import Foundation
import Testing

@testable import Riptide

@Suite("Closed connection watcher")
struct ClosedConnectionWatcherTests {

    private func makeWatcher() async throws -> (ClosedConnectionWatcher, LogbookStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("logbook-watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = LogbookStore(paths: LogbookPaths(directory: dir))
        let writer = LogbookWriter(store: store)
        let fake = FakeConnectionProvider()
        let watcher = ClosedConnectionWatcher(provider: fake, writer: writer)
        return (watcher, store, dir)
    }

    @Test("first tick seeds the snapshot, no closures recorded")
    func firstTickSeeds() async throws {
        let (watcher, store, dir) = try await makeWatcher()
        defer { try? FileManager.default.removeItem(at: dir) }
        await watcher.tick()
        try await Task.sleep(for: .milliseconds(50))
        let results = try await store.query(.last24h())
        #expect(results.isEmpty)
    }

    @Test("disappearing connection is recorded as closed")
    func detectsClose() async throws {
        let (watcher, store, dir) = try await makeWatcher()
        defer { try? FileManager.default.removeItem(at: dir) }
        await watcher.setConnectionsForTest([
            makeConn(id: "a"),
            makeConn(id: "b"),
        ])
        await watcher.tick()
        await watcher.setConnectionsForTest([makeConn(id: "a")])
        await watcher.tick()
        try await Task.sleep(for: .milliseconds(50))
        let results = try await store.query(.last24h())
        let closed = results.compactMap { entry -> ClosedConnectionRecord? in
            if case .connectionClosed(let record) = entry { return record } else { return nil }
        }
        #expect(closed.count == 1)
        #expect(closed.first?.id == "b")
    }

    @Test("new connection is not a close event")
    func newConnectionIsNotClose() async throws {
        let (watcher, store, dir) = try await makeWatcher()
        defer { try? FileManager.default.removeItem(at: dir) }
        await watcher.setConnectionsForTest([makeConn(id: "a")])
        await watcher.tick()
        await watcher.setConnectionsForTest([makeConn(id: "a"), makeConn(id: "b")])
        await watcher.tick()
        try await Task.sleep(for: .milliseconds(50))
        let results = try await store.query(.last24h())
        let closed = results.compactMap { entry -> ClosedConnectionRecord? in
            if case .connectionClosed(let record) = entry { return record } else { return nil }
        }
        #expect(closed.isEmpty)
    }

    @Test("rapid open-then-close within one tick is not recorded")
    func rapidOpenClose() async throws {
        let (watcher, store, dir) = try await makeWatcher()
        defer { try? FileManager.default.removeItem(at: dir) }
        await watcher.setConnectionsForTest([makeConn(id: "a")])
        await watcher.tick()
        // Connection "b" was never observed; it is "lost to history" by design.
        await watcher.setConnectionsForTest([makeConn(id: "a")])
        await watcher.tick()
        try await Task.sleep(for: .milliseconds(50))
        let results = try await store.query(.last24h())
        #expect(results.isEmpty)
    }
}

// MARK: - Helpers

private func makeConn(id: String) -> ConnectionInfo {
    ConnectionInfo(
        id: id,
        metadata: ConnectionMetadata(
            network: "tcp",
            type: "tcp",
            sourceIP: "127.0.0.1",
            sourcePort: "54321",
            destinationIP: "203.0.113.5",
            destinationPort: "443",
            host: "example.com"
        ),
        upload: 0,
        download: 0,
        start: nil,
        rule: nil,
        rulePayload: nil,
        chains: []
    )
}

/// Test fake that lets us inject a connection list for the next `currentConnections()`.
actor FakeConnectionProvider: ConnectionProvider {
    private var nextList: [ConnectionInfo] = []

    func currentConnections() async -> [ConnectionInfo] { nextList }

    func set(_ conns: [ConnectionInfo]) { nextList = conns }
}
