import Foundation

/// Actor that periodically monitors system proxy settings and auto-restores if needed
public actor SystemProxyMonitor {
    private let controller: any SystemProxyControlling
    private var isRunningState: Bool = false
    private var monitorTask: Task<Void, Never>?
    private var currentGuard: SystemProxyGuard?

    public init(controller: any SystemProxyControlling) {
        self.controller = controller
    }

    /// Starts monitoring with the given guard and check interval
    /// - Parameters:
    ///   - interval: Time between checks in seconds (default: 5.0)
    ///   - guard: The SystemProxyGuard to use for checking and restoring
    public func start(interval: TimeInterval = 5.0, guard proxyGuard: SystemProxyGuard) {
        guard !isRunningState else { return }

        isRunningState = true
        currentGuard = proxyGuard

        monitorTask = Task {
            while isRunningState && !Task.isCancelled {
                // Check for violations and auto-restore
                let hasViolation = await proxyGuard.checkForViolation()
                if hasViolation {
                    try? await proxyGuard.restore()
                }

                // Wait for next check
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// Stops the monitor
    public func stop() {
        isRunningState = false
        monitorTask?.cancel()
        monitorTask = nil
        currentGuard = nil
    }

    /// Returns whether the monitor is currently running
    public func isRunning() -> Bool {
        isRunningState
    }
}
