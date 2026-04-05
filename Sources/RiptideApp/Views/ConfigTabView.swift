import SwiftUI
import UniformTypeIdentifiers

struct ConfigTabView: View {
    @Bindable var vm: AppViewModel
    @State private var showHelperSetup = false
    @State private var showAddSubscription = false
    @State private var editingSubscription: SubscriptionDisplay?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Mode selector card
                modeSelectorCard

                // Active profile card
                if let profile = vm.activeProfile {
                    ProfileCard(profile: profile, isActive: true) {
                        // Edit action
                    } onDelete: {
                        vm.removeProfile(profile)
                    }
                }

                // Import button
                Button {
                    importConfig()
                } label: {
                    Label("导入配置文件", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

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
                Text("系统代理")
                    .tag(ConnectionMode.systemProxy)
                Text("TUN模式")
                    .tag(ConnectionMode.tun)
            }
            .pickerStyle(.segmented)
            .disabled(vm.isRunning)

            // Helper installation button (shown when TUN selected but helper not installed)
            if vm.connectionMode == .tun && !vm.helperInstalled {
                Button {
                    showHelperSetup = true
                } label: {
                    HStack {
                        Image(systemName: "lock.shield")
                        Text("安装Helper工具")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.danger)
                .padding(.top, 4)

                Text("TUN模式需要安装Helper工具才能配置网络接口")
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
            Task { await vm.importConfig(from: url) }
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
                Button("编辑", action: onEdit)
                    .buttonStyle(.bordered)
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
