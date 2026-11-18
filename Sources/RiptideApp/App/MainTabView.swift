import SwiftUI

enum SidebarItem: Int, Hashable, CaseIterable {
    case dashboard
    case proxy
    case config
    case traffic
    case rules
    case logs
    case diagnostics

    var title: String {
        switch self {
        case .dashboard:   return "概览"
        case .proxy:       return "代理"
        case .config:      return "配置"
        case .traffic:     return "流量"
        case .rules:       return "规则"
        case .logs:        return "日志"
        case .diagnostics: return "诊断"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:   return "square.grid.2x2"
        case .proxy:       return "point.3.connected.trianglepath.dotted"
        case .config:      return "doc.text"
        case .traffic:     return "chart.xyaxis.line"
        case .rules:       return "list.bullet"
        case .logs:        return "text.alignleft"
        case .diagnostics: return "stethoscope"
        }
    }

    var accessibilityID: String {
        switch self {
        case .dashboard:   return A11yID.Tab.dashboard
        case .proxy:       return A11yID.Tab.proxy
        case .config:      return A11yID.Tab.config
        case .traffic:     return A11yID.Tab.traffic
        case .rules:       return A11yID.Tab.rules
        case .logs:        return A11yID.Tab.logs
        case .diagnostics: return A11yID.Tab.diagnostics
        }
    }

    var section: String {
        switch self {
        case .dashboard, .proxy, .config: return "工作"
        default: return "观察"
        }
    }
}

struct MainTabView: View {
    @Bindable var vm: AppViewModel
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.canvas.ignoresSafeArea())
        }
        .tint(Theme.accent)
        .background(Theme.canvas.ignoresSafeArea())
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RIPTIDE")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Theme.subtext)
                Text(vm.activeProfile?.name ?? "未选择配置")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 14)

            sidebarSection("工作", items: [.dashboard, .proxy, .config])
            sidebarSection("观察", items: [.traffic, .rules, .logs, .diagnostics])

            Spacer(minLength: 12)

            sidebarStatus
                .padding(12)
        }
        .frame(width: 216)
        .background(Theme.sidebar.ignoresSafeArea())
    }

    private func sidebarSection(_ title: String, items: [SidebarItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(items, id: \.self) { item in
                sidebarRow(item)
            }
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        let selected = selection == item
        return Button {
            selection = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(selected ? Theme.accent : Theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Theme.accent.opacity(0.12) : Color.clear)
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(item.accessibilityID)
    }

    private var sidebarStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(vm.tunnelState == .running ? Theme.success : Theme.textTertiary)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(vm.tunnelState == .running ? "已连接" : "未连接")
                    .font(.system(size: 12, weight: .medium))
                Text(vm.connectionMode == .tun ? "TUN" : "系统代理")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.subtext)
            }
            Spacer()
        }
        .padding(10)
        .background(Theme.activityCard.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .dashboard:
            DashboardView(vm: vm)
        case .proxy:
            ProxyTabView(vm: vm)
        case .config:
            ConfigTabView(vm: vm)
        case .traffic:
            TrafficTabView(vm: vm)
        case .rules:
            RulesTabView(vm: vm)
        case .logs:
            LogTabView(vm: vm)
        case .diagnostics:
            DiagnosticsTabView(vm: vm)
        case .none:
            DashboardView(vm: vm)
        }
    }
}
