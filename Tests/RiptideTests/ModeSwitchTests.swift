import Foundation
import Testing
@testable import Riptide

// MARK: - Mode Switching Tests

@Suite("Mode Switching")
struct ModeSwitchTests {

    @Test("switchMode transitions from systemProxy to TUN")
    func switchFromSystemProxyToTUN() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .systemProxy, profile: profile)
        let mode1 = await coordinator.currentMode()
        #expect(mode1 == .systemProxy)

        try await coordinator.switchMode(to: .tun, profile: profile)
        let mode2 = await coordinator.currentMode()
        #expect(mode2 == .tun)

        try await coordinator.stop()
    }

    @Test("switchMode transitions from TUN to systemProxy")
    func switchFromTUNToSystemProxy() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .tun, profile: profile)
        let mode1 = await coordinator.currentMode()
        #expect(mode1 == .tun)

        try await coordinator.switchMode(to: .systemProxy, profile: profile)
        let mode2 = await coordinator.currentMode()
        #expect(mode2 == .systemProxy)

        try await coordinator.stop()
    }

    @Test("switchMode stops previous mode before starting new one")
    func switchModeStopsAndStarts() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        // Start in system proxy
        try await coordinator.start(mode: .systemProxy, profile: profile)
        #expect(await manager.isRunning)

        // Switch to TUN — should stop then start
        try await coordinator.switchMode(to: .tun, profile: profile)
        #expect(await manager.isRunning)
        let mode = await manager.currentMode
        #expect(mode == .tun)

        try await coordinator.stop()
    }

    @Test("switchMode emits correct events")
    func switchModeEmitsEvents() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        try await coordinator.start(mode: .systemProxy, profile: profile)
        try await coordinator.switchMode(to: .tun, profile: profile)

        let events = await coordinator.recentEvents()
        // Should have modeChanged events for both modes
        let hasSystemProxyEvent = events.contains { event in
            if case .modeChanged(.systemProxy) = event { return true }
            return false
        }
        let hasTUNEvent = events.contains { event in
            if case .modeChanged(.tun) = event { return true }
            return false
        }
        #expect(hasSystemProxyEvent)
        #expect(hasTUNEvent)

        try await coordinator.stop()
    }

    @Test("switchMode works when runtime is not running")
    func switchModeWhenNotRunning() async throws {
        let manager = MockMihomoRuntimeManager()
        let coordinator = ModeCoordinator(mihomoManager: manager)
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
        let profile = TunnelProfile(name: "test", config: config)

        // Don't start first — switchMode should handle this gracefully
        try await coordinator.switchMode(to: .tun, profile: profile)
        let mode = await coordinator.currentMode()
        #expect(mode == .tun)

        try await coordinator.stop()
    }
}
