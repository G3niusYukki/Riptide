import Foundation
import Testing

@testable import Riptide

@Suite("Logbook store")
struct LogbookStoreTests {

    // MARK: - Helpers

    private func makeStore() async throws -> (LogbookStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("logbook-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let paths = LogbookPaths(directory: dir)
        return (LogbookStore(paths: paths), dir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeEvent(message: String, at date: Date = Date()) -> LogbookEntry {
        .event(LogEvent(
            id: UUID(),
            timestamp: date,
            level: .info,
            category: .appLifecycle,
            message: message,
            context: [:]
        ))
    }

    // MARK: - Tests

    @Test("append writes one line per entry")
    func appendWritesOneLine() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }
        try await store.append(makeEvent(message: "hello"))
        try await store.flush()
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )
        #expect(files.count == 1)
        let content = try String(contentsOf: files[0], encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 1)
        #expect(lines[0].contains("hello"))
    }

    @Test("multiple appends to same day append to same file")
    func multipleAppendsSameDay() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }
        for i in 0..<10 {
            try await store.append(makeEvent(message: "msg-\(i)"))
        }
        try await store.flush()
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )
        #expect(files.count == 1)
        let content = try String(contentsOf: files[0], encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 10)
    }

    @Test("midnight UTC roll creates a new file")
    func midnightRollCreatesNewFile() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }
        // Use a UTC calendar so the dates straddle UTC midnight regardless of host TZ.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 1
        c.hour = 23; c.minute = 59; c.second = 59
        let before = utc.date(from: c)!
        c.day = 2; c.hour = 0; c.minute = 0; c.second = 1
        let after = utc.date(from: c)!
        try await store.append(makeEvent(message: "before", at: before))
        try await store.append(makeEvent(message: "after", at: after))
        try await store.flush()
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )
        #expect(files.count == 2)
        let names = Set(files.map { $0.lastPathComponent })
        #expect(names.contains("2026-06-01.jsonl"))
        #expect(names.contains("2026-06-02.jsonl"))
    }

    @Test("totalSize sums across all files")
    func totalSize() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }
        try await store.append(makeEvent(message: String(repeating: "x", count: 100)))
        try await store.append(makeEvent(message: String(repeating: "y", count: 100)))
        try await store.flush()
        let size = await store.totalSize()
        #expect(size > 200)
    }

    // MARK: - query(_:)

    @Test("query returns appended entries within range")
    func queryReturnsAppended() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }
        let now = Date()
        try await store.append(makeEvent(message: "a", at: now.addingTimeInterval(-3600)))
        try await store.append(makeEvent(message: "b", at: now))
        try await store.flush()
        let results = try await store.query(.last24h())
        #expect(results.count == 2)
    }

    @Test("query filters by level")
    func queryFiltersByLevel() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }
        let now = Date()
        try await store.append(.event(LogEvent(
            id: UUID(), timestamp: now, level: .info, category: .appLifecycle,
            message: "info", context: [:]
        )))
        try await store.append(.event(LogEvent(
            id: UUID(), timestamp: now, level: .error, category: .appLifecycle,
            message: "error", context: [:]
        )))
        try await store.flush()
        var q = LogbookQuery.last24h()
        q.levels = [.error]
        let results = try await store.query(q)
        #expect(results.count == 1)
        if case .event(let e) = results[0] { #expect(e.level == .error) }
        else { Issue.record("expected event") }
    }

    @Test("query filters by category")
    func queryFiltersByCategory() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }
        let now = Date()
        try await store.append(.event(LogEvent(
            id: UUID(), timestamp: now, level: .info, category: .mihomoCore,
            message: "m", context: [:]
        )))
        try await store.append(.event(LogEvent(
            id: UUID(), timestamp: now, level: .info, category: .appLifecycle,
            message: "a", context: [:]
        )))
        try await store.flush()
        var q = LogbookQuery.last24h()
        q.categories = [.mihomoCore]
        let results = try await store.query(q)
        #expect(results.count == 1)
    }

    @Test("query skips malformed lines")
    func querySkipsMalformed() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }
        try await store.append(makeEvent(message: "ok-1"))
        try await store.append(makeEvent(message: "ok-2"))
        try await store.flush()
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )
        let today = files[0]
        let handle = try FileHandle(forWritingTo: today)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\nnot-json\n".utf8))
        try handle.close()
        try await store.append(makeEvent(message: "ok-3"))
        try await store.flush()
        let results = try await store.query(.last24h())
        #expect(results.count == 3)
    }

    @Test("query filters connectionClosed by host")
    func queryFiltersByHost() async throws {
        let (store, dir) = try await makeStore()
        defer { cleanup(dir) }
        let now = Date()
        let rec1 = ClosedConnectionRecord(
            id: "1", host: "example.com", proxyName: "p1", protocol: "tcp",
            rule: nil, sourceIP: "127.0.0.1", sourcePort: 80,
            destinationIP: nil, destinationPort: nil,
            startedAt: now, closedAt: now,
            uploadBytes: 0, downloadBytes: 0, closeReason: .expired
        )
        let rec2 = ClosedConnectionRecord(
            id: "2", host: "other.com", proxyName: "p1", protocol: "tcp",
            rule: nil, sourceIP: "127.0.0.1", sourcePort: 80,
            destinationIP: nil, destinationPort: nil,
            startedAt: now, closedAt: now,
            uploadBytes: 0, downloadBytes: 0, closeReason: .expired
        )
        try await store.append(.connectionClosed(rec1))
        try await store.append(.connectionClosed(rec2))
        try await store.flush()
        var q = LogbookQuery.last24h()
        q.hostContains = "example"
        let results = try await store.query(q)
        #expect(results.count == 1)
    }
}
