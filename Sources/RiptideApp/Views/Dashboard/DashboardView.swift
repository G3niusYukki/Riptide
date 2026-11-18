import SwiftUI

// MARK: - Dashboard View

/// Home page with at-a-glance status cards, subscription info, and recent connections.
struct DashboardView: View {
    @Bindable var vm: AppViewModel
    @State private var showDiagnostics = false

    private var currentSelectedNode: String {
        // Find the currently selected proxy from the first non-direct group
        if let globalGroup = vm.proxyGroups.first(where: {
            $0.kind == .select || $0.kind == .urlTest || $0.kind == .fallback
        }),
           let selected = globalGroup.selectedNodeName {
            return selected
        }
        return "Direct"
    }

    private var recentConnections: [ConnectionInfo] {
        Array(vm.activeConnections.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageTitle
                heroCard
                metricsRow
                activitySection
                recentConnectionsSection

                DisclosureGroup {
                    VStack(spacing: Theme.Spacing.md) {
                        TrafficHistoryCard(vm: vm)
                        NodeHealthCard(vm: vm)
                        QuickActionsRow(vm: vm)
                        subscriptionSection
                    }
                    .padding(.top, Theme.Spacing.sm)
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.text)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.activityCard, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .stroke(Theme.cardBorder.opacity(0.35), lineWidth: 0.5)
                )
            }
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.horizontal, 28, for: .scrollContent)
        .contentMargins(.vertical, 22, for: .scrollContent)
        .background(Theme.canvas.ignoresSafeArea())
        .refreshable {
            await vm.refreshStats()
            await vm.loadSubscriptionsFromBackend()
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView()
                .frame(width: 560, height: 600)
        }
    }

    // MARK: - Hero

    private var pageTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("概览")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text(vm.activeProfile?.name ?? "还没有配置。导入一个订阅后再连接。")
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.subtext)
        }
    }

    private var heroCard: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: 8) {
                Text(isRunning ? "已连接" : "未连接")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(isRunning ? "流量正在经过当前节点" : "连接后才会改系统代理或 TUN")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.subtext)
                HStack(spacing: Theme.Spacing.sm) {
                    StatusPill(title: modeDisplayName, systemImage: modeIcon, tint: modeColor)
                    StatusPill(title: proxyModeDisplay, systemImage: "arrow.triangle.branch", tint: Theme.accent)
                }
            }
            Spacer(minLength: Theme.Spacing.lg)
            VStack(alignment: .trailing, spacing: 10) {
                Picker("连接方式", selection: $vm.connectionMode) {
                    Text("系统代理").tag(ConnectionMode.systemProxy)
                    Text("TUN").tag(ConnectionMode.tun)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .disabled(isRunning)
                Button {
                    Task { await vm.toggleTunnel() }
                } label: {
                    Text(isRunning ? "断开" : "连接")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 180, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? Theme.danger : Theme.accent)
            }
        }
        .padding(22)
        .background(Theme.activityCard, in: RoundedRectangle(cornerRadius: Theme.largeRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.largeRadius)
                .stroke(Theme.cardBorder.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityIdentifier(A11yID.Dashboard.modeCard)
        .background {
            Color.clear.accessibilityIdentifier(A11yID.Dashboard.hero)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            MetricTile(
                title: "当前节点",
                value: currentSelectedNode,
                caption: proxyModeDisplay,
                tint: Theme.accent
            )
            .accessibilityIdentifier(A11yID.Dashboard.nodeCard)
            MetricTile(
                title: "上传",
                value: formatSpeed(vm.currentSpeedUp),
                caption: "实时",
                tint: Theme.accent
            )
            MetricTile(
                title: "下载",
                value: formatSpeed(vm.currentSpeedDown),
                caption: totalTrafficSummary,
                tint: Theme.success
            )
        }
        .accessibilityIdentifier(A11yID.Dashboard.speedCard)
        .background {
            Color.clear.accessibilityIdentifier(A11yID.Dashboard.metrics)
        }
    }

    private var activitySection: some View {
        ActivityCard(title: "流量", systemImage: "chart.xyaxis.line") {
            MiniTrafficChart(vm: vm)
                .frame(height: 88)
        }
        .accessibilityIdentifier(A11yID.Dashboard.activity)
    }

    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("订阅", systemImage: "icloud.and.arrow.down")
                .font(.headline)
                .foregroundStyle(Theme.text)

            if vm.subscriptions.isEmpty {
                Text("暂无订阅")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            } else {
                ForEach(vm.subscriptions.prefix(3)) { sub in
                    SubscriptionCard(sub: sub)
                }
            }
        }
    }

    // MARK: - Recent Connections Section

    private var recentConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("最近连接", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    showDiagnostics = true
                } label: {
                    Label("诊断", systemImage: "stethoscope")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(A11yID.Dashboard.diagnosticsButton)
            }
                .font(.headline)
                .foregroundStyle(Theme.text)

            if recentConnections.isEmpty {
                Text("无活跃连接")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            } else {
                ForEach(recentConnections) { conn in
                    ActivityConnectionRow(host: conn.host, proxyName: conn.proxyName)
                        .padding(.vertical, 4)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.smallRadius))
                }
            }
        }
    }

    // MARK: - Computed Helpers

    private var isRunning: Bool { vm.tunnelState == .running }

    private var modeIcon: String {
        switch vm.connectionMode {
        case .systemProxy: return "gearshape.2"
        case .tun: return "shield.lefthalf.filled"
        }
    }

    private var modeColor: Color {
        switch vm.connectionMode {
        case .systemProxy: return Theme.accent
        case .tun: return Theme.warning
        }
    }

    private var modeDisplayName: String {
        switch vm.connectionMode {
        case .systemProxy: return "系统代理"
        case .tun: return "TUN 模式"
        }
    }

    private var proxyModeDisplay: String {
        switch vm.proxyMode {
        case .rule: return "规则模式"
        case .global: return "全局模式"
        case .direct: return "直连模式"
        }
    }

    private var totalTrafficSummary: String {
        let total = vm.totalTrafficUp + vm.totalTrafficDown
        return formatBytes(Int(total))
    }
}

