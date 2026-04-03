import SwiftUI
import Riptide

@main
struct RiptideApp: App {
    @State private var vpnVM = VPNViewModel()
    @State private var proxyVM = ProxyViewModel()
    @State private var appVM = AppViewModel()
    @State private var menuBarVM: MenuBarViewModel?
    @State private var selectedTab = 0

    var body: some SwiftUI.Scene {
        MenuBarExtra {
            if let menuBarVM {
                RiptideMenuBar(viewModel: menuBarVM)
            }
        } label: {
            Image(systemName: vpnVM.isRunning ? "shield.checkmark.fill" : "shield.slash")
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.menu)

        WindowGroup {
            TabView(selection: $selectedTab) {
                MainView()
                    .tabItem { Label("Dashboard", systemImage: "gauge.medium") }
                    .tag(0)

                ProxyListView(proxies: proxyVM.proxyNodes, selected: $proxyVM.selectedProxy)
                    .tabItem { Label("Proxies", systemImage: "list.bullet") }
                    .tag(1)

                ConnectionView(count: vpnVM.activeConnections, bytesUp: vpnVM.bytesUp, bytesDown: vpnVM.bytesDown)
                    .tabItem { Label("Connections", systemImage: "network") }
                    .tag(2)

                TrafficView(bytesUp: vpnVM.bytesUp, bytesDown: vpnVM.bytesDown)
                    .tabItem { Label("Traffic", systemImage: "chart.bar") }
                    .tag(3)

                SettingsView(controllerPort: .constant("9090"))
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(4)
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        Task {
                            if vpnVM.isRunning {
                                await vpnVM.stop()
                            } else {
                                await vpnVM.start()
                            }
                        }
                    } label: {
                        Label(vpnVM.isRunning ? "Stop" : "Start", systemImage: vpnVM.isRunning ? "stop.circle" : "play.circle")
                    }
                }
            }
            .frame(minWidth: 700, minHeight: 450)
            .task {
                menuBarVM = MenuBarViewModel(appViewModel: appVM)
            }
        }
    }
}
