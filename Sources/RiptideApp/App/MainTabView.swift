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
        case .proxy:       return "server.rack"
        case .config:      return "doc.text"
        case .traffic:     return "chart.bar"
        case .rules:       return "list.bullet"
        case .logs:        return "terminal"
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
}

struct MainTabView: View {
    @Bindable var vm: AppViewModel
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("主要") {
                    Label(SidebarItem.dashboard.title, systemImage: SidebarItem.dashboard.systemImage)
                        .tag(SidebarItem.dashboard)
                        .accessibilityIdentifier(SidebarItem.dashboard.accessibilityID)
                    Label(SidebarItem.proxy.title, systemImage: SidebarItem.proxy.systemImage)
                        .tag(SidebarItem.proxy)
                        .accessibilityIdentifier(SidebarItem.proxy.accessibilityID)
                    Label(SidebarItem.config.title, systemImage: SidebarItem.config.systemImage)
                        .tag(SidebarItem.config)
                        .accessibilityIdentifier(SidebarItem.config.accessibilityID)
                }
                Section("监控") {
                    Label(SidebarItem.traffic.title, systemImage: SidebarItem.traffic.systemImage)
                        .tag(SidebarItem.traffic)
                        .accessibilityIdentifier(SidebarItem.traffic.accessibilityID)
                    Label(SidebarItem.rules.title, systemImage: SidebarItem.rules.systemImage)
                        .tag(SidebarItem.rules)
                        .accessibilityIdentifier(SidebarItem.rules.accessibilityID)
                    Label(SidebarItem.logs.title, systemImage: SidebarItem.logs.systemImage)
                        .tag(SidebarItem.logs)
                        .accessibilityIdentifier(SidebarItem.logs.accessibilityID)
                    Label(SidebarItem.diagnostics.title, systemImage: SidebarItem.diagnostics.systemImage)
                        .tag(SidebarItem.diagnostics)
                        .accessibilityIdentifier(SidebarItem.diagnostics.accessibilityID)
                }
            }
            .navigationTitle("Riptide")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detailView
        }
        .tint(Theme.accent)
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
