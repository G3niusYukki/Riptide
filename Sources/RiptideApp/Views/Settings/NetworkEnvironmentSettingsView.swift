import SwiftUI
import Riptide

// MARK: - A11y Identifiers

extension A11yID {
    public enum NetworkEnv {
        public static let currentSSID = "network-env.current-ssid"
        public static let activeScene = "network-env.active-scene"
        public static let profileRow = "network-env.profile-row"
        public static let addSceneButton = "network-env.add-scene-button"
        public static let editSheet = "network-env.edit-sheet"
        public static let monitorToggle = "network-env.monitor-toggle"
    }
}

// MARK: - Network Environment Settings View

/// UI for configuring WiFi SSID → proxy mode / profile auto-switching.
///
/// Each `EnvironmentProfile` binds a specific SSID to a connection mode
/// (system proxy vs. TUN), a proxy mode (rule / global / direct), and an
/// optional `Profile` to switch to. The header surfaces the current WiFi
/// SSID (via `NetworkEnvironmentManager.currentWiFiSSID()`) and the active
/// scene (the profile whose `ssidName` matches the current network).
struct NetworkEnvironmentSettingsView: View {
    @Bindable var vm: AppViewModel

    @State private var profiles: [EnvironmentProfile] = []
    @State private var currentSSID: String?
    @State private var autoSwitchEnabled = false

    @State private var editingProfile: EnvironmentProfile?
    @State private var showingAddSheet = false
    @State private var isAddingCurrent = false

