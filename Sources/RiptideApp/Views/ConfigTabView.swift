import SwiftUI
import UniformTypeIdentifiers

struct ConfigTabView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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

                // Subscriptions
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("订阅列表")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Button {
                            // Add subscription — stub
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                    if vm.subscriptions.isEmpty {
                        Text("暂无订阅")
                            .foregroundStyle(Theme.subtext)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(vm.subscriptions) { sub in
                            HStack {
                                Text(sub.name)
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Text(sub.url)
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtext)
                            }
                            Divider()
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))

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
