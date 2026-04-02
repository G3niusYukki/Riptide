import Foundation
import Observation
import Riptide

enum AppControlError: Error {
    case commandFailed(operation: String, message: String)
    case invalidResponse(String)
}

@MainActor
@Observable
final class AppViewModel {
    private let importService = ConfigImportService()
    private let controlChannel: InProcessTunnelControlChannel
    private let statsPipeline = RuntimeStatsPipeline()

    private(set) var statusText: String = "state=stopped"
    private(set) var isRunning: Bool = false
    private(set) var lastError: String?

    init() {
        let runtime = AppMockTunnelRuntime()
        let manager = TunnelLifecycleManager(runtime: runtime)
        self.controlChannel = InProcessTunnelControlChannel(lifecycleManager: manager)
    }

    func startDemo() async {
        do {
            let imported = try importService.importProfile(name: "demo", yaml: DemoConfigFactory.makeYAML())
            let response = try await controlChannel.send(.start(imported.profile))
            try expectAck(response, operation: "start")
            await refreshStatus()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    func stop() async {
        do {
            let response = try await controlChannel.send(.stop)
            try expectAck(response, operation: "stop")
            await refreshStatus()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    func refreshStatus() async {
        do {
            let response = try await controlChannel.send(.status)
            switch response {
            case .status(let snapshot):
                let viewState = statsPipeline.map(snapshot: snapshot)
                isRunning = viewState.isRunning
                statusText = "state=\(snapshot.state) profile=\(viewState.profileName ?? "none") up=\(viewState.bytesUp) down=\(viewState.bytesDown) conn=\(viewState.activeConnections)"
                lastError = snapshot.lastError
            case .error(let message):
                throw AppControlError.commandFailed(operation: "status", message: message)
            case .ack:
                throw AppControlError.invalidResponse("unexpected ack response on status")
            }
        } catch {
            isRunning = false
            statusText = "state=error"
            lastError = String(describing: error)
        }
    }

    private func expectAck(_ response: TunnelControlResponse, operation: String) throws {
        switch response {
        case .ack:
            return
        case .error(let message):
            throw AppControlError.commandFailed(operation: operation, message: message)
        case .status(let snapshot):
            throw AppControlError.invalidResponse(
                "unexpected status response on \(operation): \(snapshot.state)"
            )
        }
    }
}
