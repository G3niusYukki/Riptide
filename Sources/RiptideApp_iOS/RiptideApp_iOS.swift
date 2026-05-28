import SwiftUI
import RiptideCore

/// iOS Main App — shares the same SwiftUI design language as the macOS app
/// but adapted for iPhone/iPad navigation (TabView → TabBar).
///
/// Architecture:
/// - `AppViewModel` is shared from RiptideCore (protocol-agnostic state).
/// - iOS-specific: `VPNViewModel` drives `NETunnelProviderManager` lifecycle.
/// - Views reuse RiptideCore's models and theme system.
@main
struct RiptideApp_iOS: App {
    @StateObject private var appVM = AppViewModel_iOS()
    @State private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView_iOS(vm: appVM)
                    .onAppear { appVM.start() }
            } else {
                OnboardingView_iOS(onComplete: {
                    hasCompletedOnboarding = true
                })
            }
        }
    }
}

// MARK: - Main Tab View

struct MainTabView_iOS: View {
    @ObservedObject var vm: AppViewModel_iOS

    var body: some View {
        TabView {
            DashboardView_iOS(vm: vm)
                .tabItem {
                    Label("概览", systemImage: "square.grid.2x2")
                }

            ProxyListView_iOS(vm: vm)
                .tabItem {
                    Label("代理", systemImage: "server.rack")
                }

            RulesView_iOS(vm: vm)
                .tabItem {
                    Label("规则", systemImage: "list.bullet")
                }

            SettingsView_iOS(vm: vm)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .tint(.accentColor)
    }
}

// MARK: - App ViewModel (iOS)

/// iOS-specific observable view model.
/// In production this wraps the cross-platform `AppViewModel` from RiptideCore
/// and adds iOS-specific VPN management via `NETunnelProviderManager`.
@MainActor
class AppViewModel_iOS: ObservableObject {
    @Published var tunnelState: TunnelState = .disconnected
    @Published var currentMode: ConnectionMode = .systemProxy
    @Published var proxyMode: ProxyMode = .rule
    @Published var currentSpeedUp: Int64 = 0
    @Published var currentSpeedDown: Int64 = 0
    @Published var totalTrafficUp: Int64 = 0
    @Published var totalTrafficDown: Int64 = 0
    @Published var activeConnections: [ConnectionInfo_iOS] = []
    @Published var subscriptions: [SubscriptionDisplay_iOS] = []
    @Published var proxyGroups: [ProxyGroupDisplay_iOS] = []
    @Published var rules: [ProxyRuleDisplay_iOS] = []

    func start() {
        // TODO: Load profiles, restore state, start VPN if needed
    }

    func startTunnel() async {
        // TODO: Configure NETunnelProviderManager, start VPN
        tunnelState = .connecting
        // Simulate connection
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        tunnelState = .connected
    }

    func stopTunnel() async {
        tunnelState = .disconnecting
        try? await Task.sleep(nanoseconds: 500_000_000)
        tunnelState = .disconnected
    }

    func switchMode(_ mode: ProxyMode) async {
        proxyMode = mode
    }
}

// MARK: - Supporting Types

enum TunnelState {
    case disconnected, connecting, connected, disconnecting
}

enum ConnectionMode: String {
    case systemProxy, tun
}

enum ProxyMode: String {
    case rule, global, direct
}

// MARK: - Placeholder Display Models

struct ConnectionInfo_iOS: Identifiable {
    let id = UUID()
    let host: String
    let proxyName: String
    let uploadBytes: Int
    let downloadBytes: Int
}

struct SubscriptionDisplay_iOS: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let autoUpdate: Bool
}

struct ProxyGroupDisplay_iOS: Identifiable {
    let id = UUID()
    let name: String
    let kind: String
    let nodes: [String]
}

struct ProxyRuleDisplay_iOS: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - Placeholder Views

struct OnboardingView_iOS: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "network")
                .font(.system(size: 64))
                .foregroundStyle(.accent)
            Text("欢迎使用 Riptide")
                .font(.title)
                .fontWeight(.bold)
            Text("跨平台网络代理工具")
                .foregroundStyle(.secondary)
            Button("开始使用", action: onComplete)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct DashboardView_iOS: View {
    @ObservedObject var vm: AppViewModel_iOS

    var body: some View {
        NavigationStack {
            List {
                Section("状态") {
                    HStack { Text("模式"); Spacer(); Text(vm.currentMode.rawValue).foregroundStyle(.secondary) }
                    HStack { Text("状态"); Spacer(); Text(tunnelStateText).foregroundStyle(.secondary) }
                }
                Section("速度") {
                    HStack { Text("↑ 上传"); Spacer(); Text(formatBytes(Int(vm.currentSpeedUp)) + "/s") }
                    HStack { Text("↓ 下载"); Spacer(); Text(formatBytes(Int(vm.currentSpeedDown)) + "/s") }
                }
            }
            .navigationTitle("Riptide")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(vm.tunnelState == .connected ? "断开" : "连接") {
                        Task {
                            if vm.tunnelState == .connected {
                                await vm.stopTunnel()
                            } else {
                                await vm.startTunnel()
                            }
                        }
                    }
                }
            }
        }
    }

    private var tunnelStateText: String {
        switch vm.tunnelState {
        case .disconnected: return "未连接"
        case .connecting: return "连接中…"
        case .connected: return "已连接"
        case .disconnecting: return "断开中…"
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let absBytes = abs(bytes)
        switch absBytes {
        case 0: return "0 B"
        case 1..<1024: return "\(absBytes) B"
        case 1024..<(1024 * 1024): return String(format: "%.1f KB", Double(absBytes) / 1024.0)
        case (1024 * 1024)..<(1024 * 1024 * 1024): return String(format: "%.1f MB", Double(absBytes) / (1024.0 * 1024.0))
        default: return String(format: "%.1f GB", Double(absBytes) / (1024.0 * 1024.0 * 1024.0))
        }
    }
}

struct ProxyListView_iOS: View {
    @ObservedObject var vm: AppViewModel_iOS

    var body: some View {
        NavigationStack {
            List {
                Section("代理组") {
                    ForEach(vm.proxyGroups) { group in
                        HStack {
                            Text(group.name)
                            Spacer()
                            Text(group.kind).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("代理")
        }
    }
}

struct RulesView_iOS: View {
    @ObservedObject var vm: AppViewModel_iOS

    var body: some View {
        NavigationStack {
            List {
                Picker("模式", selection: Binding(
                    get: { vm.proxyMode },
                    set: { newMode in Task { await vm.switchMode(newMode) } }
                )) {
                    Text("规则").tag(ProxyMode.rule)
                    Text("全局").tag(ProxyMode.global)
                    Text("直连").tag(ProxyMode.direct)
                }
                .pickerStyle(.segmented)

                Section("规则列表") {
                    ForEach(vm.rules) { rule in
                        Text(rule.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("规则")
        }
    }
}

struct SettingsView_iOS: View {
    @ObservedObject var vm: AppViewModel_iOS

    var body: some View {
        NavigationStack {
            List {
                Section("连接") {
                    Picker("连接模式", selection: $vm.currentMode) {
                        Text("系统代理").tag(ConnectionMode.systemProxy)
                        Text("TUN").tag(ConnectionMode.tun)
                    }
                }
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("2.5.0-iOS").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
        }
    }
}
