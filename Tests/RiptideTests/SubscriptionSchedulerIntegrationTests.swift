import Foundation
import Testing
@testable import Riptide

// MARK: - Subscription Scheduler Integration Tests

@Suite("SubscriptionScheduler Integration")
struct SubscriptionSchedulerIntegrationTests {

    @Test("Scheduler starts and stops correctly")
    func schedulerLifecycle() async throws {
        let storage = InMemorySubscriptionStorage()
        let manager = SubscriptionManager(storage: storage)
        let scheduler = SubscriptionUpdateScheduler(manager: manager, checkInterval: 5)

        await scheduler.start()
        let running = await scheduler.isRunning()
        #expect(running == true)

        await scheduler.stop()
        let stopped = await scheduler.isRunning()
        #expect(stopped == false)
    }

    @Test("Scheduler identifies subscriptions needing update")
    func identifiesExpiredSubscriptions() async throws {
        let storage = InMemorySubscriptionStorage()
        let manager = SubscriptionManager(storage: storage)

        // Add a subscription that needs update (lastUpdated is nil, autoUpdate is true)
        _ = await manager.addSubscription(
            name: "test",
            url: "https://example.com/sub",
            autoUpdate: true,
            interval: 3600
        )

        let needing = await manager.subscriptionsNeedingUpdate()
        #expect(needing.count == 1)
        #expect(needing.first?.name == "test")
    }

    @Test("Scheduler does not flag subscriptions with autoUpdate disabled")
    func skipAutoUpdateDisabled() async throws {
        let storage = InMemorySubscriptionStorage()
        let manager = SubscriptionManager(storage: storage)

        // Add a subscription with autoUpdate disabled
        _ = await manager.addSubscription(
            name: "manual",
            url: "https://example.com/sub",
            autoUpdate: false,
            interval: 3600
        )

        let needing = await manager.subscriptionsNeedingUpdate()
        #expect(needing.isEmpty)
    }

    @Test("Scheduler does not flag recently updated subscriptions")
    func skipRecentlyUpdated() async throws {
        let storage = InMemorySubscriptionStorage()
        let manager = SubscriptionManager(storage: storage)

        // Add a subscription and record a recent update
        let sub = await manager.addSubscription(
            name: "recent",
            url: "https://example.com/sub",
            autoUpdate: true,
            interval: 3600
        )
        await manager.recordUpdateSuccess(id: sub.id)

        let needing = await manager.subscriptionsNeedingUpdate()
        #expect(needing.isEmpty)
    }
}

// MARK: - Test Helper

/// In-memory storage for subscription persistence in tests.
private actor InMemorySubscriptionStorage: SubscriptionStorage {
    private var subs: [Subscription] = []

    func load() async throws -> [Subscription] { subs }
    func save(_ subscriptions: [Subscription]) async throws { subs = subscriptions }
}