// MARK: - Status Card

struct StatusCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String
    var isActive: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: isActive)

            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.subtext)

            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Theme.subtext)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

// MARK: - Speed Box

struct SpeedBox: View {
    let title: String
    let speed: Int64
    let color: Color

    private var formattedSpeed: String {
        let bytesPerSecond = Double(speed)
        let absSpeed = abs(bytesPerSecond)
        switch absSpeed {
        case 0: return "0 B/s"
        case 1..<1024: return String(format: "%.0f B/s", absSpeed)
        case 1024..<(1024 * 1024): return String(format: "%.1f KB/s", absSpeed / 1024.0)
        case (1024 * 1024)..<(1024 * 1024 * 1024): return String(format: "%.1f MB/s", absSpeed / (1024.0 * 1024.0))
        default: return String(format: "%.1f GB/s", absSpeed / (1024.0 * 1024.0 * 1024.0))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.subtext)

            Text(formattedSpeed)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

// MARK: - Subscription Card

struct SubscriptionCard: View {
    let sub: SubscriptionDisplay

    private var quotaRatio: Double? { sub.userinfo?.usageRatio }
    private var usedStr: String? {
        guard let used = sub.userinfo?.usedBytes else { return nil }
        return formatBytes(Int(used))
    }
    private var totalStr: String? {
        guard let total = sub.userinfo?.totalBytes else { return nil }
        return formatBytes(Int(total))
    }
    private var expiryLabel: (text: String, color: Color)? {
        guard let info = sub.userinfo else { return nil }
        if info.isExpired { return ("已过期", Theme.danger) }
        if info.isExpiringSoon {
            guard let date = info.expireDate else { return nil }
            let df = RelativeDateTimeFormatter()
            df.locale = Locale(identifier: "zh-Hans")
            return (df.localizedString(for: date, relativeTo: Date()), Theme.warning)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.text)
                    Text(sub.url)
                        .font(.caption2)
                        .foregroundStyle(Theme.subtext)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(sub.autoUpdate ? Theme.success : Theme.subtext)
                        .frame(width: 6, height: 6)
                    Text(sub.autoUpdate ? "自动" : "手动")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtext)
                }
            }

            // Quota bar + expiry label
            if sub.userinfo != nil {
                HStack(spacing: 8) {
                    // Quota progress bar
                    if let ratio = quotaRatio {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(ratio > 0.9 ? Theme.danger : ratio > 0.7 ? Theme.warning : Theme.accent)
                                    .frame(width: geo.size.width * ratio, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }

                    if let expiry = expiryLabel {
                        Text(expiry.text)
                            .font(.caption2)
                            .foregroundStyle(expiry.color)
                    }
                }

                if let used = usedStr, let total = totalStr {
                    HStack {
                        Text("\(used) / \(total)")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtext)
                        if let ratio = quotaRatio {
                            Text(String(format: "(%.0f%%)", ratio * 100))
                                .font(.caption2)
                                .foregroundStyle(Theme.subtext)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

// MARK: - Recent Connection Row

struct RecentConnectionRow: View {
    let conn: ConnectionInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: conn.proxyName == "Direct" ? "arrow.up.right" : "arrow.triangle.swap")
                .font(.caption)
                .foregroundStyle(conn.proxyName == "Direct" ? Theme.success : Theme.accent)
                .frame(width: 16)

            Text(conn.host)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(conn.proxyName)
                .font(.caption2)
                .foregroundStyle(conn.proxyName == "Direct" ? Theme.success : Theme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    conn.proxyName == "Direct"
                        ? Theme.success.opacity(0.15)
                        : Theme.accent.opacity(0.15)
                )
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Helpers

/// Format bytes to human-readable string. Used by DashboardView components.
func formatBytes(_ bytes: Int) -> String {
    let absBytes = abs(bytes)
    switch absBytes {
    case 0: return "0 B"
    case 1..<1024: return "\(absBytes) B"
    case 1024..<(1024 * 1024):
        return String(format: "%.1f KB", Double(absBytes) / 1024.0)
    case (1024 * 1024)..<(1024 * 1024 * 1024):
        return String(format: "%.1f MB", Double(absBytes) / (1024.0 * 1024.0))
    default:
        return String(format: "%.1f GB", Double(absBytes) / (1024.0 * 1024.0 * 1024.0))
    }
}
