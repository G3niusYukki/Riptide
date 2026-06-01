import Foundation
import UserNotifications
import Testing
@testable import Riptide

// MARK: - User Notification Manager Tests

@Suite("User Notification Manager")
struct UserNotificationManagerTests {

    // MARK: - Category Identifiers

    @Test("category identifiers are namespaced under riptide")
    func categoryIdentifiers() {
        #expect(UserNotificationManager.categoryNodeFailure == "riptide.node.failure")
        #expect(UserNotificationManager.categorySubscriptionExpiring == "riptide.subscription.expiring")
        #expect(UserNotificationManager.categorySystemAlert == "riptide.system.alert")
    }

    @Test("action identifiers are stable strings")
    func actionIdentifiers() {
        #expect(UserNotificationManager.actionSwitch == "SWITCH")
        #expect(UserNotificationManager.actionDetails == "DETAILS")
        #expect(UserNotificationManager.actionDismiss == "DISMISS")
    }

    // MARK: - Content Builders (Pure Functions)

    @Test("node failure content includes name and latency")
    func nodeFailureContent() {
        let content = UserNotificationManager.makeNodeFailureContent(
            nodeName: "test-ss-01",
            latencyMs: 5300
        )
        #expect(content.title == "节点连接失败")
        #expect(content.body == "节点 test-ss-01 延迟 5300ms")
        #expect(content.categoryIdentifier == UserNotificationManager.categoryNodeFailure)
        #expect(content.userInfo["nodeName"] as? String == "test-ss-01")
        #expect(content.userInfo["latency"] as? Int == 5300)
    }

    @Test("subscription expiring content includes name and days remaining")
    func subscriptionExpiringContent() {
        let content = UserNotificationManager.makeSubscriptionExpiringContent(
            name: "my-sub",
            daysRemaining: 2
        )
        #expect(content.title == "订阅即将过期")
        #expect(content.body == "my-sub 还剩 2 天")
        #expect(content.categoryIdentifier == UserNotificationManager.categorySubscriptionExpiring)
        #expect(content.userInfo["subscriptionName"] as? String == "my-sub")
        #expect(content.userInfo["daysRemaining"] as? Int == 2)
    }

    @Test("system proxy changed content reflects detection state")
    func systemProxyChangedContent() {
        let restored = UserNotificationManager.makeSystemProxyChangedContent(autoRestored: true)
        #expect(restored.title == "系统代理被修改")
        #expect(restored.body == "已自动恢复")
        #expect(restored.categoryIdentifier == UserNotificationManager.categorySystemAlert)
        #expect(restored.userInfo["type"] as? String == "systemProxy")
        #expect(restored.userInfo["autoRestored"] as? Bool == true)

        let manual = UserNotificationManager.makeSystemProxyChangedContent(autoRestored: false)
        #expect(manual.body == "请检查网络设置")
        #expect(manual.userInfo["autoRestored"] as? Bool == false)
    }

    @Test("mihomo exited content explains impact")
    func mihomoExitedContent() {
        let content = UserNotificationManager.makeMihomoExitedContent()
        #expect(content.title == "mihomo 进程退出")
        #expect(content.body == "代理核心意外退出,网络可能中断")
        #expect(content.categoryIdentifier == UserNotificationManager.categorySystemAlert)
        #expect(content.userInfo["type"] as? String == "mihomoExit")
    }

    @Test("all notification contents set a default sound")
    func contentSound() {
        let node = UserNotificationManager.makeNodeFailureContent(
            nodeName: "n", latencyMs: 1
        )
        let sub = UserNotificationManager.makeSubscriptionExpiringContent(
            name: "n", daysRemaining: 1
        )
        let proxy = UserNotificationManager.makeSystemProxyChangedContent(
            autoRestored: true
        )
        let mihomo = UserNotificationManager.makeMihomoExitedContent()
        #expect(node.sound == .default)
        #expect(sub.sound == .default)
        #expect(proxy.sound == .default)
        #expect(mihomo.sound == .default)
    }

    // MARK: - Category Set

    @Test("registered categories cover the four notification types")
    func registeredCategoriesCoverAllTypes() {
        let categories = UserNotificationManager.registeredCategories()
        let ids = Set(categories.map { $0.identifier })
        #expect(ids.contains(UserNotificationManager.categoryNodeFailure))
        #expect(ids.contains(UserNotificationManager.categorySubscriptionExpiring))
        #expect(ids.contains(UserNotificationManager.categorySystemAlert))
    }

    @Test("node failure category exposes switch/details/dismiss actions")
    func nodeFailureCategoryActions() {
        let categories = UserNotificationManager.registeredCategories()
        let node = categories.first(where: { $0.identifier == UserNotificationManager.categoryNodeFailure })
        let actionIDs = Set(node?.actions.map { $0.identifier } ?? [])
        #expect(actionIDs.contains(UserNotificationManager.actionSwitch))
        #expect(actionIDs.contains(UserNotificationManager.actionDetails))
        #expect(actionIDs.contains(UserNotificationManager.actionDismiss))
    }

    @Test("system alert category exposes details/dismiss actions")
    func systemAlertCategoryActions() {
        let categories = UserNotificationManager.registeredCategories()
        let alert = categories.first(where: { $0.identifier == UserNotificationManager.categorySystemAlert })
        let actionIDs = Set(alert?.actions.map { $0.identifier } ?? [])
        #expect(actionIDs.contains(UserNotificationManager.actionDetails))
        #expect(actionIDs.contains(UserNotificationManager.actionDismiss))
        #expect(!actionIDs.contains(UserNotificationManager.actionSwitch))
    }
}
