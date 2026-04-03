import SwiftUI

struct MainTabView: View {
    @Bindable var vm: AppViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ConfigTabView(vm: vm)
                .tabItem { Label("配置", systemImage: "doc.text") }
                .tag(0)

            ProxyTabView(vm: vm)
                .tabItem { Label("代理", systemImage: "server.rack") }
                .tag(1)

            TrafficTabView(vm: vm)
                .tabItem { Label("流量", systemImage: "chart.bar") }
                .tag(2)

            RulesTabView(vm: vm)
                .tabItem { Label("规则", systemImage: "list.bullet") }
                .tag(3)

            LogTabView(vm: vm)
                .tabItem { Label("日志", systemImage: "terminal") }
                .tag(4)
        }
        .tint(Theme.accent)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
