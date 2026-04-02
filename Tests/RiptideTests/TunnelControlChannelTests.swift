import Foundation
import Testing

@testable import Riptide

@Suite("Tunnel control channel")
struct TunnelControlChannelTests {
    @Test("start and status commands return running snapshot")
    func startAndStatus() async throws {
        let runtime = MockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        let channel = InProcessTunnelControlChannel(lifecycleManager: manager)
        let profile = TunnelProfile(name: "test", config: sampleConfig())

        let startResponse = try await channel.send(.start(profile))
        #expect(startResponse == .ack)

        let statusResponse = try await channel.send(.status)
        if case .status(let snapshot) = statusResponse {
            #expect(snapshot.state == .running)
            #expect(snapshot.activeProfileName == "test")
        } else {
            Issue.record("Expected status response")
        }
    }

    @Test("stop command transitions to stopped")
    func stopCommand() async throws {
        let runtime = MockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        let channel = InProcessTunnelControlChannel(lifecycleManager: manager)
        let profile = TunnelProfile(name: "test", config: sampleConfig())

        _ = try await channel.send(.start(profile))
        _ = try await channel.send(.stop)
        let statusResponse = try await channel.send(.status)

        if case .status(let snapshot) = statusResponse {
            #expect(snapshot.state == .stopped)
        } else {
            Issue.record("Expected status response")
        }
    }

    @Test("failing runtime emits error response and event")
    func errorPath() async throws {
        let runtime = MockTunnelRuntime(startError: .startFailed("boom"))
        let manager = TunnelLifecycleManager(runtime: runtime)
        let channel = InProcessTunnelControlChannel(lifecycleManager: manager)
        let profile = TunnelProfile(name: "test", config: sampleConfig())

        let stream = await channel.events()
        let response = try await channel.send(.start(profile))
        if case .error(let message) = response {
            #expect(message.contains("boom"))
        } else {
            Issue.record("Expected error response")
        }

        var iterator = stream.makeAsyncIterator()
        if let event = await iterator.next() {
            if case .error(let message) = event {
                #expect(message.contains("boom"))
            } else {
                Issue.record("Expected error event")
            }
        } else {
            Issue.record("Expected at least one event")
        }
    }

    private func sampleConfig() -> RiptideConfig {
        RiptideConfig(
            mode: .rule,
            proxies: [ProxyNode(name: "proxy-a", kind: .socks5, server: "1.2.3.4", port: 1080)],
            rules: [.final(policy: .proxyNode(name: "proxy-a"))]
        )
    }
}
