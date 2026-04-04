import Foundation
import Testing
@testable import Riptide

// MARK: - System Proxy Guard Tests

@Suite("System Proxy Guard")
struct SystemProxyGuardTests {

    @Test("guard starts in disabled state")
    func guardStartsDisabled() async {
        let mockController = MockSystemProxyController()
        let proxyGuard = SystemProxyGuard(controller: mockController)

        let isEnabled = await proxyGuard.isEnabled()
        #expect(isEnabled == false)
    }

    @Test("enable starts monitoring with expected settings")
    func enableStartsMonitoring() async throws {
        let mockController = MockSystemProxyController()
        let proxyGuard = SystemProxyGuard(controller: mockController)

        try await proxyGuard.enable(expectedHTTPPort: 6152, expectedSOCKSPort: 6153)

        let isEnabled = await proxyGuard.isEnabled()
        #expect(isEnabled == true)
    }

    @Test("disable stops monitoring")
    func disableStopsMonitoring() async throws {
        let mockController = MockSystemProxyController()
        let proxyGuard = SystemProxyGuard(controller: mockController)

        try await proxyGuard.enable(expectedHTTPPort: 6152, expectedSOCKSPort: 6153)
        await proxyGuard.disable()

        let isEnabled = await proxyGuard.isEnabled()
        #expect(isEnabled == false)
    }

    @Test("guard detects when proxy is disabled externally")
    func detectsExternalDisable() async throws {
        let mockController = MockSystemProxyController()
        let proxyGuard = SystemProxyGuard(controller: mockController)

        // Enable guard and set proxy
        try await mockController.enable(httpPort: 6152, socksPort: 6153)
        try await proxyGuard.enable(expectedHTTPPort: 6152, expectedSOCKSPort: 6153)

        // Simulate external disable
        try await mockController.disable()

        // Check should detect the change
        let violation = await proxyGuard.checkForViolation()
        #expect(violation == true)
    }

    @Test("guard detects when proxy port is changed externally")
    func detectsPortChange() async throws {
        let mockController = MockSystemProxyController()
        let proxyGuard = SystemProxyGuard(controller: mockController)

        // Enable guard with expected port 6152
        try await mockController.enable(httpPort: 6152, socksPort: nil)
        try await proxyGuard.enable(expectedHTTPPort: 6152, expectedSOCKSPort: nil)

        // Simulate external change to different port
        try await mockController.enable(httpPort: 8080, socksPort: nil)

        let violation = await proxyGuard.checkForViolation()
        #expect(violation == true)
    }

    @Test("guard does not report violation when settings are correct")
    func noViolationWhenCorrect() async throws {
        let mockController = MockSystemProxyController()
        let proxyGuard = SystemProxyGuard(controller: mockController)

        try await mockController.enable(httpPort: 6152, socksPort: 6153)
        try await proxyGuard.enable(expectedHTTPPort: 6152, expectedSOCKSPort: 6153)

        let violation = await proxyGuard.checkForViolation()
        #expect(violation == false)
    }

    @Test("restore resets proxy to expected settings")
    func restoreSettings() async throws {
        let mockController = MockSystemProxyController()
        let proxyGuard = SystemProxyGuard(controller: mockController)

        // Setup and change externally
        try await mockController.enable(httpPort: 6152, socksPort: nil)
        try await proxyGuard.enable(expectedHTTPPort: 6152, expectedSOCKSPort: nil)
        try await mockController.enable(httpPort: 8080, socksPort: nil)

        // Restore should fix it
        try await proxyGuard.restore()

        let state = mockController.currentState()
        if case .enabled(let httpPort, _) = state {
            #expect(httpPort == 6152)
        } else {
            #expect(false, "Expected enabled state")
        }
    }

    @Test("getViolationCount returns number of detected violations")
    func violationCount() async throws {
        let mockController = MockSystemProxyController()
        let proxyGuard = SystemProxyGuard(controller: mockController)

        try await proxyGuard.enable(expectedHTTPPort: 6152, expectedSOCKSPort: nil)

        // Initial count should be 0
        let initialCount = await proxyGuard.getViolationCount()
        #expect(initialCount == 0)

        // Simulate violations
        try await mockController.enable(httpPort: 8080, socksPort: nil)
        _ = await proxyGuard.checkForViolation()

        let count = await proxyGuard.getViolationCount()
        #expect(count == 1)
    }
}

// MARK: - System Proxy Monitor Tests

@Suite("System Proxy Monitor")
struct SystemProxyMonitorTests {

    @Test("monitor starts and stops")
    func monitorLifecycle() async {
        let mockController = MockSystemProxyController()
        let monitor = SystemProxyMonitor(controller: mockController)
        let proxyGuard = SystemProxyGuard(controller: mockController)

        let isRunningBefore = await monitor.isRunning()
        #expect(isRunningBefore == false)

        await monitor.start(interval: 1.0, guard: proxyGuard)
        let isRunningDuring = await monitor.isRunning()
        #expect(isRunningDuring == true)

        await monitor.stop()
        let isRunningAfter = await monitor.isRunning()
        #expect(isRunningAfter == false)
    }

    @Test("monitor detects violations during check cycle")
    func monitorDetectsViolations() async throws {
        let mockController = MockSystemProxyController()
        let monitor = SystemProxyMonitor(controller: mockController)
        let proxyGuard = SystemProxyGuard(controller: mockController)

        // Setup
        try await mockController.enable(httpPort: 6152, socksPort: nil)
        try await proxyGuard.enable(expectedHTTPPort: 6152, expectedSOCKSPort: nil)

        // Start monitor with the guard
        await monitor.start(interval: 0.1, guard: proxyGuard)

        // Simulate external change
        try await mockController.enable(httpPort: 9999, socksPort: nil)

        // Wait for monitor to detect
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        let count = await proxyGuard.getViolationCount()
        #expect(count >= 1)

        await monitor.stop()
    }
}
