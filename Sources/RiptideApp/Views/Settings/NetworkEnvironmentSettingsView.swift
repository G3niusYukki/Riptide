import SwiftUI
import Riptide

// MARK: - Network Environment Settings View

/// UI for configuring WiFi SSID → proxy mode / profile auto-switching.
struct NetworkEnvironmentSettingsView: View {
    @Bindable var vm: AppViewModel
    @State private var profiles: [EnvironmentProfile] = []
    @State private var currentSSID: String?
    @State private var isAddingCurrent = false
    @State private var autoSwitchEnabled = false

    private let envManager = NetworkEnvironmentManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("网络环境自动切换", systemImage: "wifi.router")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Toggle("自动切换", isOn: $autoSwitchEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: autoSwitchEnabled) { _, newValue in
                        Task {
                            if newValue {
                                await envManager.startMonitoring()
                            } else {
                                await envManager.stopMonitoring()
                            }
                        }
                    }
            }

            // Current network info
            if let ssid = currentSSID {
                HStack {
                    Image(systemName: "wifi")
                        .foregroundStyle(Theme.accent)
                    Text("当前网络: \(ssid)")
                        .font(.callout)
                        .foregroundStyle(Theme.text)
                    Spacer()
                    if !profiles.contains(where: { $0.ssidName == ssid }) {
                        Button("添加此网络") {
                            isAddingCurrent = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            } else {
                HStack {
                    Image(systemName: "cable.connector")
                        .foregroundStyle(Theme.subtext)
                    Text("以太网或无 WiFi — 自动切换不可用")
                        .font(.callout)
                        .foregroundStyle(Theme.subtext)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            }

            // Configured environments
            if profiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.subtext)
                    Text("未配置任何网络环境")
                        .foregroundStyle(Theme.subtext)
                    Text("连接到 WiFi 后点击「添加此网络」来创建自动切换规则")
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
                        onUpdate: { updated in
                            Task { await envManager.upsertProfile(updated) }
                            refreshProfiles()
                        },
                        onDelete: {
                            Task { await envManager.removeProfile(id: profile.id) }
                            refreshProfiles()
                        }
                    )
                }
            }

            Spacer()

            // Info footer
            Text("当连接到不同的 WiFi 网络时，Riptide 可自动切换代理模式和配置。仅在 WiFi 环境下生效，以太网连接不受影响。")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .task {
            refreshProfiles()
            currentSSID = await envManager.currentWiFiSSID()
        }
        .sheet(isPresented: $isAddingCurrent) {
            if let ssid = currentSSID {
                AddEnvironmentSheet(
                    ssid: ssid,
                    vm: vm,
                    onAdd: { profile in
                        Task { await envManager.upsertProfile(profile) }
                        refreshProfiles()
                        isAddingCurrent = false
                    },
                    onCancel: { isAddingCurrent = false }
                )
                .frame(width: 400, height: 350)
            }
        }
    }

    private func refreshProfiles() {
        Task {
            profiles = await envManager.allProfiles
        }
    }
}

// MARK: - Environment Profile Row

struct EnvironmentProfileRow: View {
    let profile: EnvironmentProfile
    let onUpdate: (EnvironmentProfile) -> Void
    let onDelete: () -> Void

    @State private var selectedMode: String
    @State private var isEnabled: Bool

    init(profile: EnvironmentProfile, onUpdate: @escaping (EnvironmentProfile) -> Void, onDelete: @escaping () -> Void) {
        self.profile = profile
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _selectedMode = State(initialValue: profile.connectionMode == .tun ? "TUN" : "系统代理")
        _isEnabled = State(initialValue: profile.enabled)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "wifi")
                        .foregroundStyle(isEnabled ? Theme.accent : Theme.subtext)
                    Text(profile.ssidName)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(isEnabled ? Theme.text : Theme.subtext)
                }

                HStack(spacing: 8) {
                    Picker("模式", selection: $selectedMode) {
                        Text("系统代理").tag("系统代理")
                        Text("TUN").tag("TUN")
                        Text("直连").tag("直连")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .onChange(of: selectedMode) { _, newValue in
                        var updated = profile
                        switch newValue {
                        case "TUN": updated.connectionMode = .tun
                        case "直连": updated.connectionMode = .systemProxy
                        default: updated.connectionMode = .systemProxy
                        }
                        onUpdate(updated)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .onChange(of: isEnabled) { _, newValue in
                    var updated = profile
                    updated.enabled = newValue
                    onUpdate(updated)
                }

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

// MARK: - Add Environment Sheet

struct AddEnvironmentSheet: View {
    let ssid: String
    let vm: AppViewModel
    let onAdd: (EnvironmentProfile) -> Void
    let onCancel: () -> Void

    @State private var selectedMode = "系统代理"
    @State private var selectedProfileID: UUID?

    var body: some View {
        VStack(spacing: 16) {
            Text("添加网络环境")
                .font(.headline)
                .foregroundStyle(Theme.text)

            VStack(alignment: .leading, spacing: 8) {
                Text("WiFi: \(ssid)")
                    .font(.callout)
                    .foregroundStyle(Theme.text)

                Text("当连接到此 WiFi 时自动切换到：")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)

                Picker("模式", selection: $selectedMode) {
                    Text("系统代理").tag("系统代理")
                    Text("TUN 模式").tag("TUN")
                }
                .pickerStyle(.radioGroup)

                if !vm.profiles.isEmpty {
                    Text("关联配置 (可选):")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                    Picker("配置", selection: $selectedProfileID) {
                        Text("不关联").tag(nil as UUID?)
                        ForEach(vm.profiles) { profile in
                            Text(profile.name).tag(profile.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            HStack {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                Spacer()
                Button("添加") {
                    let mode: RuntimeMode = selectedMode == "TUN" ? .tun : .systemProxy
                    let profile = EnvironmentProfile(
                        ssidName: ssid,
                        connectionMode: mode,
                        profileID: selectedProfileID
                    )
                    onAdd(profile)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
