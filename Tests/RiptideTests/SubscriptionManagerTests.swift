import Foundation
import Testing
@testable import Riptide

// MARK: - Subscription Manager Tests

@Suite("Subscription Manager")
struct SubscriptionManagerTests {

    @Test("creates subscription with correct properties")
    func createsSubscription() async throws {
        let manager = SubscriptionManager()

        let sub = await manager.addSubscription(name: "Test Sub", url: "https://example.com/sub.yaml")

        #expect(sub.name == "Test Sub")
        #expect(sub.url == "https://example.com/sub.yaml")
        #expect(sub.autoUpdate == true)
        #expect(sub.updateInterval == 3600)
        #expect(sub.lastUpdated == nil)
        #expect(sub.lastError == nil)
    }

    @Test("returns all subscriptions")
    func returnsAllSubscriptions() async throws {
        let manager = SubscriptionManager()

        _ = await manager.addSubscription(name: "Sub 1", url: "https://example.com/1.yaml")
        _ = await manager.addSubscription(name: "Sub 2", url: "https://example.com/2.yaml")

        let all = await manager.allSubscriptions()

        #expect(all.count == 2)
    }

    @Test("removes subscription by ID")
    func removesSubscription() async throws {
        let manager = SubscriptionManager()

        let sub = await manager.addSubscription(name: "To Remove", url: "https://example.com/rm.yaml")
        await manager.removeSubscription(id: sub.id)

        let all = await manager.allSubscriptions()
        #expect(all.isEmpty)
    }

    @Test("updates subscription auto-update setting")
    func updatesAutoUpdate() async throws {
        let manager = SubscriptionManager()

        let sub = await manager.addSubscription(name: "Test", url: "https://example.com/test.yaml")
        await manager.updateSubscription(id: sub.id, autoUpdate: false)

        let updated = await manager.subscription(id: sub.id)
        #expect(updated?.autoUpdate == false)
    }

    @Test("updates subscription interval")
    func updatesInterval() async throws {
        let manager = SubscriptionManager()

        let sub = await manager.addSubscription(name: "Test", url: "https://example.com/test.yaml")
        await manager.updateSubscription(id: sub.id, interval: 7200)

        let updated = await manager.subscription(id: sub.id)
        #expect(updated?.updateInterval == 7200)
    }

    @Test("returns nil for non-existent subscription")
    func returnsNilForNonExistent() async throws {
        let manager = SubscriptionManager()

        let found = await manager.subscription(id: UUID())

        #expect(found == nil)
    }

    @Test("next update time is calculated correctly when lastUpdated is set")
    func nextUpdateTime() async throws {
        let manager = SubscriptionManager()
        let now = Date()

        let sub = await manager.addSubscription(name: "Test", url: "https://example.com/test.yaml")

        // Initially lastUpdated is nil, so nextUpdateTime returns nil (meaning update immediately)
        let nextUpdate = await manager.nextUpdateTime(for: sub.id)
        #expect(nextUpdate == nil)

        // Simulate an update
        await manager.recordUpdateSuccess(id: sub.id)

        // Now nextUpdateTime should be approximately 1 hour from now (default interval)
        let nextUpdate2 = await manager.nextUpdateTime(for: sub.id)
        #expect(nextUpdate2 != nil)

        // Check it's roughly 1 hour later
        if let next = nextUpdate2 {
            let diff = next.timeIntervalSince(now)
            #expect(diff > 3500 && diff < 3700) // ~1 hour with some tolerance
        }
    }
}

// MARK: - Subscription Update Scheduler Tests

@Suite("Subscription Update Scheduler")
struct SubscriptionUpdateSchedulerTests {

    @Test("scheduler starts and stops without errors")
    func schedulerLifecycle() async throws {
        let manager = SubscriptionManager()
        let scheduler = SubscriptionUpdateScheduler(manager: manager)

        // Should not throw
        await scheduler.start()
        await scheduler.stop()
    }

    @Test("scheduler returns isRunning status")
    func schedulerStatus() async throws {
        let manager = SubscriptionManager()
        let scheduler = SubscriptionUpdateScheduler(manager: manager)

        let before = await scheduler.isRunning()
        #expect(before == false)

        await scheduler.start()
        let during = await scheduler.isRunning()
        #expect(during == true)

        await scheduler.stop()
        let after = await scheduler.isRunning()
        #expect(after == false)
    }

    @Test("manual trigger updates all enabled subscriptions")
    func manualTrigger() async throws {
        let manager = SubscriptionManager()
        _ = await manager.addSubscription(name: "Auto", url: "https://example.com/auto.yaml")
        _ = await manager.addSubscription(name: "Manual", url: "https://example.com/manual.yaml", autoUpdate: false)

        let scheduler = SubscriptionUpdateScheduler(manager: manager)

        // Manual trigger should only update auto-enabled subscriptions
        let count = await scheduler.triggerManualUpdate()

        // Should only update the one with autoUpdate=true
        #expect(count == 1)
    }
}

// MARK: - Subscription Update Result Tests

@Suite("Subscription Update Result")
struct SubscriptionUpdateResultTests {

    @Test("success result contains proxy nodes")
    func successResult() async throws {
        let proxies = [
            ProxyNode(name: "Node1", kind: .shadowsocks, server: "1.2.3.4", port: 443),
            ProxyNode(name: "Node2", kind: .vmess, server: "5.6.7.8", port: 443)
        ]

        let result = SubscriptionUpdateResult.success(proxies: proxies)

        switch result {
        case .success(let nodes):
            #expect(nodes.count == 2)
        default:
            #expect(false, "Expected success")
        }
    }

    @Test("failure result contains error message")
    func failureResult() async throws {
        let result = SubscriptionUpdateResult.failure(error: "Network timeout")

        switch result {
        case .failure(let error):
            #expect(error == "Network timeout")
        default:
            #expect(false, "Expected failure")
        }
    }

    @Test("noChange result indicates no updates needed")
    func noChangeResult() async throws {
        let result = SubscriptionUpdateResult.noChange

        switch result {
        case .noChange:
            #expect(true)
        default:
            #expect(false, "Expected noChange")
        }
    }
}
