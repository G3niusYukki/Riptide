import SwiftUI
import Sparkle

// MARK: - Update Settings View

/// Shows current version, update channel, and manual update check.
struct UpdateSettingsView: View {
    @State private var automaticallyChecksForUpdates: Bool
    @State private var updateChannel: UpdateChannel = .stable
    @State private var isChecking = false

    enum UpdateChannel: String, CaseIterable {
        case stable = "稳定版"
        case beta = "测试版"
    }

    private let updater: SPUStandardUpdaterController

    init() {
        let controller = AppCoordinator.shared.updaterController
        self.updater = controller
        _automaticallyChecksForUpdates = State(
            initialValue: controller.updater.automaticallyChecksForUpdates
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("软件更新", systemImage: "arrow.down.circle.dotted")
                .font(.headline)
                .foregroundStyle(Theme.text)

            // Version info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前版本")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                    Text(currentVersion)
                        .font(.callout)
                        .foregroundStyle(Theme.text)
                }
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))

            // Auto-check toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动检查更新")
                        .foregroundStyle(Theme.text)
                    Text("启动时自动检查新版本")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
                Spacer()
                Toggle("", isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                        updater.updater.automaticallyChecksForUpdates = newValue
                    }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))

            // Update channel
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("更新通道")
                        .foregroundStyle(Theme.text)
                    Text("稳定版：经过测试的正式发布版本")
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
                Spacer()
                Picker("", selection: $updateChannel) {
                    ForEach(UpdateChannel.allCases, id: \.self) { channel in
                        Text(channel.rawValue).tag(channel)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))

            // Manual check
            Button {
                isChecking = true
                updater.checkForUpdates(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    isChecking = false
                }
            } label: {
                Label(isChecking ? "正在检查…" : "检查更新", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isChecking)

            // Build info
            Text("构建信息: \(buildInfo)")
                .font(.caption2)
                .foregroundStyle(Theme.subtext)
        }
        .padding()
    }

    private var currentVersion: String {
        if let info = Bundle.main.infoDictionary,
           let version = info["CFBundleShortVersionString"] as? String {
            return "v\(version)"
        }
        // Fallback: read from .version file at repo root
        return "v2.0.0"
    }

    private var buildInfo: String {
        if let info = Bundle.main.infoDictionary,
           let build = info["CFBundleVersion"] as? String {
            return "Build \(build) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        }
        return "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}
