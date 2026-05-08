import Foundation
import Testing
@testable import Riptide

// MARK: - SystemProxyGuard + Monitor Integration with ModeCoordinator

@Suite("SystemProxyGuard Integration with ModeCoordinator")
struct SystemProxyGuardIntegrationTests {

    @Test("Guard is active when system proxy mode starts with injected controller")
    func guardStartsWithSystemProxyMode() async throws {
        let manager = MockMihomoRuntimeManager()
        let controller = MockSystemProxyController()
        let coordinator = ModeCoordinator(mihomoManager: manager, systemProxyController: controller)

        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .systemProxy, profile: profile)

        let guarded = await coordinator.isSystemProxyGuarded()
        #expect(guarded == true)

        try await coordinator.stop()
    }

    @Test("Guard is not active in TUN mode")
    func guardNotActiveInTunMode() async throws {
        let manager = MockMihomoRuntimeManager()
        let controller = MockSystemProxyController()
        let coordinator = ModeCoordinator(mihomoManager: manager, systemProxyController: controller)

        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .tun, profile: profile)

        let guarded = await coordinator.isSystemProxyGuarded()
        #expect(guarded == false)

        try await coordinator.stop()
    }

    @Test("Guard is deactivated when coordinator stops")
    func guardStopsWithCoordinator() async throws {
        let manager = MockMihomoRuntimeManager()
        let controller = MockSystemProxyController()
        let coordinator = ModeCoordinator(mihomoManager: manager, systemProxyController: controller)

        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .systemProxy, profile: profile)
        let guardedDuringRun = await coordinator.isSystemProxyGuarded()
        #expect(guardedDuringRun == true)

        try await coordinator.stop()
        let guardedAfterStop = await coordinator.isSystemProxyGuarded()
        #expect(guardedAfterStop == false)
    }

    @Test("Guard sets expected HTTP port on system proxy")
    func guardSetsExpectedPort() async throws {
        let manager = MockMihomoRuntimeManager()
        let controller = MockSystemProxyController()
        let coordinator = ModeCoordinator(mihomoManager: manager, systemProxyController: controller)

        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .systemProxy, profile: profile)

        // The guard should have enabled the system proxy at the default port
        let state = controller.currentState()
        if case .enabled(let httpPort, _) = state {
            #expect(httpPort == ModeCoordinator.defaultHTTPPort)
        } else {
            Issue.record("Expected system proxy to be enabled after guard setup")
        }

        try await coordinator.stop()
    }

    @Test("Guard is not started when no controller injected and helper not installed")
    func guardSkippedWithoutController() async throws {
        let manager = MockMihomoRuntimeManager()
        // No systemProxyController injected — guard should be skipped
        let coordinator = ModeCoordinator(mihomoManager: manager)

        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .systemProxy, profile: profile)

        let guarded = await coordinator.isSystemProxyGuarded()
        #expect(guarded == false)

        try await coordinator.stop()
    }

    @Test("Guard survives start failure gracefully")
    func guardSurvivesFailureGracefully() async throws {
        let manager = MockMihomoRuntimeManager()
        let controller = MockSystemProxyController()
        let coordinator = ModeCoordinator(mihomoManager: manager, systemProxyController: controller)

        // Configure mock to fail on start
        await manager.configureThrowOnStart(RuntimeError.configGenerationFailed("test error"))

        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        do {
            try await coordinator.start(mode: .systemProxy, profile: profile)
            Issue.record("Expected start to throw")
        } catch {
            // Guard should not be active after failed start
            let guarded = await coordinator.isSystemProxyGuarded()
            #expect(guarded == false)
        }
    }
}
