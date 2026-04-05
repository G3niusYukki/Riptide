import SwiftUI
import Riptide

/// A menu bar extra providing quick access to Riptide controls.
@available(macOS 14.0, *)
public struct RiptideMenuBar: View {
    @ObservedObject private var viewModel: MenuBarViewModel

    public init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Menu {
            // Status header
            Section {
                HStack {
                    Image(systemName: viewModel.isRunning ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(viewModel.isRunning ? .green : .red)
                    Text(viewModel.statusLabel)
                        .fontWeight(.medium)
                    Spacer()
                    if viewModel.isRunning {
                        VStack(alignment: .trailing) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .font(.caption2)
                                Text(viewModel.uploadSpeed)
                                    .font(.caption2)
                                    .monospacedDigit()
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.caption2)
                                Text(viewModel.downloadSpeed)
                                    .font(.caption2)
                                    .monospacedDigit()
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // Start/Stop
            Button {
                Task { await viewModel.toggleConnection() }
            } label: {
                Label(viewModel.isRunning ? "停止" : "启动", systemImage: viewModel.isRunning ? "stop.circle" : "play.circle")
            }

            // Quick profile switch
            if !viewModel.profiles.isEmpty {
                Divider()
                Section("配置") {
                    ForEach(viewModel.profiles, id: \.id) { profile in
                        Button {
                            Task { await viewModel.switchProfile(profile) }
                        } label: {
                            HStack {
                                if profile.isActive {
                                    Image(systemName: "checkmark")
                                } else {
                                    Image(systemName: "circle")
                                        .hidden()
                                }
                                Text(profile.name)
                            }
                        }
                    }
                }
            }

            Divider()

            // Mode switch
            Section("模式") {
                Picker("模式", selection: $viewModel.selectedMode) {
                    Text("系统代理").tag(RuntimeMode.systemProxy)
                    Text("TUN").tag(RuntimeMode.tun)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .disabled(viewModel.isRunning)
                .onChange(of: viewModel.selectedMode) {
                    viewModel.requestModeChange(viewModel.selectedMode)
                }
            }

            Divider()

            Button("打开面板") {
                viewModel.openDashboard()
            }

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: viewModel.isRunning ? "shield.checkmark.fill" : "shield.slash")
                .symbolRenderingMode(.hierarchical)
        }
        .onAppear {
            viewModel.startStatusPolling()
        }
    }
}

/// View model driving the menu bar's state.
@available(macOS 14.0, *)
@MainActor
public final class MenuBarViewModel: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var selectedMode: RuntimeMode = .systemProxy
    @Published var statusLabel: String = "未连接"
    @Published var uploadSpeed: String = "0 B/s"
    @Published var downloadSpeed: String = "0 B/s"
    @Published var profiles: [(id: UUID, name: String, isActive: Bool)] = []

    private let appViewModel: AppViewModel
    private var statusTimer: Task<Void, Never>?

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
        self.isRunning = appViewModel.isRunning
        updateStatusLabel()
    }

    deinit {
        statusTimer?.cancel()
    }

    /// Starts periodic status polling to keep menu bar in sync.
    public func startStatusPolling() {
        statusTimer?.cancel()
        statusTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    syncFromApp()
                }
            }
        }
    }

    /// Request a mode switch.
    public func requestModeChange(_ mode: RuntimeMode) {
        // Mode change requires stopping first — warn user
        if isRunning {
            statusLabel = "请先停止服务再切换模式"
            return
        }
        selectedMode = mode
    }

    public func toggleConnection() async {
        if isRunning {
            await appViewModel.stop()
        } else {
            await appViewModel.startDemo()
        }
        isRunning = appViewModel.isRunning
        updateStatusLabel()
    }

    /// Switches to a specific profile.
    public func switchProfile(_ profile: (id: UUID, name: String, isActive: Bool)) async {
        // Activate profile in AppViewModel
        // This is a simplified implementation — full version would wire through profile store
        updateProfiles()
    }

    public func openDashboard() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Refresh state from the app view model to stay in sync.
    public func syncFromApp() {
        isRunning = appViewModel.isRunning
        uploadSpeed = formatSpeed(appViewModel.currentSpeedUp)
        downloadSpeed = formatSpeed(appViewModel.currentSpeedDown)
        updateStatusLabel()
        updateProfiles()
    }

    private func updateStatusLabel() {
        statusLabel = isRunning ? "已连接" : "未连接"
    }

    private func updateProfiles() {
        profiles = appViewModel.profiles.map { p in
            (id: p.id, name: p.name, isActive: p.id == appViewModel.activeProfile?.id)
        }
    }

    private func formatSpeed(_ bytesPerSec: Int64) -> String {
        if bytesPerSec < 1024 { return "\(bytesPerSec) B/s" }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", Double(bytesPerSec) / 1024) }
        return String(format: "%.1f MB/s", Double(bytesPerSec) / 1024 / 1024)
    }
}
