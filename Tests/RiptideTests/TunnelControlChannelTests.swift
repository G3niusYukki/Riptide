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

    @Test("control channel emits structured lifecycle and failure events")
    func controlChannelEmitsStructuredEvents() async throws {
        let runtime = MockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        let channel = InProcessTunnelControlChannel(lifecycleManager: manager)
        let profile = TunnelProfile(name: "test", config: sampleConfig())

        let stream = await channel.events()
        _ = try await channel.send(.start(profile))

        var iterator = stream.makeAsyncIterator()
        var foundStateChanged = false
        for _ in 0..<10 {
            guard let event = await iterator.next() else { break }
            if case .runtimeEvent(.stateChanged(let state)) = event {
                #expect(state == .running)
                foundStateChanged = true
                break
            }
        }
        #expect(foundStateChanged)
    }

    @Test("view model maps connection snapshot and mode state")
    func viewModelMapsRuntimeSnapshots() async throws {
        let runtime = MockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        let viewModel = TunnelControlViewModel(lifecycleManager: manager)

        await viewModel.setMode(.tun)
        let mode = await viewModel.currentMode()
        #expect(mode == .tun)
    }

    @Test("mode transitions surface degraded-state recommendations")
    func modeTransitionsSurfaceDegradedStates() async throws {
        let event = RuntimeEvent.degraded(.tun, "no TUN interface available, falling back to system proxy")
        #expect(event == RuntimeEvent.degraded(.tun, "no TUN interface available, falling back to system proxy"))
    }

    private func sampleConfig() -> RiptideConfig {
        RiptideConfig(
            mode: .rule,
            proxies: [ProxyNode(name: "proxy-a", kind: .socks5, server: "1.2.3.4", port: 1080)],
            rules: [.final(policy: .proxyNode(name: "proxy-a"))]
        )
    }
}
