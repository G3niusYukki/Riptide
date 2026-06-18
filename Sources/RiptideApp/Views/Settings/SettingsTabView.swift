import SwiftUI
import Riptide

// MARK: - Settings Tab

/// Unified settings container with navigation to all sub-settings views.
struct SettingsTabView: View {
    @Bindable var vm: AppViewModel
    @Bindable var themeManager: ThemeManager
    @State private var hotkeyManager = HotkeyManager()

    @State private var launchAtLogin: Bool = false
    @State private var launchAgentLoaded: Bool = false
    @State private var launchAgentError: String?
    @State private var launchAgentBusy: Bool = false

    private let launchAgent = LaunchAgentManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // MARK: - Network
                    SettingsSection(title: "网络", icon: "network") {
                        NavigationLink {
                            NetworkEnvironmentSettingsView(vm: vm)
                        } label: {
                            SettingsRow(
                                icon: "wifi.router",
                                title: "网络环境自动切换",
                                subtitle: "连接不同 WiFi 时自动切换代理模式",
                                accent: Theme.accent
                            )
                        }

                        NavigationLink {
                            SceneEditorView(vm: vm)
                        } label: {
                            SettingsRow(
                                icon: "wifi.circle",
                                title: "场景管理",
                                subtitle: "创建 WiFi 场景，自动切换代理模式和节点",
                                accent: Theme.success
                            )
                        }

                        NavigationLink {
                            PerAppRuleEditor(vm: vm)
                        } label: {
                            SettingsRow(
                                icon: "square.grid.3x3.topleft.filled",
                                title: "应用分流",
                                subtitle: "为不同 App 设置独立的代理策略",
                                accent: Theme.accent
                            )
                        }

                        NavigationLink {
                            // Gateway settings placeholder — backend ready
                            GatewaySettingsPlaceholderView()
                        } label: {
                            SettingsRow(
                                icon: "globe.americas",
                                title: "网关模式",
                                subtitle: "为局域网设备提供代理服务",
                                accent: Theme.warning
                            )
                        }
                    }

                    // MARK: - Security
                    SettingsSection(title: "安全与隐私", icon: "lock.shield") {
                        NavigationLink {
                            MITMSettingsView(vm: vm)
                        } label: {
                            SettingsRow(
                                icon: "lock.shield",
                                title: "HTTPS 拦截 (MITM)",
                                subtitle: "管理 CA 证书、域名白名单和拦截日志",
                                accent: Theme.danger
                            )
                        }

                        NavigationLink {
                            RewriteRulesView()
                        } label: {
                            SettingsRow(
                                icon: "pencil.and.list.clipboard",
                                title: "URL 重写规则",
                                subtitle: "拦截广告域名、修改请求/响应头",
                                accent: Theme.accent
                            )
                        }
                    }

                    // MARK: - Updates
                    SettingsSection(title: "软件更新", icon: "arrow.down.circle") {
                        UpdateSettingsView()
                    }

                    // MARK: - Hotkeys
                    SettingsSection(title: "快捷键", icon: "keyboard") {
                        HotkeySettingsView(hotkeyManager: hotkeyManager)
                    }

                    // MARK: - Notifications
                    SettingsSection(title: "通知", icon: "bell.badge") {
                        NotificationSettingsView()
                    }

