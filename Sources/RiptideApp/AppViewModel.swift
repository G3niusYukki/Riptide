import Foundation
import Observation
import Riptide

@MainActor
@Observable
final class AppViewModel {
    private let control: TunnelControlViewModel
    private let statsPipeline = RuntimeStatsPipeline()

    private(set) var statusText: String = "state=stopped"
    private(set) var isRunning: Bool = false
    private(set) var lastError: String?

    init() {
        let runtime = AppMockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        self.control = TunnelControlViewModel(lifecycleManager: manager)
    }

    func startDemo() async {
        do {
            let imported = try await control.importConfig(name: "demo", yaml: DemoConfigFactory.makeYAML())
            try await control.applyImportedProfileAndStart(imported)
            await refreshStatus()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    func stop() async {
        do {
            try await control.stop()
            await refreshStatus()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    func refreshStatus() async {
        let snapshot = await control.currentStatus()
        let viewState = statsPipeline.map(snapshot: snapshot)
        isRunning = viewState.isRunning
        statusText = "state=\(snapshot.state) profile=\(viewState.profileName ?? "none") up=\(viewState.bytesUp) down=\(viewState.bytesDown) conn=\(viewState.activeConnections)"
    }
}
