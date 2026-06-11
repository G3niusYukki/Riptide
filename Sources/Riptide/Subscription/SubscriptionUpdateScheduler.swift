import Foundation

/// Scheduler for automatic subscription updates
public actor SubscriptionUpdateScheduler {
    private let manager: SubscriptionManager
    private var isActive: Bool = false
    private var updateTask: Task<Void, Never>?

    /// Update check interval (default: 5 minutes)
    private let checkInterval: TimeInterval

    /// Optional callback invoked after every subscription update attempt.
    /// Parameters are `(profileName, success, errorMessage)`. The closure is
    /// called from the scheduler's actor; consumers are responsible for
    /// hopping to the appropriate isolation domain (e.g. `@MainActor`) before
    /// touching UI or `UNUserNotificationCenter`.
    private let onUpdateResult: (@Sendable (String, Bool, String?) async -> Void)?

    public init(
        manager: SubscriptionManager,
        checkInterval: TimeInterval = 300,
        onUpdateResult: (@Sendable (String, Bool, String?) async -> Void)? = nil
    ) {
        self.manager = manager
        self.checkInterval = checkInterval
        self.onUpdateResult = onUpdateResult
    }

    /// Starts the scheduler
    public func start() {
        guard !isActive else { return }
        isActive = true

        updateTask = Task {
            while isActive && !Task.isCancelled {
                // Check for subscriptions needing update
                _ = await checkAndUpdateSubscriptions()

                // Wait before next check
                try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            }
        }
    }

    /// Stops the scheduler
    public func stop() {
        isActive = false
        updateTask?.cancel()
        updateTask = nil
    }

    /// Returns whether the scheduler is running
    public func isRunning() -> Bool {
        isActive
    }

    /// Manually triggers update for all auto-update enabled subscriptions
    /// - Returns: Number of subscriptions that were updated
    public func triggerManualUpdate() async -> Int {
        await checkAndUpdateSubscriptions()
    }

    // MARK: - Private

    private func checkAndUpdateSubscriptions() async -> Int {
        let needingUpdate = await manager.subscriptionsNeedingUpdate()

        var updatedCount = 0
        for subscription in needingUpdate where subscription.autoUpdate {
            let result = await manager.updateSubscription(id: subscription.id)
            switch result {
            case .success:
                updatedCount += 1
                if let cb = onUpdateResult {
                    await cb(subscription.name, true, nil)
                }
            case .noChange:
                // No notification — repeated refreshes that produce identical
                // payloads would otherwise spam the user.
                break
            case .failure(let error):
                if let cb = onUpdateResult {
                    await cb(subscription.name, false, error)
                }
            }
        }

        return updatedCount
    }
}
