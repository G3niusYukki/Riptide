import SwiftUI
import Riptide

// MARK: - Scene Editor View

/// Create and manage network environment scenes.
/// Each scene binds a WiFi SSID → proxy mode + proxy group + optional profile.
///
/// When the matching SSID is detected, the `ModeCoordinator` auto-switches
/// to the configured mode and proxy group via `NetworkEnvironmentManager`.
struct SceneEditorView: View {
    @Bindable var vm: AppViewModel
    @State private var scenes: [SceneConfig] = []
    @State private var editingScene: SceneConfig?
    @State private var showAddSheet = false

    // Detected nearby SSIDs for the picker
    @State private var detectedSSIDs: [String] = []
    @State private var currentSSID: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("场景管理", systemImage: "wifi.router")
                    .font(.headline)
                    .foregroundStyle(Theme.text)

                Spacer()

                if let ssid = currentSSID {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 6, height: 6)
                        Text("当前: \(ssid)")
                            .font(.caption)
                            .foregroundStyle(Theme.subtext)
                    }
                }

                Button {
                    editingScene = SceneConfig()
                    showAddSheet = true
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Scene list
            if scenes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.subtext)
                    Text("暂无场景")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                    Text("添加场景后，Riptide 会在连接指定 WiFi 时自动切换代理设置。")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtext)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(scenes) { scene in
                        SceneRow(
                            scene: scene,
                            isActive: scene.ssidName == currentSSID,
                            onEdit: {
                                editingScene = scene
                                showAddSheet = true
                            },
                            onDelete: {
                                scenes.removeAll { $0.id == scene.id }
                                saveScenes()
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }

            // Security policy
            VStack(alignment: .leading, spacing: 8) {
                Label("未知网络安全", systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(Theme.text)

                Picker("未知网络时使用", selection: $vm.unknownNetworkPolicy) {
                    Text("保持当前").tag(UnknownNetworkPolicy.keepCurrent)
                    Text("切换到最安全节点").tag(UnknownNetworkPolicy.safest)
                    Text("直连模式").tag(UnknownNetworkPolicy.direct)
                }
                .pickerStyle(.segmented)

                Text("当连接到未配置场景的 WiFi 时自动切换到此模式。")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .padding()
        }
        .frame(width: 560, height: 480)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .sheet(isPresented: $showAddSheet) {
            SceneFormView(
                scene: editingScene ?? SceneConfig(),
                availableSSIDs: detectedSSIDs,
                currentSSID: currentSSID,
                proxyGroups: vm.proxyGroupNames,
                onSave: { newScene in
                    if let idx = scenes.firstIndex(where: { $0.id == newScene.id }) {
                        scenes[idx] = newScene
                    } else {
                        scenes.append(newScene)
                    }
                    saveScenes()
                    showAddSheet = false
                },
                onCancel: {
                    showAddSheet = false
                }
            )
        }
        .onAppear {
            loadScenes()
            refreshSSIDs()
        }
    }

    // MARK: - Persistence

    private func saveScenes() {
        guard let data = try? JSONEncoder().encode(scenes) else { return }
        UserDefaults.standard.set(data, forKey: "com.riptide.scenes")
    }

    private func loadScenes() {
        guard let data = UserDefaults.standard.data(forKey: "com.riptide.scenes"),
              let loaded = try? JSONDecoder().decode([SceneConfig].self, from: data) else {
            scenes = []
            return
        }
        scenes = loaded
    }

    private func refreshSSIDs() {
        // In production: call NetworkEnvironmentManager to get current + nearby SSIDs
        currentSSID = "MyHomeWiFi" // placeholder
        detectedSSIDs = ["MyHomeWiFi", "OfficeWiFi", "CoffeeShop", "AirportWiFi"]
    }
}

// MARK: - Scene Config Model

struct SceneConfig: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String = ""
    var ssidName: String = ""
    var connectionMode: SceneConnectionMode = .systemProxy
    var proxyGroupName: String = ""
    var profileID: String?
    var isEnabled: Bool = true
    var notifyOnSwitch: Bool = true
}

enum SceneConnectionMode: String, CaseIterable, Codable {
    case systemProxy = "系统代理"
    case tun = "TUN 模式"
    case direct = "直连模式"
}

enum UnknownNetworkPolicy: String, CaseIterable {
    case keepCurrent = "保持当前"
    case safest = "最安全"
    case direct = "直连"
}

// MARK: - Scene Row

struct SceneRow: View {
    let scene: SceneConfig
    let isActive: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Active indicator
            Circle()
                .fill(isActive ? Theme.success : Theme.subtext.opacity(0.3))
                .frame(width: 8, height: 8)

            // Scene info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(scene.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.text)

                    if isActive {
                        Text("活跃")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.success.opacity(0.2))
                            .foregroundStyle(Theme.success)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Label(scene.ssidName, systemImage: "wifi")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtext)

                    Text("→")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtext)

                    Text(scene.connectionMode.rawValue)
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)

                    if !scene.proxyGroupName.isEmpty {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtext)
                        Text(scene.proxyGroupName)
                            .font(.caption2)
                            .foregroundStyle(Theme.subtext)
                    }
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Scene Form (Add/Edit)

struct SceneFormView: View {
    @State var scene: SceneConfig
    let availableSSIDs: [String]
    let currentSSID: String?
    let proxyGroups: [String]
    let onSave: (SceneConfig) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(scene.name.isEmpty ? "添加场景" : "编辑场景")
                .font(.headline)

            Form {
                TextField("场景名称", text: $scene.name)
                    .textFieldStyle(.roundedBorder)

                Picker("WiFi SSID", selection: $scene.ssidName) {
                    if currentSSID != nil {
                        Text("当前: \(currentSSID!)").tag(currentSSID!)
                    }
                    ForEach(availableSSIDs, id: \.self) { ssid in
                        Text(ssid).tag(ssid)
                    }
                    if !availableSSIDs.contains(scene.ssidName) && !scene.ssidName.isEmpty {
                        Text("其他: \(scene.ssidName)").tag(scene.ssidName)
                    }
                }

                Picker("连接模式", selection: $scene.connectionMode) {
                    ForEach(SceneConnectionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("代理组", selection: $scene.proxyGroupName) {
                    Text("默认").tag("")
                    ForEach(proxyGroups, id: \.self) { group in
                        Text(group).tag(group)
                    }
                }

                Toggle("启用", isOn: $scene.isEnabled)
                Toggle("切换时通知", isOn: $scene.notifyOnSwitch)
            }
            .formStyle(.grouped)

            HStack {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)

                Button("保存") {
                    onSave(scene)
                }
                .buttonStyle(.borderedProminent)
                .disabled(scene.name.isEmpty || scene.ssidName.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 380)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}

// MARK: - AppViewModel Extensions

extension AppViewModel {
    /// Available proxy group names for scene assignment.
    var proxyGroupNames: [String] {
        proxyGroups.compactMap { group in
            group.kind == .select || group.kind == .urlTest || group.kind == .fallback
                ? group.name
                : nil
        }
    }

    /// Unknown network policy (persisted).
    var unknownNetworkPolicy: UnknownNetworkPolicy {
        get {
            let raw = UserDefaults.standard.string(forKey: "com.riptide.unknownNetworkPolicy") ?? ""
            return UnknownNetworkPolicy(rawValue: raw) ?? .keepCurrent
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "com.riptide.unknownNetworkPolicy")
        }
    }
}
