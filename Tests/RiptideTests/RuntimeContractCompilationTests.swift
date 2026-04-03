import Foundation
import Testing

@testable import Riptide

@Suite("Runtime contract compilation")
struct RuntimeContractCompilationTests {
    // MARK: - Platform / System Integration Workstream

    @Test("RuntimeMode has systemProxy and tun cases")
    func runtimeModeHasExpectedCases() {
        let systemProxy = RuntimeMode.systemProxy
        let tun = RuntimeMode.tun
        #expect(systemProxy == .systemProxy)
        #expect(tun == .tun)
        #expect(systemProxy != tun)
    }

    @Test("TunnelControlViewModel supports mode access and mutation")
    func viewModelModeAccess() async {
        let runtime = MockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        let viewModel = TunnelControlViewModel(lifecycleManager: manager)

        let initial = await viewModel.currentMode()
        #expect(initial == .systemProxy)

        await viewModel.setMode(.tun)
        let updated = await viewModel.currentMode()
        #expect(updated == .tun)
    }

    @Test("RuntimeEvent carries mode and state transitions")
    func runtimeEventCarriesModeAndState() {
        let stateEvent = RuntimeEvent.stateChanged(.running)
        let modeEvent = RuntimeEvent.modeChanged(.systemProxy)
        let degradedEvent = RuntimeEvent.degraded(.tun, "fallback reason")

        #expect(stateEvent == .stateChanged(.running))
        #expect(modeEvent == .modeChanged(.systemProxy))
        #expect(degradedEvent == .degraded(.tun, "fallback reason"))
    }

    // MARK: - TUN Provider Messaging Workstream

    @Test("RuntimeConnectionSnapshot is constructible and equatable")
    func connectionSnapshotConstructible() {
        let id = UUID()
        let snapshot = RuntimeConnectionSnapshot(
            id: id,
            targetHost: "example.com",
            targetPort: 443,
            routeDescription: "proxy-a"
        )
        #expect(snapshot.id == id)
        #expect(snapshot.targetHost == "example.com")
        #expect(snapshot.targetPort == 443)
        #expect(snapshot.routeDescription == "proxy-a")

        let duplicate = RuntimeConnectionSnapshot(
            id: id,
            targetHost: "example.com",
            targetPort: 443,
            routeDescription: "proxy-a"
        )
        #expect(snapshot == duplicate)
    }

    @Test("RuntimeErrorSnapshot is constructible and equatable")
    func errorSnapshotConstructible() {
        let fixedDate = Date(timeIntervalSince1970: 0)
        let error = RuntimeErrorSnapshot(code: "E_DIAL", message: "connection refused", timestamp: fixedDate)
        #expect(error.code == "E_DIAL")
        #expect(error.message == "connection refused")

        let duplicate = RuntimeErrorSnapshot(code: "E_DIAL", message: "connection refused", timestamp: fixedDate)
        #expect(error == duplicate)
    }

    @Test("RuntimeEvent connection and error variants are equatable")
    func runtimeEventConnectionAndErrorVariants() {
        let connID = UUID()
        let conn = RuntimeConnectionSnapshot(
            id: connID, targetHost: "host", targetPort: 80, routeDescription: "DIRECT"
        )
        let fixedDate = Date(timeIntervalSince1970: 0)
        let opened = RuntimeEvent.connectionOpened(conn)
        let closed = RuntimeEvent.connectionClosed(connID)
        let error = RuntimeEvent.error(
            RuntimeErrorSnapshot(code: "E_TIMEOUT", message: "timed out", timestamp: fixedDate)
        )

        #expect(opened == .connectionOpened(conn))
        #expect(closed == .connectionClosed(connID))
        #expect(error == .error(RuntimeErrorSnapshot(code: "E_TIMEOUT", message: "timed out", timestamp: fixedDate)))
    }

    // MARK: - Profile Persistence and Runtime Reload Workstream

    @Test("TunnelProfile is constructible with a config")
    func tunnelProfileConstructible() {
        let config = RiptideConfig(
            mode: .rule,
            proxies: [ProxyNode(name: "p", kind: .socks5, server: "1.2.3.4", port: 1080)],
            rules: [.final(policy: .proxyNode(name: "p"))]
        )
        let profile = TunnelProfile(name: "test-profile", config: config)
        #expect(profile.name == "test-profile")
        #expect(profile.config.mode == .rule)
    }

    @Test("InProcessTunnelControlChannel accepts start and status commands")
    func controlChannelAcceptsCommands() async throws {
        let runtime = MockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        let channel = InProcessTunnelControlChannel(lifecycleManager: manager)
        let profile = TunnelProfile(name: "test", config: RiptideConfig(
            mode: .rule,
            proxies: [ProxyNode(name: "p", kind: .socks5, server: "1.2.3.4", port: 1080)],
            rules: [.final(policy: .proxyNode(name: "p"))]
        ))

        let response = try await channel.send(.start(profile))
        #expect(response == .ack)

        let statusResponse = try await channel.send(.status)
        if case .status(let snapshot) = statusResponse {
            #expect(snapshot.state == .running)
        } else {
            Issue.record("Expected status response")
        }
    }

    @Test("RuntimeControlSurface carries mode context")
    func controlSurfaceCarriesMode() {
        let surface = RuntimeControlSurface(mode: .tun)
        #expect(surface.mode == .tun)

        let systemProxySurface = RuntimeControlSurface(mode: .systemProxy)
        #expect(systemProxySurface.mode == .systemProxy)
    }
}
