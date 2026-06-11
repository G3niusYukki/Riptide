import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Riptide

struct ConfigTabView: View {
    // swiftlint:disable:next identifier_name
    @Bindable var vm: AppViewModel
    @State private var showHelperSetup = false
    @State private var showAddSubscription = false
    @State private var editingSubscription: SubscriptionDisplay?
    @State private var showImportPreview = false
    @State private var importPreviewURL: URL?
    @State private var importPreviewYAML = ""
    @State private var importPreviewFileName = ""
    @State private var isDragOver = false
    @State private var importErrorMessage: String?
    @State private var showImportError = false
    @State private var showYAMLEditor = false
    @State private var yamlEditorProfileID: UUID?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Mode selector card
                modeSelectorCard

                // Active profile card
                if let profile = vm.activeProfile {
                    ProfileCard(profile: profile, isActive: true) {
                        yamlEditorProfileID = profile.id
                        showYAMLEditor = true
                    } onDelete: {
                        vm.removeProfile(profile)
                    }
                }

                // Import controls (button + clipboard + drag-drop target)
                VStack(spacing: 12) {
                    Button {
                        importConfig()
                    } label: {
                        Label("导入配置文件", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .accessibilityIdentifier(A11yID.Config.importButton)

                    Button {
                        importFromClipboard()
                    } label: {
                        Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("riptide.config.clipboardImportButton")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(
                            isDragOver ? Theme.accent : Color.clear,
                            style: StrokeStyle(lineWidth: 2, dash: [6])
                        )
                )
                .onDrop(of: [.fileURL, .plainText], isTargeted: $isDragOver) { providers in
                    handleDrop(providers: providers)
                }
                .overlay {
                    if isDragOver {
                        Text("释放以导入")
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                    }
                }

                // Profiles list (inactive)
                if !vm.profiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("所有配置")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                        ForEach(vm.profiles) { profile in
                            ProfileRow(
                                profile: profile,
                                isActive: profile.id == vm.activeProfile?.id,
                                onActivate: {
                                    vm.activateProfile(profile)
                                },
                                onDelete: {
                                    vm.removeProfile(profile)
                                }
                            )
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                }

                // Subscriptions — wired to backend
                subscriptionSection

                // Rule Sets
                if !vm.ruleSetDisplays.isEmpty {
                    ruleSetSection
                }

                // Backups
                backupSection

                // Error display
                if let error = vm.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Theme.danger.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                }
            }
            .padding()
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .sheet(isPresented: $showHelperSetup) {
            HelperSetupView()
        }
        .sheet(isPresented: $showAddSubscription) {
            AddSubscriptionSheet(vm: vm)
        }
        .sheet(item: $editingSubscription) { sub in
            AddSubscriptionSheet(vm: vm, editing: sub)
        }
        .sheet(isPresented: $showImportPreview) {
            ConfigImportPreviewView(
                yaml: importPreviewYAML,
                fileName: importPreviewFileName,
                onImport: { _ in
                    if let url = importPreviewURL {
                        Task { await vm.importConfig(from: url) }
                    }
                    showImportPreview = false
                },
                onCancel: { showImportPreview = false }
            )
        }
        .sheet(isPresented: $showYAMLEditor) {
            if let id = yamlEditorProfileID {
                YAMLEditorView(vm: vm, profileID: id)
            }
        }
        .onChange(of: vm.showHelperSetup) { _, newValue in
            showHelperSetup = newValue
        }
        .onChange(of: showHelperSetup) { _, newValue in
            if !newValue {
                vm.showHelperSetup = false
                // Recheck helper status when sheet closes
                vm.checkHelperInstallation()
            }
        }
        .alert("导入失败", isPresented: $showImportError, presenting: importErrorMessage) { _ in
            Button("确定") { importErrorMessage = nil }
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("订阅列表")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    showAddSubscription = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier(A11yID.Config.addSubscription)
            }

            if vm.subscriptions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cloud")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.subtext)
                    Text("暂无订阅")
                        .foregroundStyle(Theme.subtext)
                    Text("添加远程订阅以自动获取代理节点")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
            } else {
                ForEach(vm.subscriptions) { sub in
                    SubscriptionRow(
                        sub: sub,
                        onUpdate: {
                            Task { await vm.updateSubscription(id: sub.id) }
                        },
                        onEdit: {
                            editingSubscription = sub
                        },
                        onDelete: {
                            Task { await vm.removeSubscription(id: sub.id) }
                        }
                    )
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Rule Set Section

    private var ruleSetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("规则集")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("共 \(vm.ruleSetDisplays.count) 个")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }

            ForEach(vm.ruleSetDisplays) { display in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.name)
                            .font(.body)
                            .foregroundStyle(Theme.text)
                        HStack(spacing: 8) {
                            Text("\(display.ruleCount) 条规则")
                                .font(.caption)
                                .foregroundStyle(Theme.subtext)
                            if display.interval > 0 {
                                Text("每 \(display.interval)s 更新")
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtext)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        Task { await vm.refreshRuleSetProvider(name: display.id) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Backup Section

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("配置备份")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    Task { await vm.createManualBackup() }
                } label: {
                    Label("创建备份", systemImage: "archivebox")
                }
                .buttonStyle(.bordered)
            }

            if vm.backupDisplays.isEmpty {
                Text("暂无备份")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(vm.backupDisplays) { backup in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backup.name)
                                .font(.body)
                                .foregroundStyle(Theme.text)
                            Text("\(backup.fileSizeFormatted) · \(backup.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(Theme.subtext)
                        }

                        Spacer()

                        Button {
                            Task { await vm.restoreBackup(backup) }
                        } label: {
                            Text("恢复")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await vm.deleteBackup(backup) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.danger)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .task { await vm.loadBackups() }
    }

    // MARK: - Mode Selector Card

    private var modeSelectorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "network")
                    .foregroundStyle(Theme.accent)
                Text("运行模式")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()

