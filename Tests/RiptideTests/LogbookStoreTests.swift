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
}
