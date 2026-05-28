import SwiftUI
import Riptide

// MARK: - Per-App Proxy Rule Editor

/// Configure per-application proxy routing.
///
/// For each installed app, you can override the proxy policy:
/// - **默认**: Follow the global rule engine
/// - **代理**: Force all traffic from this app through the selected proxy
/// - **直连**: Force all traffic from this app to bypass the proxy
///
/// Implementation: injects `PROCESS-NAME` rules into the profile config
/// before passing to mihomo. On macOS, process matching uses the bundle
/// executable name; on the Swift engine, it uses the process path.
struct PerAppRuleEditor: View {
    @Bindable var vm: AppViewModel
    @State private var rules: [PerAppRule] = []
    @State private var searchText = ""
    @State private var editingRule: PerAppRule?
    @State private var showAddSheet = false

    private var filteredApps: [PerAppRule] {
        guard !searchText.isEmpty else { return rules }
        let query = searchText.lowercased()
        return rules.filter {
            $0.appName.lowercased().contains(query)
            || $0.bundleID.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("应用分流", systemImage: "square.grid.3x3.topleft.filled")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    editingRule = PerAppRule()
                    showAddSheet = true
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            // Rule list
            if rules.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.subtext)
                    Text("暂无应用分流规则")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                    Text("为特定应用设置独立的代理策略，例如 Safari 走节点 A，Chrome 直连。")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtext)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            } else {
                List {
                    Section {
                        ForEach(filteredApps) { rule in
                            PerAppRuleRow(
                                rule: rule,
                                onToggle: {
                                    if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
                                        rules[idx].isEnabled.toggle()
                                        saveRules()
                                    }
                                },
                                onDelete: {
                                    rules.removeAll { $0.id == rule.id }
                                    saveRules()
                                }
                            )
                        }
                    } header: {
                        Text("自定义规则 (\(rules.count))")
                    }
                }
                .listStyle(.plain)
            }

            // Info footer
            VStack(alignment: .leading, spacing: 4) {
                Label("工作原理", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                Text("应用分流通过 PROCESS-NAME 规则实现。macOS 上会匹配进程的可执行文件名。修改后需要重新连接使规则生效。")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .padding()
        }
        .frame(width: 560, height: 480)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .searchable(text: $searchText, prompt: "搜索应用名或 Bundle ID")
        .sheet(isPresented: $showAddSheet) {
            PerAppRuleFormView(
                rule: editingRule ?? PerAppRule(),
                proxyGroups: vm.proxyGroupNames,
                onSave: { newRule in
                    if let idx = rules.firstIndex(where: { $0.id == newRule.id }) {
                        rules[idx] = newRule
                    } else {
                        rules.append(newRule)
                    }
                    saveRules()
                    showAddSheet = false
                },
                onCancel: {
                    showAddSheet = false
                }
            )
        }
        .onAppear {
            loadRules()
        }
    }

    // MARK: - Persistence

    private func saveRules() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: "com.riptide.perAppRules")
    }

    private func loadRules() {
        guard let data = UserDefaults.standard.data(forKey: "com.riptide.perAppRules"),
              let loaded = try? JSONDecoder().decode([PerAppRule].self, from: data) else {
            rules = []
            return
        }
        rules = loaded
    }
}

// MARK: - Per-App Rule Model

struct PerAppRule: Identifiable, Codable {
    var id: UUID = UUID()
    var appName: String = ""
    var bundleID: String = ""
    var processName: String = "" // actual executable name for PROCESS-NAME matching
    var policy: PerAppPolicy = .proxy
    var proxyGroupName: String = ""
    var isEnabled: Bool = true
}

enum PerAppPolicy: String, CaseIterable, Codable {
    case proxy = "代理"
    case direct = "直连"
    case reject = "拒绝"
}

// MARK: - Per-App Rule Row

struct PerAppRuleRow: View {
    let rule: PerAppRule
    let onToggle: () -> Void
    let onDelete: () -> Void

    private var policyColor: Color {
        switch rule.policy {
        case .proxy: return Theme.accent
        case .direct: return Theme.success
        case .reject: return Theme.danger
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // App icon placeholder
            Image(systemName: "app.fill")
                .font(.title3)
                .foregroundStyle(Theme.subtext)
                .frame(width: 28, height: 28)
                .background(Theme.subtext.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // App info
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.appName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.text)

                Text(rule.processName)
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Policy badge
            HStack(spacing: 4) {
                Circle()
                    .fill(policyColor)
                    .frame(width: 6, height: 6)
                Text(rule.policy.rawValue)
                    .font(.caption2)
                    .foregroundStyle(policyColor)

                if rule.policy == .proxy, !rule.proxyGroupName.isEmpty {
                    Text("→ \(rule.proxyGroupName)")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtext)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(policyColor.opacity(0.1))
            .clipShape(Capsule())

            // Toggle + Delete
            Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { _ in onToggle() }))
                .toggleStyle(.switch)
                .scaleEffect(0.7)
                .frame(width: 40)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Rule Form (Add/Edit)

struct PerAppRuleFormView: View {
    @State var rule: PerAppRule
    let proxyGroups: [String]
    let onSave: (PerAppRule) -> Void
    let onCancel: () -> Void

    // Sample installed apps for the picker
    private let sampleApps: [(name: String, bundleID: String, processName: String)] = [
        ("Safari", "com.apple.Safari", "Safari"),
        ("Google Chrome", "com.google.Chrome", "Google Chrome"),
        ("Firefox", "org.mozilla.firefox", "firefox"),
        ("Terminal", "com.apple.Terminal", "Terminal"),
        ("VS Code", "com.microsoft.VSCode", "Code"),
        ("Slack", "com.tinyspeck.slackmacgap", "Slack"),
        ("Discord", "com.hnc.Discord", "Discord"),
        ("Spotify", "com.spotify.client", "Spotify"),
        ("Telegram", "ru.keepcoder.Telegram", "Telegram"),
        ("Zoom", "us.zoom.xos", "zoom.us"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text(rule.appName.isEmpty ? "添加应用" : "编辑应用")
                .font(.headline)

            Form {
                Picker("应用", selection: Binding(
                    get: { rule.bundleID },
                    set: { newBundleID in
                        if let match = sampleApps.first(where: { $0.bundleID == newBundleID }) {
                            rule.appName = match.name
                            rule.bundleID = match.bundleID
                            rule.processName = match.processName
                        }
                    }
                )) {
                    ForEach(sampleApps, id: \.bundleID) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }

                TextField("进程名 (PROCESS-NAME)", text: $rule.processName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))

                Picker("策略", selection: $rule.policy) {
                    ForEach(PerAppPolicy.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }

                if rule.policy == .proxy {
                    Picker("代理组", selection: $rule.proxyGroupName) {
                        Text("默认").tag("")
                        ForEach(proxyGroups, id: \.self) { group in
                            Text(group).tag(group)
                        }
                    }
                }

                Toggle("启用", isOn: $rule.isEnabled)
            }
            .formStyle(.grouped)

            HStack {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)

                Button("保存") {
                    onSave(rule)
                }
                .buttonStyle(.borderedProminent)
                .disabled(rule.processName.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
