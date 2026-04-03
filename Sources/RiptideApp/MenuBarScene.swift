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
            Section {
                Label(viewModel.statusLabel, systemImage: viewModel.isRunning ? "checkmark.circle.fill" : "xmark.circle")
            }

            Divider()

            Button {
                Task { await viewModel.toggleConnection() }
            } label: {
                Label(viewModel.isRunning ? "Stop" : "Start", systemImage: viewModel.isRunning ? "stop.circle" : "play.circle")
            }

            Divider()

            Section("Mode") {
                Picker("Mode", selection: $viewModel.selectedMode) {
                    Text("System Proxy").tag(RuntimeMode.systemProxy)
                    Text("TUN").tag(RuntimeMode.tun)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Divider()

            Button("Open Dashboard") {
                viewModel.openDashboard()
            }

            Button("Quit Riptide") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: viewModel.isRunning ? "shield.checkmark.fill" : "shield.slash")
                .symbolRenderingMode(.hierarchical)
        }
    }
}

/// View model driving the menu bar's state.
@available(macOS 14.0, *)
@MainActor
public final class MenuBarViewModel: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var selectedMode: RuntimeMode = .systemProxy
    @Published var statusLabel: String = "Disconnected"

    private let appViewModel: AppViewModel

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
        self.isRunning = appViewModel.isRunning
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

    public func openDashboard() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    public func update() {
        isRunning = appViewModel.isRunning
        updateStatusLabel()
    }

    private func updateStatusLabel() {
        statusLabel = isRunning ? "Connected" : "Disconnected"
    }
}
