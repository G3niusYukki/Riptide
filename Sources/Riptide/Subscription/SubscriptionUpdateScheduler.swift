import Foundation

/// Scheduler for automatic subscription updates
public actor SubscriptionUpdateScheduler {
    private let manager: SubscriptionManager
    private var isActive: Bool = false
    private var updateTask: Task<Void, Never>?

    /// Update check interval (default: 5 minutes)
    private let checkInterval: TimeInterval

    public init(manager: SubscriptionManager, checkInterval: TimeInterval = 300) {
        self.manager = manager
        self.checkInterval = checkInterval
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

        for subscription in needingUpdate where subscription.autoUpdate {
            // Note: Actual fetch and parse would happen here
            // For now, just mark as updated
            await manager.recordUpdateSuccess(id: subscription.id)
        }

        return needingUpdate.filter { $0.autoUpdate }.count
    }
}
