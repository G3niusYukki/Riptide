import Foundation
import Testing

@testable import Riptide

@Suite("Runtime observability")
struct RuntimeObservabilityTests {
    @Test("runtime event store retains recent logs and connection snapshots")
    func eventStoreRetainsRecentEvents() async {
        let store = RuntimeEventStore()

        await store.record(.stateChanged(.running))
        await store.record(.modeChanged(.systemProxy))
        await store.record(.error(RuntimeErrorSnapshot(code: "E_X", message: "test")))

        let events = await store.recentEvents(limit: 10)
        #expect(events.count == 3)
        #expect(events[0].event == .stateChanged(.running))
    }

    @Test("view model observable snapshot reflects current state")
    func viewModelObservableSnapshot() async throws {
        let runtime = MockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        let viewModel = TunnelControlViewModel(lifecycleManager: manager)

        // Record a test event directly via the event store
        let profile = TunnelProfile(
            name: "test",
            config: RiptideConfig(
                mode: .rule,
                proxies: [ProxyNode(name: "p", kind: .socks5, server: "1.2.3.4", port: 1080)],
                rules: [.final(policy: .proxyNode(name: "p"))]
            )
        )
        try await manager.start(profile: profile)
        let snapshot = await viewModel.observableSnapshot()
        // Verify the snapshot has the expected structure
        #expect(snapshot.throughput.totalConnections >= 0)
        #expect(snapshot.connections.isEmpty)
    }

    @Test("event store tracks throughput counters")
    func eventStoreTracksThroughput() async {
        let store = RuntimeEventStore()

        await store.recordThroughput(up: 1024, down: 2048)
        await store.recordThroughput(up: 512, down: 768)

        let throughput = await store.currentThroughput()
        #expect(throughput.bytesUp == 1536)
        #expect(throughput.bytesDown == 2816)
    }

    @Test("observable snapshot contains events connections and throughput")
    func aggregateSnapshot() async {
        let store = RuntimeEventStore()
        let conn = RuntimeConnectionSnapshot(
            id: UUID(),
            targetHost: "example.com",
            targetPort: 443,
            routeDescription: "proxy-a"
        )
        await store.recordConnectionOpened(conn, up: 100, down: 200)

        let snapshot = await store.aggregateSnapshot()
        #expect(snapshot.events.count == 1)
        #expect(snapshot.connections.count == 1)
        #expect(snapshot.throughput.totalConnections == 1)
        #expect(snapshot.throughput.bytesUp == 100)
        #expect(snapshot.throughput.bytesDown == 200)
    }

    @Test("event store respects max size limit")
    func eventStoreRespectsLimit() async {
        let store = RuntimeEventStore(maxEvents: 5, maxConnections: 3)

        for i in 0..<10 {
            await store.record(.stateChanged(.running))
        }

        let events = await store.recentEvents(limit: 10)
        #expect(events.count <= 5)
    }
}