                    // MARK: - Startup
                    SettingsSection(title: "启动", icon: "power") {
                        Toggle(isOn: $launchAtLogin) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("登录时启动 Riptide")
                                    .font(.callout)
                                    .foregroundStyle(Theme.text)
                                Text(launchAtLoginSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtext)
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(!launchAgentLoaded || launchAgentBusy)
                        .accessibilityIdentifier(A11yID.Settings.launchAtLogin)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))

                        if let error = launchAgentError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Theme.danger)
                                .padding(.horizontal)
                        }
                    }

                    // MARK: - Core
                    SettingsSection(title: "内核管理", icon: "cpu") {
                        NavigationLink {
                            KernelSwitcherView()
                        } label: {
                            SettingsRow(
                                icon: "cpu",
                                title: "内核切换",
                                subtitle: "查看已安装的代理内核及状态",
                                accent: Theme.accent
                            )
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("mihomo 版本")
                                    .font(.callout)
                                    .foregroundStyle(Theme.text)
                                Text(vm.mihomoVersion.isEmpty ? "未安装" : vm.mihomoVersion)
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtext)
                            }
                            Spacer()
                            Picker("", selection: $vm.mihomoChannel) {
                                Text("稳定版").tag(MihomoDownloader.Channel.stable)
                                Text("测试版").tag(MihomoDownloader.Channel.alpha)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))

                        if vm.isDownloadingMihomo {
                            VStack(spacing: 4) {
                                ProgressView(value: vm.mihomoDownloadProgress)
                                Text("下载中… \(Int(vm.mihomoDownloadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtext)
                            }
                            .padding(.horizontal)
                        }

                        if let error = vm.mihomoDownloadError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Theme.danger)
                                .padding(.horizontal)
                        }
                    }

                    // MARK: - Diagnostics
                    SettingsSection(title: "诊断", icon: "stethoscope") {
                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            SettingsRow(
                                icon: "stethoscope",
                                title: "网络诊断",
                                subtitle: "检查 Helper、内核、DNS、连接和配置状态",
                                accent: Theme.success
                            )
                        }
                    }

                    // MARK: - WebDAV
                    SettingsSection(title: "同步", icon: "icloud") {
                        NavigationLink {
                            WebDAVSettingsView()
                        } label: {
                            SettingsRow(
                                icon: "externaldrive.badge.icloud",
                                title: "WebDAV 同步",
                                subtitle: "备份和同步配置到 WebDAV 服务器",
                                accent: Theme.accent
                            )
                        }
                    }

                    // MARK: - General
                    SettingsSection(title: "通用", icon: "gearshape") {
                        // Theme picker
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("外观")
                                    .font(.callout)
                                    .foregroundStyle(Theme.text)
                                Text(themeModeLabel)
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtext)
                            }
                            Spacer()
                            Picker("", selection: Binding(
                                get: { themeManager.appearanceMode },
                                set: { themeManager.setAppearance($0) }
                            )) {
                                Text("跟随系统").tag(ThemeManager.AppearanceMode.system)
                                Text("浅色").tag(ThemeManager.AppearanceMode.light)
                                Text("深色").tag(ThemeManager.AppearanceMode.dark)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 210)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))

                        NavigationLink {
                            LanguageSelectorView()
                        } label: {
                            SettingsRow(
                                icon: "globe",
                                title: "语言",
                                subtitle: "选择界面语言",
                                accent: Theme.accent
                            )
                        }
                    }
                }
            }
            .contentMargins(.all, Theme.Spacing.lg, for: .scrollContent)
            .navigationTitle("设置")
            .background(Theme.backgroundGradient.ignoresSafeArea())
        }
        .task {
            await loadLaunchAtLoginState()
        }
        .onChange(of: launchAtLogin) { _, newValue in
            guard launchAgentLoaded else { return }
            Task { await applyLaunchAtLogin(newValue) }
        }
    }

    private var launchAtLoginSubtitle: String {
        if !launchAgentLoaded {
            return "正在读取登录项状态…"
        }
        if launchAgentBusy {
            return launchAtLogin ? "正在启用登录项…" : "正在禁用登录项…"
        }
        return launchAtLogin
            ? "已添加至 ~/Library/LaunchAgents"
            : "开启后 Riptide 将在用户登录时自动启动"
    }

    private func loadLaunchAtLoginState() async {
        let registered = await launchAgent.isRegistered()
        launchAtLogin = registered
        launchAgentLoaded = true
    }

    private func applyLaunchAtLogin(_ enabled: Bool) async {
        launchAgentBusy = true
        launchAgentError = nil
        do {
            if enabled {
                try await launchAgent.register()
            } else {
                try await launchAgent.unregister()
            }
            launchAgentError = nil
        } catch {
            launchAgentError = "无法更新登录项: \(error.localizedDescription)"
            launchAtLogin = await launchAgent.isRegistered()
        }
        launchAgentBusy = false
    }

    private var themeModeLabel: String {
        switch themeManager.appearanceMode {
        case .system: return "自动匹配系统外观"
        case .light:  return "始终使用浅色模式"
        case .dark:   return "始终使用深色模式"
        }
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.accent)
            content()
        }
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

// MARK: - Gateway Placeholder

/// Placeholder for gateway settings — backend (GatewayEnabler) is ready, UI to come.
struct GatewaySettingsPlaceholderView: View {
    @State private var subnet = GatewayEnabler.GatewayConfig.default.subnet
    @State private var gatewayIP = GatewayEnabler.GatewayConfig.default.gatewayIP
    @State private var enabled = false
    @State private var devices: [ConnectedDevice] = []

    private let enabler = GatewayEnabler()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("网关模式", systemImage: "globe.americas")
                .font(.headline)
                .foregroundStyle(Theme.text)

            Toggle("启用网关模式", isOn: $enabled)

            if enabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("子网: \(subnet)")
                    Text("网关 IP: \(gatewayIP)")
                    Text("DHCP: \(GatewayEnabler.GatewayConfig.default.dhcpRangeStart) - \(GatewayEnabler.GatewayConfig.default.dhcpRangeEnd)")
                }
                .font(.caption)
                .foregroundStyle(Theme.subtext)

                if !devices.isEmpty {
                    Text("已连接设备 (\(devices.count))")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                    ForEach(devices) { device in
                        HStack {
                            Text(device.hostname)
                            Text(device.ip)
                                .foregroundStyle(Theme.subtext)
                            Text(device.mac)
                                .font(.caption2)
                                .foregroundStyle(Theme.subtext)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .task {
            devices = enabler.connectedDevices()
        }
    }
}