                // Helper status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(vm.helperInstalled ? Theme.success : Theme.danger)
                        .frame(width: 8, height: 8)
                    Text(vm.helperInstalled ? "Helper已安装" : "Helper未安装")
                        .font(.caption)
                        .foregroundStyle(vm.helperInstalled ? Theme.success : Theme.danger)
                }
            }

            // Mode selector
            Picker("模式", selection: $vm.connectionMode) {
                ForEach(ConnectionMode.productAvailableModes, id: \.self) { mode in
                    Text(mode.displayName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(vm.isRunning)

            // Start / Stop button
            HStack(spacing: 12) {
                Button {
                    Task { await vm.toggleTunnel() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: vm.isRunning ? "stop.fill" : "play.fill")
                        Text(vm.isRunning ? "停止代理" : "启动代理")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(vm.isRunning ? Theme.danger : Theme.accent)
                .keyboardShortcut(.return, modifiers: [])

                // Helper setup (only when TUN selected and helper not installed)
                if vm.connectionMode == .tun && !vm.helperInstalled {
                    Button {
                        showHelperSetup = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                            Text("安装Helper")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.warning)
                }
            }

            // TUN mode sudo info
            if vm.connectionMode == .tun && !vm.helperInstalled {
                Text("Helper 未安装时将使用 sudo 提权启动，macOS 会弹出密码框。")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Warning when running and mode is disabled
            if vm.isRunning {
                Text("运行中无法切换模式，请先停止代理")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "yaml")!, UTType(filenameExtension: "yml")!]
        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url),
               let yaml = String(data: data, encoding: .utf8) {
                importPreviewURL = url
                importPreviewYAML = yaml
                importPreviewFileName = url.deletingPathExtension().lastPathComponent
                showImportPreview = true
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    if routeImportURL(url) == nil {
                        // Fall back to reading the file contents as text
                        if let text = try? String(contentsOf: url, encoding: .utf8) {
                            routeImportText(text)
                        } else {
                            importErrorMessage = "无法读取文件内容"
                            showImportError = true
                        }
                    }
                }
            }
            return true
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let text: String?
                if let data = item as? Data {
                    text = String(data: data, encoding: .utf8)
                } else if let str = item as? String {
                    text = str
                } else {
                    text = nil
                }
                guard let text else {
                    DispatchQueue.main.async {
                        importErrorMessage = "无法读取拖入的文本"
                        showImportError = true
                    }
                    return
                }
                DispatchQueue.main.async {
                    routeImportText(text)
                }
            }
            return true
        }
        return false
    }

    private func importFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            importErrorMessage = "剪贴板为空"
            showImportError = true
            return
        }
        routeImportText(text)
    }

    @discardableResult
    private func routeImportURL(_ url: URL) -> Bool? {
        let ext = url.pathExtension.lowercased()
        if ext == "yaml" || ext == "yml" {
            Task { await vm.importConfig(from: url) }
            return true
        }
        return nil
    }

    private func routeImportText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            // Subscription URL — full URL flow is a follow-up
            importErrorMessage = "检测到订阅 URL，请使用「添加订阅」功能导入"
            showImportError = true
            return
        }
        let uriPrefixes = ["ss://", "vmess://", "vless://", "trojan://", "hysteria2://", "hy2://", "tuic://"]
        for prefix in uriPrefixes where trimmed.hasPrefix(prefix) {
            importErrorMessage = "Share URI 解析暂未实现，请使用 YAML 格式"
            showImportError = true
            return
        }
        // Try as YAML
        do {
            _ = try ClashConfigParser.parse(yaml: trimmed)
            // Create a temp file and import
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).yaml")
            try trimmed.write(to: tmp, atomically: true, encoding: .utf8)
            Task { await vm.importConfig(from: tmp) }
        } catch {
            importErrorMessage = "无法解析内容: \(error.localizedDescription)"
            showImportError = true
        }
    }
}

