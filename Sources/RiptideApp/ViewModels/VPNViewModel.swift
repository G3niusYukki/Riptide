import SwiftUI
import Riptide

@MainActor
@Observable
final class VPNViewModel {
    var isRunning = false
    var statusText = "Disconnected"
    var bytesUp: UInt64 = 0
    var bytesDown: UInt64 = 0
    var activeConnections = 0
    var errorMessage: String?

    private var runtime: LiveTunnelRuntime?
    private var statsTask: Task<Void, Never>?

    func start() async {
        do {
            let proxyDialer = TCPTransportDialer()
            let directDialer = TCPTransportDialer()
            let runtime = LiveTunnelRuntime(proxyDialer: proxyDialer, directDialer: directDialer)

            let config = RiptideConfig(mode: .rule, proxies: [], rules: [.final(policy: .direct)])
            let profile = TunnelProfile(name: "default", config: config)

            try await runtime.start(profile: profile)
            self.runtime = runtime
            isRunning = true
            statusText = "Connected"

            statsTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, let runtime = self.runtime else { break }
                    let status = await runtime.status()
                    self.bytesUp = status.bytesUp
                    self.bytesDown = status.bytesDown
                    self.activeConnections = status.activeConnections
                }
            }
        } catch {
            errorMessage = String(describing: error)
            statusText = "Error"
        }
    }

    func stop() async {
        statsTask?.cancel()
        statsTask = nil
        try? await runtime?.stop()
        runtime = nil
        isRunning = false
        statusText = "Disconnected"
        bytesUp = 0
        bytesDown = 0
        activeConnections = 0
        errorMessage = nil
    }
}
