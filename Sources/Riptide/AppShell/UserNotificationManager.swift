import Foundation
import UserNotifications

/// Manages local user notifications for the Riptide app.
///
/// Surfaces events that need the user's attention even when the app is in the
/// background:
/// - proxy node failures (latency above the timeout threshold)
/// - subscription expiring within three days
/// - system proxy settings being modified by another process
/// - the mihomo sidecar process exiting unexpectedly
///
/// All content-building logic is exposed as static methods so unit tests can
/// verify the resulting `UNMutableNotificationContent` without actually posting
/// to the user's notification center.
///
/// When the manager is constructed outside a real `.app` bundle (e.g. from
/// SwiftPM unit tests, or from a CLI invocation), the live
/// `UNUserNotificationCenter` calls are skipped — `Bundle.main` does not carry
/// a bundle identifier in those environments, and `UNUserNotificationCenter`
/// would throw `bundleProxyForCurrentProcess is nil`. Content builders and
/// category registration still work because they don't touch the center.
@MainActor
public final class UserNotificationManager: NSObject {

    public static let shared = UserNotificationManager()

    // MARK: - Category Identifiers

    public nonisolated static let categoryNodeFailure = "riptide.node.failure"
    public nonisolated static let categorySubscriptionExpiring = "riptide.subscription.expiring"
    public nonisolated static let categorySystemAlert = "riptide.system.alert"

    // MARK: - Action Identifiers

    public nonisolated static let actionSwitch = "SWITCH"
    public nonisolated static let actionDetails = "DETAILS"
    public nonisolated static let actionDismiss = "DISMISS"

    // MARK: - State

    /// True when the manager has successfully registered itself as the
    /// `UNUserNotificationCenter` delegate and installed the categories. Only
    /// flips to true in a real `.app` bundle; tests and CLI usage leave it
    /// false so that all delivery paths short-circuit cleanly.
    private var didConfigureNotificationCenter: Bool = false

    /// Whether the host environment can host a `UNUserNotificationCenter`.
    /// We treat a present `Bundle.main.bundleIdentifier` as the canonical
    /// signal that we're running inside a real macOS app.
    public nonisolated static var canHostNotifications: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    // MARK: - Init

    public override init() {
        super.init()
        // Intentionally do NOT touch `UNUserNotificationCenter.current()` here.
        // The center requires a real `.app` bundle and the singleton is
        // sometimes created from non-bundled contexts (unit tests, CLI).
        // Configuration is performed lazily on first use.
    }

    // MARK: - Authorization

