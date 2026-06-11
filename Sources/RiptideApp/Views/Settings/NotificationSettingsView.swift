import SwiftUI

// MARK: - Notification Settings View

/// User-facing toggles for the categories of notifications surfaced by
/// `UserNotificationManager`. Persists via `@AppStorage` so changes are
/// picked up by the notification dispatcher without requiring an app
/// restart.
struct NotificationSettingsView: View {
    @AppStorage("riptide.notify.nodeFailure") private var nodeFailure = true
    @AppStorage("riptide.notify.subscriptionExpiring") private var subscriptionExpiring = true
    @AppStorage("riptide.notify.systemAlert") private var systemAlert = true
    @AppStorage("riptide.notify.configUpdate") private var configUpdate = true
    @AppStorage("riptide.notify.trafficThreshold") private var trafficThreshold = false
    @AppStorage("riptide.notify.trafficLimitGB") private var trafficLimitGB = 100.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("通知设置")
                .font(.headline)
                .foregroundStyle(Theme.text)

            Text("控制哪些事件会以系统通知的形式提醒你。关闭后仍可在应用内查看对应事件。")
                .font(.caption)
                .foregroundStyle(Theme.subtext)

            Toggle("节点连接失败", isOn: $nodeFailure)
            Toggle("订阅即将到期", isOn: $subscriptionExpiring)
            Toggle("系统提示（Helper 变更等）", isOn: $systemAlert)
            Toggle("订阅自动更新结果", isOn: $configUpdate)
            Toggle("流量使用提醒", isOn: $trafficThreshold)

            if trafficThreshold {
                HStack {
                    Text("阈值: \(Int(trafficLimitGB)) GB")
                        .font(.callout)
                        .foregroundStyle(Theme.text)
                    Slider(value: $trafficLimitGB, in: 10...1000, step: 10)
                }
                .padding(.leading, 4)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}
