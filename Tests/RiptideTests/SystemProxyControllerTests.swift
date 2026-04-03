import Foundation
import Testing

@testable import Riptide

@Suite("System proxy controller")
struct SystemProxyControllerTests {
    @Test("mock controller starts in disabled state")
    func mockStartsDisabled() throws {
        let controller = MockSystemProxyController()
        let state = try controller.currentState()
        #expect(state == .disabled)
    }

    @Test("mock controller enables and reports correct state")
    func mockEnableAndState() throws {
        let controller = MockSystemProxyController()
        try controller.enable(httpPort: 6152, socksPort: nil)
        let state = try controller.currentState()
        if case .enabled(let httpPort, let socksPort) = state {
            #expect(httpPort == 6152)
            #expect(socksPort == nil)
        } else {
            Issue.record("Expected enabled state")
        }
    }

    @Test("mock controller disables and returns disabled state")
    func mockDisable() throws {
        let controller = MockSystemProxyController()
        try controller.enable(httpPort: 6152, socksPort: 1080)
        try controller.disable()
        let state = try controller.currentState()
        #expect(state == .disabled)
    }
}

@Suite("Mode coordinator")
struct ModeCoordinatorTests {
    @Test("mode coordinator starts in system proxy mode")
    func coordinatorStartsSystemProxy() async throws {
        let controller = MockSystemProxyController()
        let coordinator = ModeCoordinator(
            systemProxyController: controller,
            lifecycleManager: nil
        )
        let mode = await coordinator.currentMode()
        #expect(mode == .systemProxy)
    }

    @Test("mode coordinator enables system proxy mode")
    func coordinatorStartsSystemProxyMode() async throws {
        let controller = MockSystemProxyController()
        let coordinator = ModeCoordinator(
            systemProxyController: controller,
            lifecycleManager: nil
        )
        try await coordinator.start(mode: .systemProxy, profile: nil)
        let state = try controller.currentState()
        #expect(state == .enabled(httpPort: 6152, socksPort: nil))
    }

    @Test("mode coordinator surfaces fallback recommendation when mode start fails")
    func coordinatorSurfacesFallbackRecommendation() async throws {
        let failingController = FailingSystemProxyController()
        let coordinator = ModeCoordinator(
            systemProxyController: failingController,
            lifecycleManager: nil
        )
        do {
            try await coordinator.start(mode: .systemProxy, profile: nil)
            Issue.record("Expected an error to be thrown")
        } catch {
            // Expected — the coordinator should throw after emitting the degraded event
        }
        let events = await coordinator.recentEvents()
        let hasDegraded = events.contains { event in
            if case .degraded(.systemProxy, _) = event { return true }
            return false
        }
        #expect(hasDegraded)
    }

    @Test("mode coordinator stops and disables proxy")
    func coordinatorStop() async throws {
        let controller = MockSystemProxyController()
        let coordinator = ModeCoordinator(
            systemProxyController: controller,
            lifecycleManager: nil
        )
        try await coordinator.start(mode: .systemProxy, profile: nil)
        try await coordinator.stop()
        let state = try controller.currentState()
        #expect(state == .disabled)
    }
}
