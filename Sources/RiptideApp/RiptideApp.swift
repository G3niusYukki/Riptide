import SwiftUI

@main
struct RiptideApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("Riptide") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Riptide")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(viewModel.statusText)
                    .font(.system(.body, design: .monospaced))

                HStack(spacing: 8) {
                    Button("Load Demo Config & Start") {
                        Task { await viewModel.startDemo() }
                    }
                    .disabled(viewModel.isRunning)

                    Button("Stop") {
                        Task { await viewModel.stop() }
                    }
                    .disabled(!viewModel.isRunning)
                }

                if let error = viewModel.lastError {
                    Text("error: \(error)")
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
            .frame(minWidth: 480, minHeight: 180)
            .task {
                await viewModel.refreshStatus()
            }
        }
    }
}
