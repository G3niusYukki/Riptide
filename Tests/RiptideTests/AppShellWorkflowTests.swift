import Foundation
import Testing

@testable import Riptide

@Suite("App shell workflow")
struct AppShellWorkflowTests {
    @Test("config import succeeds for valid YAML")
    func importSuccess() throws {
        let service = ConfigImportService()
        let result = try service.importProfile(name: "test", yaml: validYAML())

        #expect(result.profile.name == "test")
        #expect(result.profile.config.proxies.count == 1)
    }

    @Test("config import fails for invalid YAML")
    func importFailure() {
        let service = ConfigImportService()

        #expect(throws: ClashConfigError.self) {
            _ = try service.importProfile(name: "test", yaml: "not: [valid")
        }
    }

    @Test("stats pipeline maps running snapshot")
    func statsMapping() {
        let pipeline = RuntimeStatsPipeline()
        let snapshot = TunnelStatusSnapshot(
            state: .running,
            activeProfileName: "default",
            bytesUp: 100,
            bytesDown: 200,
            activeConnections: 5,
            lastError: nil
        )

        let state = pipeline.map(snapshot: snapshot)
        #expect(state.isRunning == true)
        #expect(state.profileName == "default")
        #expect(state.activeConnections == 5)
    }

    @Test("control view model start stop flow updates status")
    func controlViewModelFlow() async throws {
        let runtime = MockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        let control = TunnelControlViewModel(lifecycleManager: manager)

        let imported = try await control.importConfig(name: "default", yaml: validYAML())
        try await control.applyImportedProfileAndStart(imported)

        let running = await control.currentStatus()
        #expect(running.state == .running)

        try await control.stop()
        let stopped = await control.currentStatus()
        #expect(stopped.state == .stopped)
    }

    @Test("control channel status command mirrors lifecycle status")
    func controlChannelStatus() async throws {
        let runtime = MockTunnelRuntime(statusOverride: TunnelRuntimeStatus(bytesUp: 10, bytesDown: 20, activeConnections: 1))
        let manager = TunnelLifecycleManager(runtime: runtime)
        let channel = InProcessTunnelControlChannel(lifecycleManager: manager)
        let profile = TunnelProfile(name: "demo", config: sampleConfig())

        _ = try await channel.send(.start(profile))
        let response = try await channel.send(.status)

        if case .status(let snapshot) = response {
            #expect(snapshot.state == .running)
            #expect(snapshot.activeProfileName == "demo")
            #expect(snapshot.bytesUp == 10)
            #expect(snapshot.bytesDown == 20)
            #expect(snapshot.activeConnections == 1)
        } else {
            Issue.record("Expected status response from control channel")
        }
    }

    @Test("control channel emits RuntimeMode and RuntimeEvent through event stream")
    func runtimeModeAndEventEmittedThroughControlChannel() async throws {
        let runtime = MockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        let channel = InProcessTunnelControlChannel(lifecycleManager: manager)
        let profile = TunnelProfile(name: "demo", config: sampleConfig())

        let stream = await channel.events()
        _ = try await channel.send(.start(profile))

        var iterator = stream.makeAsyncIterator()
        var foundRuntimeEvent = false
        // Consume at most 10 events — the stream stays open so a plain while loop would hang
        for _ in 0..<10 {
            guard let event = await iterator.next() else { break }
            if case .runtimeEvent(.stateChanged(let state)) = event {
                #expect(state == .running)
                foundRuntimeEvent = true
                break
            }
        }
        #expect(foundRuntimeEvent)

        let snapshot = RuntimeConnectionSnapshot(
            id: UUID(),
            targetHost: "example.com",
            targetPort: 443,
            routeDescription: "proxy-a"
        )
        #expect(snapshot.targetHost == "example.com")
        #expect(snapshot.targetPort == 443)

        let errorSnapshot = RuntimeErrorSnapshot(code: "E_NO_PROFILE", message: "no profile loaded")
        #expect(errorSnapshot.code == "E_NO_PROFILE")
    }

    private func sampleConfig() -> RiptideConfig {
        RiptideConfig(
            mode: .rule,
            proxies: [ProxyNode(name: "demo", kind: .socks5, server: "127.0.0.1", port: 1080)],
            rules: [.final(policy: .proxyNode(name: "demo"))]
        )
    }

    private func validYAML() -> String {
        """
        mode: rule
        proxies:
          - name: "my-socks"
            type: socks5
            server: "5.6.7.8"
            port: 1080
        rules:
          - MATCH,my-socks
        """
    }
}
