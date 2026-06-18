import SwiftUI

// MARK: - Quick Actions Row

/// Four shortcut buttons: toggle tunnel / refresh subscriptions / test delay /
/// open diagnostics. The diagnostics button is a no-op for now (tab switching
/// is left to the sidebar); everything else maps to an existing `AppViewModel`
/// method.
struct QuickActionsRow: View {
    @Bindable var vm: AppViewModel
    @State private var pressedAction: String?

    var body: some View {
        HStack(spacing: 12) {
            actionButton(
                icon: "power",
                title: "切换模式",
                color: Theme.accent,
                id: "power"
            ) {
                Task { await vm.toggleTunnel() }
            }
            actionButton(
                icon: "arrow.clockwise",
                title: "刷新订阅",
                color: Theme.success,
                id: "refresh"
            ) {
                Task { await vm.refreshAllSubscriptions() }
            }
            actionButton(
                icon: "speedometer",
                title: "测试延迟",
                color: Theme.warning,
                id: "speed"
            ) {
                Task { await vm.testDelay() }
            }
            actionButton(
                icon: "stethoscope",
                title: "打开诊断",
                color: Theme.danger,
                id: "diag"
            ) {
                // Tab switching is a follow-up; for now this is a no-op.
            }
        }
        .accessibilityIdentifier(A11yID.Dashboard.quickActions)
    }

    private func actionButton(
        icon: String,
        title: String,
        color: Color,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            pressedAction = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { pressedAction = nil }
            action()
        }, label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                    .symbolEffect(.bounce, value: pressedAction == id)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(color)
        })
        .buttonStyle(.bordered)
    }
}
