import Foundation
import Testing

@testable import Riptide

@Suite("Tunnel lifecycle")
struct TunnelLifecycleTests {
    @Test("start transitions to running and binds active profile")
    func startSuccess() async throws {
        let runtime = MockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        let config = TunnelProfile(name: "default", config: sampleConfig())

        try await manager.start(profile: config)
        let status = await manager.status()

        #expect(status.state == .running)
        #expect(status.activeProfileName == "default")
    }

    @Test("start failure transitions to error")
    func startFailure() async throws {
        let runtime = MockTunnelRuntime(startError: TunnelRuntimeError.startFailed("boom"))
        let manager = TunnelLifecycleManager(runtime: runtime)
        let config = TunnelProfile(name: "default", config: sampleConfig())

        await #expect(throws: TunnelRuntimeError.self) {
            try await manager.start(profile: config)
        }

        let status = await manager.status()
        #expect(status.state == .error)
        #expect(status.lastError?.contains("boom") == true)
    }

    @Test("update before start is rejected")
    func updateRequiresRunning() async throws {
        let runtime = MockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        let config = TunnelProfile(name: "default", config: sampleConfig())

        await #expect(throws: TunnelLifecycleError.self) {
            try await manager.update(profile: config)
        }
    }

    @Test("stop from running returns stopped state")
    func stopFromRunning() async throws {
        let runtime = MockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        let config = TunnelProfile(name: "default", config: sampleConfig())

        try await manager.start(profile: config)
        try await manager.stop()

        let status = await manager.status()
        #expect(status.state == .stopped)
        #expect(status.activeProfileName == nil)
    }

    @Test("status exposes runtime counters")
    func statusCounters() async throws {
        let runtime = MockTunnelRuntime(statusOverride: TunnelRuntimeStatus(bytesUp: 10, bytesDown: 20, activeConnections: 3))
        let manager = TunnelLifecycleManager(runtime: runtime)
        let config = TunnelProfile(name: "default", config: sampleConfig())

        try await manager.start(profile: config)
        let status = await manager.status()

        #expect(status.bytesUp == 10)
        #expect(status.bytesDown == 20)
        #expect(status.activeConnections == 3)
    }

    private func sampleConfig() -> RiptideConfig {
        RiptideConfig(
            mode: .rule,
            proxies: [ProxyNode(name: "proxy-a", kind: .socks5, server: "1.2.3.4", port: 1080)],
            rules: [.final(policy: .proxyNode(name: "proxy-a"))]
        )
    }
}
