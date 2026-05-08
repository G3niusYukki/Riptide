import Foundation
import Testing
@testable import Riptide

// MARK: - Health Check Integration Tests

@Suite("Health Check Integration with ModeCoordinator")
struct HealthCheckIntegrationTests {

    @Test("Health results are empty before any checks")
    func healthResultsEmptyBeforeChecks() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)

        let results = await coordinator.allHealthResults()
        #expect(results.isEmpty)
    }

    @Test("testAllProxies stores results for each proxy")
    func testAllProxiesStoresResults() async throws {
        let manager = MockMihomoRuntimeManager()
        // Configure mock delays
        await manager.configureMockDelay(42, for: "fast-node")
        await manager.configureMockDelay(200, for: "slow-node")

        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        // Start the coordinator to set up the API client
        try await coordinator.start(mode: .systemProxy, profile: profile)

        let proxies = [
            ProxyNode(name: "fast-node", kind: .socks5, server: "1.1.1.1", port: 1080),
            ProxyNode(name: "slow-node", kind: .socks5, server: "2.2.2.2", port: 1080)
        ]

        await coordinator.testAllProxies(proxies: proxies)

        let results = await coordinator.allHealthResults()
        #expect(results.count == 2)
        #expect(results["fast-node"]?.latency == 42)
        #expect(results["fast-node"]?.alive == true)
        #expect(results["slow-node"]?.latency == 200)
        #expect(results["slow-node"]?.alive == true)

        try await coordinator.stop()
    }

    @Test("Health result shows dead proxy when delay test fails")
    func deadProxyOnDelayFailure() async throws {
        let manager = MockMihomoRuntimeManager()
        await manager.configureFailDelay(for: "dead-node")

        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .systemProxy, profile: profile)

        let proxies = [
            ProxyNode(name: "dead-node", kind: .socks5, server: "1.1.1.1", port: 1080)
        ]

        await coordinator.testAllProxies(proxies: proxies)

        let result = await coordinator.healthResult(for: "dead-node")
        #expect(result != nil)
        #expect(result?.alive == false)
        #expect(result?.latency == nil)

        try await coordinator.stop()
    }

    @Test("Health results are cleared on stop")
    func healthResultsClearedOnStop() async throws {
        let manager = MockMihomoRuntimeManager()
        await manager.configureMockDelay(50, for: "node-1")

        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .systemProxy, profile: profile)

        let proxies = [ProxyNode(name: "node-1", kind: .socks5, server: "1.1.1.1", port: 1080)]
        await coordinator.testAllProxies(proxies: proxies)

        let resultsDuringRun = await coordinator.allHealthResults()
        #expect(resultsDuringRun.count == 1)

        try await coordinator.stop()

        let resultsAfterStop = await coordinator.allHealthResults()
        #expect(resultsAfterStop.isEmpty)
    }
}