struct ProfileRow: View {
    let profile: Profile
    let isActive: Bool
    let onActivate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text(profile.name)
                .foregroundStyle(Theme.text)
            if isActive {
                Text("激活")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.success.opacity(0.2))
                    .foregroundStyle(Theme.success)
                    .clipShape(Capsule())
            }
            Spacer()
            Text("节点: \(profile.config.proxies.count)  规则: \(profile.config.rules.count)")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
            if !isActive {
                Button("激活") { onActivate() }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
            }
            Button("删除") { onDelete() }
                .buttonStyle(.bordered)
                .tint(Theme.danger)
        }
    }
}

struct ProfileCard: View {
    let profile: Profile
    let isActive: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(profile.name)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                if isActive {
                    Text("激活")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.success.opacity(0.2))
                        .foregroundStyle(Theme.success)
                        .clipShape(Capsule())
                }
                Spacer()
                Button {
                    onEdit()
                } label: {
                    Label("编辑 YAML", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(A11yID.Config.editYAMLButton)
                Button("删除", action: onDelete)
                    .buttonStyle(.bordered)
                    .tint(Theme.danger)
            }
            Text("节点: \(profile.config.proxies.count)  规则: \(profile.config.rules.count)")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(isActive ? Theme.success : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Subscription Row

struct SubscriptionRow: View {
    let sub: SubscriptionDisplay
    let onUpdate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isUpdating = false

    private var lastUpdatedText: String {
        guard let date = sub.lastUpdated else { return "从未更新" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "cloud.fill")
                    .foregroundStyle(Theme.accent)
                Text(sub.name)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                if sub.autoUpdate {
                    Label("自动", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(Theme.success)
                }
            }

            Text(sub.url)
                .font(.caption)
                .foregroundStyle(Theme.subtext)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack {
                Text(lastUpdatedText)
                    .font(.caption2)
                    .foregroundStyle(Theme.subtext)
                if let error = sub.lastError {
                    Text("错误: \(error)")
                        .font(.caption2)
                        .foregroundStyle(Theme.danger)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if sub.profileCount > 0 {
                    Text("\(sub.profileCount) 个配置")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtext)
                }
                Spacer()

                Button {
                    withAnimation { isUpdating = true }
                    Task {
                        defer { Task { @MainActor in withAnimation { isUpdating = false } } }
                        await onUpdate()
                    }
                } label: {
                    Label(isUpdating ? "更新中…" : "更新", systemImage: isUpdating ? "arrow.clockwise" : "arrow.clockwise.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isUpdating)

                Button("编辑") { onEdit() }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)

                Button("删除") { onDelete() }
                    .buttonStyle(.bordered)
                    .tint(Theme.danger)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}
