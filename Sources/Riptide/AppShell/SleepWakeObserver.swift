import Foundation
import AppKit

// MARK: - Sleep/Wake Observer

/// Observes macOS sleep/wake notifications and forwards them to ModeCoordinator
/// for runtime recovery. Uses NSObject-based selector observation because
/// NSWorkspace notifications require an ObjC-compatible observer.
///
/// This is a non-actor class marked `@unchecked Sendable` because all mutable
/// state (the callback closures) is only accessed on the main thread via
/// notification delivery, and the callbacks themselves are `@Sendable`.
final class SleepWakeObserver: NSObject, @unchecked Sendable {
    private var onSleep: (@Sendable () -> Void)?
    private var onWake: (@Sendable () -> Void)?

    /// Register for system sleep/wake notifications.
    /// - Parameters:
    ///   - onSleep: Called when the system is about to sleep. Use this to gracefully
    ///     prepare the runtime (e.g., close idle connections, flush state).
    ///   - onWake: Called when the system wakes from sleep. Use this to trigger
    ///     recovery: verify sidecar health, flush DNS cache, reset connection pools.
    func start(
        onSleep: @Sendable @escaping () -> Void,
        onWake: @Sendable @escaping () -> Void
    ) {
        self.onSleep = onSleep
        self.onWake = onWake

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(
            self,
            selector: #selector(handleWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    /// Unregister from all notifications and release callbacks.
    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        onSleep = nil
        onWake = nil
    }

    // MARK: - Notification Handlers

    @objc private func handleWillSleep(_ notification: Notification) {
        onSleep?()
    }

    @objc private func handleDidWake(_ notification: Notification) {
        onWake?()
    }
}
