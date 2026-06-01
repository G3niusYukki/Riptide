import SwiftUI

struct MainTabView: View {
    @Bindable var vm: AppViewModel
    @ObservedObject var themeManager: ThemeManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(vm: vm)
                .tabItem {
                    Label("概览", systemImage: "square.grid.2x2")
                        .accessibilityIdentifier(A11yID.Tab.dashboard)
                }
                .tag(0)

            ConfigTabView(vm: vm)
                .tabItem {
                    Label("配置", systemImage: "doc.text")
                        .accessibilityIdentifier(A11yID.Tab.config)
                }
                .tag(1)

            ProxyTabView(vm: vm)
                .tabItem {
                    Label("代理", systemImage: "server.rack")
                        .accessibilityIdentifier(A11yID.Tab.proxy)
                }
                .tag(2)

            TrafficTabView(vm: vm)
                .tabItem {
                    Label("流量", systemImage: "chart.bar")
                        .accessibilityIdentifier(A11yID.Tab.traffic)
                }
                .tag(3)

            RulesTabView(vm: vm)
                .tabItem { Label("规则", systemImage: "list.bullet") }
                .tag(4)

            LogTabView(vm: vm)
                .tabItem {
                    Label("日志", systemImage: "terminal")
                        .accessibilityIdentifier(A11yID.Tab.logs)
                }
                .tag(5)

            SettingsTabView(vm: vm, themeManager: themeManager)
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(6)
        }
        .tint(Theme.accent)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
