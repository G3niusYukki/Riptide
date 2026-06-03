import Foundation
import Testing

@testable import Riptide

@Suite("Logbook writer")
struct LogbookWriterTests {

    private func makeWriter() async throws -> (LogbookWriter, LogbookStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("logbook-writer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = LogbookStore(paths: LogbookPaths(directory: dir))
        return (LogbookWriter(store: store), store, dir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("logInfo appends an event with info level")
    func logInfoAppends() async throws {
        let (writer, store, dir) = try await makeWriter()
        defer { cleanup(dir) }
        await writer.logInfo("hello", category: .appLifecycle, context: ["k": "v"])
        try await Task.sleep(for: .milliseconds(50))
        let results = try await store.query(.last24h())
        #expect(results.count == 1)
        if case .event(let event) = results[0] {
            #expect(event.message == "hello")
            #expect(event.level == .info)
            #expect(event.category == .appLifecycle)
            #expect(event.context == ["k": "v"])
        } else { Issue.record("expected event") }
    }

    @Test("logWarning writes warning level")
    func logWarningLevel() async throws {
        let (writer, store, dir) = try await makeWriter()
        defer { cleanup(dir) }
        await writer.logWarning("warn", category: .mihomoCore)
        try await Task.sleep(for: .milliseconds(50))
        let results = try await store.query(.last24h())
        if case .event(let event) = results[0] {
            #expect(event.level == .warning)
        } else { Issue.record("expected event") }
    }

    @Test("logError writes error level")
    func logErrorLevel() async throws {
        let (writer, store, dir) = try await makeWriter()
        defer { cleanup(dir) }
        await writer.logError("err", category: .helperInstall)
        try await Task.sleep(for: .milliseconds(50))
        let results = try await store.query(.last24h())
        if case .event(let event) = results[0] {
            #expect(event.level == .error)
        } else { Issue.record("expected event") }
    }

    @Test("empty context is allowed")
    func emptyContext() async throws {
        let (writer, store, dir) = try await makeWriter()
        defer { cleanup(dir) }
        await writer.logInfo("x", category: .diagnostic)
        try await Task.sleep(for: .milliseconds(50))
        let results = try await store.query(.last24h())
        if case .event(let event) = results[0] { #expect(event.context.isEmpty) }
        else { Issue.record("expected event") }
    }

    @Test("recordConnectionClosed writes a connectionClosed entry")
    func recordConnectionClosed() async throws {
        let (writer, store, dir) = try await makeWriter()
        defer { cleanup(dir) }
        let rec = ClosedConnectionRecord(
            id: "x", host: "h.com", proxyName: "p", protocol: "tcp",
            rule: nil, sourceIP: "127.0.0.1", sourcePort: 80,
            destinationIP: nil, destinationPort: nil,
            startedAt: Date(), closedAt: Date(),
            uploadBytes: 0, downloadBytes: 0, closeReason: .userClosed
        )
        await writer.recordConnectionClosed(rec)
        try await Task.sleep(for: .milliseconds(50))
        let results = try await store.query(.last24h())
        #expect(results.count == 1)
        if case .connectionClosed(let record) = results[0] {
            #expect(record.id == "x")
        } else { Issue.record("expected connectionClosed") }
    }

    @Test("writer is fire-and-forget; never throws")
    func fireAndForget() async throws {
        let (writer, _, dir) = try await makeWriter()
        defer { cleanup(dir) }
        // 1000 rapid calls must not throw
        for idx in 0..<1000 {
            await writer.logInfo("msg-\(idx)", category: .appLifecycle)
        }
    }
}