    private let envManager = NetworkEnvironmentManager()
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            currentNetworkSection
            profilesListSection
            Spacer()
            infoFooter
        }
        .padding()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .task {
            await refreshState()
        }
        .onChange(of: autoSwitchEnabled) { _, newValue in
            Task {
                if newValue {
                    await envManager.startMonitoring()
                } else {
                    await envManager.stopMonitoring()
                }
            }
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
        .sheet(item: $editingProfile) { profile in
            EditEnvironmentProfileSheet(
                profile: profile,
                vm: vm,
                isNew: false,
                onSave: { updated in
                    Task {
                        await envManager.upsertProfile(updated)
                        await refreshProfiles()
                    }
                    editingProfile = nil
                },
                onCancel: { editingProfile = nil }
            )
            .frame(width: 420, height: 380)
        }
        .sheet(isPresented: $showingAddSheet) {
            let newProfile = EnvironmentProfile(ssidName: currentSSID ?? "")
            EditEnvironmentProfileSheet(
                profile: newProfile,
                vm: vm,
                isNew: true,
                onSave: { created in
                    Task {
                        await envManager.upsertProfile(created)
                        await refreshProfiles()
                    }
                    showingAddSheet = false
                },
                onCancel: { showingAddSheet = false }
            )
            .frame(width: 420, height: 380)
        }
        .sheet(isPresented: $isAddingCurrent) {
            if let ssid = currentSSID {
                EditEnvironmentProfileSheet(
                    profile: EnvironmentProfile(ssidName: ssid),
                    vm: vm,
                    isNew: true,
                    onSave: { created in
                        Task {
                            await envManager.upsertProfile(created)
                            await refreshProfiles()
                        }
                        isAddingCurrent = false
                    },
                    onCancel: { isAddingCurrent = false }
                )
                .frame(width: 420, height: 380)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("网络环境自动切换", systemImage: "wifi.router")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Spacer()
            Toggle("自动切换", isOn: $autoSwitchEnabled)
                .toggleStyle(.switch)
                .accessibilityIdentifier(A11yID.NetworkEnv.monitorToggle)
        }
    }

    // MARK: - Current Network Section

    private var currentNetworkSection: some View {
        HStack(alignment: .top, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: currentSSID == nil ? "cable.connector" : "wifi")
                    .foregroundStyle(currentSSID == nil ? Theme.subtext : Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentSSID ?? "未连接 WiFi")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.text)
                        .accessibilityIdentifier(A11yID.NetworkEnv.currentSSID)
                    Text(currentSSID == nil ? "以太网或无 WiFi — 自动切换不可用" : "当前网络")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
            }

            Divider()
                .frame(height: 32)

            HStack(spacing: 8) {
                Image(systemName: activeSceneName == nil ? "location.slash" : "location.fill")
                    .foregroundStyle(activeSceneName == nil ? Theme.subtext : Theme.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeSceneName ?? "未匹配场景")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.text)
                        .accessibilityIdentifier(A11yID.NetworkEnv.activeScene)
                    Text(activeSceneName == nil ? "使用默认代理模式" : "当前激活场景")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
            }

            Spacer()

            if let ssid = currentSSID,
               !profiles.contains(where: { $0.ssidName == ssid }) {
                Button {
                    isAddingCurrent = true
                } label: {
                    Label("为此网络添加场景", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Profiles List Section

    private var profilesListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("已配置场景", systemImage: "list.bullet.rectangle")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("添加场景", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(A11yID.NetworkEnv.addSceneButton)
            }

            if profiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.subtext)
                    Text("未配置任何网络环境")
                        .foregroundStyle(Theme.subtext)
                    Text("连接到 WiFi 后点击「添加场景」来创建自动切换规则")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            } else {
                ForEach(profiles) { profile in
                    EnvironmentProfileRow(
                        profile: profile,
                        isActive: profile.ssidName == currentSSID,
                        onEdit: {
                            editingProfile = profile
                        },
                        onDelete: {
                            Task {
                                await envManager.removeProfile(id: profile.id)
                                await refreshProfiles()
                            }
                        },
                        onToggleEnabled: { newValue in
                            var updated = profile
                            updated.enabled = newValue
                            Task {
                                await envManager.upsertProfile(updated)
                                await refreshProfiles()
                            }
                        }
                    )
                    .accessibilityIdentifier(A11yID.NetworkEnv.profileRow + ".\(profile.ssidName)")
                }
            }
        }
    }

    // MARK: - Info Footer

    private var infoFooter: some View {
        Text("当连接到不同的 WiFi 网络时，Riptide 可自动切换代理模式、代理策略和配置。仅在 WiFi 环境下生效，以太网连接不受影响。")
            .font(.caption)
            .foregroundStyle(Theme.subtext)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Helpers

    private var activeSceneName: String? {
        guard let ssid = currentSSID else { return nil }
        return profiles.first(where: { $0.ssidName == ssid && $0.enabled })?.ssidName
    }

    private func refreshState() async {
        await refreshProfiles()
        currentSSID = await envManager.currentWiFiSSID()
        startSSIDPolling()
    }

    private func refreshProfiles() async {
        let loaded = await envManager.allProfiles
        profiles = loaded
    }

    /// Polls the current SSID every 5 seconds while the view is on screen so
    /// the header reflects network changes without requiring a manual reload.
    private func startSSIDPolling() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                let ssid = await envManager.currentWiFiSSID()
                if ssid != currentSSID {
                    currentSSID = ssid
                }
                // Reload profiles in case the manager was updated externally.
                let updated = await envManager.allProfiles
                if updated != profiles {
                    profiles = updated
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}

// MARK: - Environment Profile Row

struct EnvironmentProfileRow: View {
    let profile: EnvironmentProfile
    let isActive: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleEnabled: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Active indicator dot
            Circle()
                .fill(isActive && profile.enabled ? Theme.success : Theme.subtext.opacity(0.3))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "wifi")
                        .foregroundStyle(profile.enabled ? Theme.accent : Theme.subtext)
                    Text(profile.ssidName)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(profile.enabled ? Theme.text : Theme.subtext)
                    if isActive && profile.enabled {
                        Text("活跃")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.success.opacity(0.2))
                            .foregroundStyle(Theme.success)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    badge(icon: profile.connectionMode == .tun ? "shield.lefthalf.filled" : "network",
                          text: profile.connectionMode == .tun ? "TUN" : "系统代理",
                          color: profile.connectionMode == .tun ? Theme.warning : Theme.accent)
                    badge(icon: proxyModeIcon(profile.proxyMode),
                          text: proxyModeLabel(profile.proxyMode),
                          color: Theme.subtext)
                    if let pid = profile.profileID {
                        badge(icon: "doc.text", text: shortProfileID(pid), color: Theme.subtext)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { profile.enabled },
                set: { onToggleEnabled($0) }
            ))
            .labelsHidden()

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .help("编辑")

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(.plain)
            .help("删除")
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func badge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private func proxyModeIcon(_ mode: ProxyMode) -> String {
        switch mode {
        case .rule:   return "list.bullet.indent"
        case .global: return "globe"
        case .direct: return "arrow.right"
        }
    }

    private func proxyModeLabel(_ mode: ProxyMode) -> String {
        switch mode {
        case .rule:   return "规则"
        case .global: return "全局"
        case .direct: return "直连"
        }
    }

    private func shortProfileID(_ id: UUID) -> String {
        let str = id.uuidString
        return "配置 \(String(str.prefix(8)))"
    }
}