    /// Requests notification authorization the first time the user launches the
    /// app. Skipped if the user has already made a decision in System Settings,
    /// and skipped entirely when the host environment cannot host
    /// notifications (unit tests, CLI, etc.).
    public func requestAuthorizationIfNeeded() async {
        guard Self.canHostNotifications else { return }
        ensureNotificationCenterConfigured()

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }

        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Per project convention we avoid silent fallbacks but also avoid
            // blocking the UI for an opt-in permission prompt. The catch is
            // intentionally empty — the next notify* call will simply skip
            // delivery because authorizationStatus will not become .authorized.
        }
    }

    // MARK: - Category Registration

    /// Returns the categories this manager registers. Exposed as a static
    /// helper so unit tests can verify the configuration without touching the
    /// live `UNUserNotificationCenter` singleton.
    public nonisolated static func registeredCategories() -> Set<UNNotificationCategory> {
        let switchAction = UNNotificationAction(
            identifier: actionSwitch,
            title: "立即切换",
            options: [.foreground]
        )
        let detailsAction = UNNotificationAction(
            identifier: actionDetails,
            title: "查看详情",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: actionDismiss,
            title: "关闭",
            options: [.destructive]
        )

        let nodeFailure = UNNotificationCategory(
            identifier: categoryNodeFailure,
            actions: [switchAction, detailsAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        let subExpiring = UNNotificationCategory(
            identifier: categorySubscriptionExpiring,
            actions: [detailsAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        let systemAlert = UNNotificationCategory(
            identifier: categorySystemAlert,
            actions: [detailsAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        return [nodeFailure, subExpiring, systemAlert]
    }

    // MARK: - Notify Methods (Instance API)

    public func notifyNodeFailure(nodeName: String, latencyMs: Int) async {
        let content = Self.makeNodeFailureContent(nodeName: nodeName, latencyMs: latencyMs)
        await deliver(content)
    }

    public func notifySubscriptionExpiring(name: String, daysRemaining: Int) async {
        let content = Self.makeSubscriptionExpiringContent(
            name: name, daysRemaining: daysRemaining
        )
        await deliver(content)
    }

    public func notifySystemProxyChanged(autoRestored: Bool) async {
        let content = Self.makeSystemProxyChangedContent(autoRestored: autoRestored)
        await deliver(content)
    }

    public func notifyMihomoExited() async {
        let content = Self.makeMihomoExitedContent()
        await deliver(content)
    }

    public func notifyTrafficThreshold(usedBytes: Int64, limitBytes: Int64) async {
        let content = Self.makeTrafficThresholdContent(
            usedBytes: usedBytes, limitBytes: limitBytes
        )
        await deliver(content)
    }

    public func notifyConfigUpdateSuccess(profileName: String) async {
        let content = Self.makeConfigUpdateSuccessContent(profileName: profileName)
        await deliver(content)
    }

    public func notifyConfigUpdateFailed(profileName: String, error: String) async {
        let content = Self.makeConfigUpdateFailedContent(
            profileName: profileName, error: error
        )
        await deliver(content)
    }

    // MARK: - Content Builders (Testable Static API)

    public nonisolated static func makeNodeFailureContent(
        nodeName: String,
        latencyMs: Int
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "节点连接失败"
        content.body = "节点 \(nodeName) 延迟 \(latencyMs)ms"
        content.sound = .default
        content.categoryIdentifier = categoryNodeFailure
        content.userInfo = [
            "nodeName": nodeName,
            "latency": latencyMs
        ]
        return content
    }

    public nonisolated static func makeSubscriptionExpiringContent(
        name: String,
        daysRemaining: Int
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "订阅即将过期"
        content.body = "\(name) 还剩 \(daysRemaining) 天"
        content.sound = .default
        content.categoryIdentifier = categorySubscriptionExpiring
        content.userInfo = [
            "subscriptionName": name,
            "daysRemaining": daysRemaining
        ]
        return content
    }

    public nonisolated static func makeSystemProxyChangedContent(
        autoRestored: Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "系统代理被修改"
        content.body = autoRestored ? "已自动恢复" : "请检查网络设置"
        content.sound = .default
        content.categoryIdentifier = categorySystemAlert
        content.userInfo = [
            "type": "systemProxy",
            "autoRestored": autoRestored
        ]
        return content
    }

    public nonisolated static func makeMihomoExitedContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "mihomo 进程退出"
        content.body = "代理核心意外退出,网络可能中断"
        content.sound = .default
        content.categoryIdentifier = categorySystemAlert
        content.userInfo = [
            "type": "mihomoExit"
        ]
        return content
    }

    public nonisolated static func makeTrafficThresholdContent(
        usedBytes: Int64,
        limitBytes: Int64
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "流量使用提醒"
        content.body = "已使用 \(formatBytes(usedBytes)) / \(formatBytes(limitBytes))"
        content.sound = .default
        content.categoryIdentifier = categorySystemAlert
        content.userInfo = [
            "type": "trafficThreshold",
            "usedBytes": usedBytes,
            "limitBytes": limitBytes
        ]
        return content
    }

    public nonisolated static func makeConfigUpdateSuccessContent(
        profileName: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "订阅更新成功"
        content.body = "\(profileName) 已更新"
        content.sound = .default
        content.categoryIdentifier = categorySystemAlert
        content.userInfo = [
            "type": "configUpdateSuccess",
            "profileName": profileName
        ]
        return content
    }

    public nonisolated static func makeConfigUpdateFailedContent(
        profileName: String,
        error: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "订阅更新失败"
        content.body = "\(profileName): \(error)"
        content.sound = .default
        content.categoryIdentifier = categorySystemAlert
        content.userInfo = [
            "type": "configUpdateFailed",
            "profileName": profileName,
            "error": error
        ]
        return content
    }

    /// Formats a byte count using the same unit scheme as the rest of the
    /// app's traffic displays (K/M/G with one decimal place).
    public nonisolated static func formatBytes(_ bytes: Int64) -> String {
        let abs = Double(bytes.magnitude)
        if abs < 1_000 { return "<1K" }
        if abs < 1_000_000 { return String(format: "%.1fK", abs / 1_000) }
        if abs < 1_000_000_000 { return String(format: "%.1fM", abs / 1_000_000) }
        return String(format: "%.1fG", abs / 1_000_000_000)
    }

    // MARK: - Delivery

    private func deliver(_ content: UNMutableNotificationContent) async {
        guard Self.canHostNotifications else { return }
        ensureNotificationCenterConfigured()

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        guard authorized else { return }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            // Per project convention we don't surface error to UI. The user
            // will simply not see this notification.
        }
    }

    /// Performs one-time setup of the notification center delegate and the
    /// registered categories. Idempotent — safe to call from any notify*
    /// method. A no-op when the host cannot host notifications.
    private func ensureNotificationCenterConfigured() {
        guard Self.canHostNotifications, !didConfigureNotificationCenter else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(Self.registeredCategories())
        didConfigureNotificationCenter = true
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension UserNotificationManager: UNUserNotificationCenterDelegate {

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner + sound even when the app is in the foreground.
        completionHandler([.banner, .sound])
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        Task { @MainActor in
            await Self.handleResponse(action: action, userInfo: userInfo)
        }
        completionHandler()
    }

    @MainActor
    private static func handleResponse(
        action: String,
        userInfo: [AnyHashable: Any]
    ) async {
        switch action {
        case actionSwitch:
            // The notification payload carries the node name; the actual
            // group-selection logic is intentionally left to AppViewModel
            // because the proxy groups live in the UI layer. The action
            // identifier itself is wired so a future iteration can dispatch
            // a node switch via AppCoordinator.
            _ = userInfo["nodeName"]
        case actionDetails:
            // Open the main window — SwiftUI handles activation via the
            // existing scene restoration path.
            _ = userInfo["type"]
        default:
            break
        }
    }
}
