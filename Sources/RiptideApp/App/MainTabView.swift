import SwiftUI

struct MainTabView: View {
    @Bindable var vm: AppViewModel
    @ObservedObject var themeManager: ThemeManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(vm: vm)
                .tabItem { Label("概览", systemImage: "square.grid.2x2") }
                .tag(0)
                .accessibilityIdentifier(A11yID.Tab.dashboard)

            ConfigTabView(vm: vm)
                .tabItem { Label("配置", systemImage: "doc.text") }
                .tag(1)
                .accessibilityIdentifier(A11yID.Tab.config)

            ProxyTabView(vm: vm)
                .tabItem { Label("代理", systemImage: "server.rack") }
                .tag(2)
                .accessibilityIdentifier(A11yID.Tab.proxy)

            TrafficTabView(vm: vm)
                .tabItem { Label("流量", systemImage: "chart.bar") }
                .tag(3)
                .accessibilityIdentifier(A11yID.Tab.traffic)

            RulesTabView(vm: vm)
                .tabItem { Label("规则", systemImage: "list.bullet") }
                .tag(4)

            LogTabView(vm: vm)
                .tabItem { Label("日志", systemImage: "terminal") }
                .tag(5)
                .accessibilityIdentifier(A11yID.Tab.logs)

            SettingsTabView(vm: vm, themeManager: themeManager)
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(6)
        }
        .tint(Theme.accent)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