// MARK: - Edit Environment Profile Sheet

/// Edit or create an `EnvironmentProfile`. The user picks:
/// - SSID (free-form text, defaults to the current WiFi network)
/// - Connection mode (system proxy / TUN)
/// - Proxy mode (rule / global / direct)
/// - Optional `Profile` binding (nil = unbind)
private struct EditEnvironmentProfileSheet: View {
    let initialProfile: EnvironmentProfile
    let vm: AppViewModel
    let isNew: Bool
    let onSave: (EnvironmentProfile) -> Void
    let onCancel: () -> Void

    @State private var ssid: String
    @State private var connectionMode: RuntimeMode
    @State private var proxyMode: ProxyMode
    @State private var profileID: UUID?
    @State private var enabled: Bool

    init(
        profile: EnvironmentProfile,
        vm: AppViewModel,
        isNew: Bool,
        onSave: @escaping (EnvironmentProfile) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialProfile = profile
        self.vm = vm
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel

        _ssid = State(initialValue: profile.ssidName)
        _connectionMode = State(initialValue: profile.connectionMode)
        _proxyMode = State(initialValue: profile.proxyMode)
        _profileID = State(initialValue: profile.profileID)
        _enabled = State(initialValue: profile.enabled)
    }

    private var canSave: Bool {
        !ssid.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "添加网络场景" : "编辑网络场景")
                .font(.headline)
                .foregroundStyle(Theme.text)
                .accessibilityIdentifier(A11yID.NetworkEnv.editSheet)

            Form {
                Section("WiFi SSID") {
                    TextField("SSID 名称", text: $ssid)
                        .textFieldStyle(.roundedBorder)
                }

                Section("代理模式") {
                    Picker("代理模式", selection: $proxyMode) {
                        Text("规则").tag(ProxyMode.rule)
                        Text("全局").tag(ProxyMode.global)
                        Text("直连").tag(ProxyMode.direct)
                    }
                    .pickerStyle(.segmented)
                }

                Section("连接方式") {
                    Picker("连接方式", selection: $connectionMode) {
                        Text("系统代理").tag(RuntimeMode.systemProxy)
                        Text("TUN").tag(RuntimeMode.tun)
                    }
                    .pickerStyle(.segmented)
                }

                if !vm.profiles.isEmpty {
                    Section("关联配置 (可选)") {
                        Picker("配置", selection: $profileID) {
                            Text("不关联").tag(UUID?.none)
                            ForEach(vm.profiles) { profile in
                                Text(profile.name).tag(UUID?.some(profile.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section {
                    Toggle("启用此场景", isOn: $enabled)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                Spacer()
                Button(isNew ? "添加" : "保存") {
                    var updated = initialProfile
                    updated.ssidName = ssid.trimmingCharacters(in: .whitespaces)
                    updated.connectionMode = connectionMode
                    updated.proxyMode = proxyMode
                    updated.profileID = profileID
                    updated.enabled = enabled
                    onSave(updated)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding()
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}

// MARK: - Legacy Add Environment Sheet (kept for API compatibility)

/// Backwards-compatible wrapper preserved for any caller that still uses
/// `AddEnvironmentSheet`. New code should use `EditEnvironmentProfileSheet`.
struct AddEnvironmentSheet: View {
    let ssid: String
    let vm: AppViewModel
    let onAdd: (EnvironmentProfile) -> Void
    let onCancel: () -> Void

    var body: some View {
        EditEnvironmentProfileSheet(
            profile: EnvironmentProfile(ssidName: ssid),
            vm: vm,
            isNew: true,
            onSave: onAdd,
            onCancel: onCancel
        )
    }
}
