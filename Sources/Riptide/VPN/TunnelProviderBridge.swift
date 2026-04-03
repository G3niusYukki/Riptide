import Foundation

/// Errors from tunnel provider bridge operations.
public enum TunnelProviderBridgeError: Error, Equatable, Sendable {
    case notRunning
    case configParseFailed
    case commandFailed(String)
}

/// A bridge actor that routes commands between the host app and the tunnel extension,
/// and produces structured snapshots for IPC.
public actor TunnelProviderBridge {
    private let vpnManager: VPNTunnelManager?
    private var mode: RuntimeMode
    private var recentErrors: [RuntimeErrorSnapshot]
    private var runtimeStatus: TunnelRuntimeStatus
    private let maxErrors = 20

    public init(vpnManager: VPNTunnelManager? = nil) {
        self.vpnManager = vpnManager
        self.mode = .tun
        self.recentErrors = []
        self.runtimeStatus = TunnelRuntimeStatus()
    }

    /// Handle a command from the tunnel extension.
    public func handle(command: TunnelProviderCommand) async throws -> TunnelProviderSnapshot {
        switch command {
        case .start(let configData):
            try await start(with: configData)
            return makeSnapshot(running: true)

        case .stop:
            vpnManager?.stop(reason: "extension command")
            return makeSnapshot(running: false)

        case .snapshot:
            return makeSnapshot(running: vpnManager?.isRunning ?? false)
        }
    }

    /// Update the current runtime status (called from the host runtime).
    public func updateStatus(_ status: TunnelRuntimeStatus) {
        runtimeStatus = status
    }

    /// Record an error from the tunnel extension.
    public func recordError(_ error: RuntimeErrorSnapshot) {
        recentErrors.append(error)
        if recentErrors.count > maxErrors {
            recentErrors.removeFirst()
        }
    }

    /// Return the current tunnel provider snapshot.
    public func snapshot() -> TunnelProviderSnapshot {
        makeSnapshot(running: vpnManager?.isRunning ?? false)
    }

    private func start(with configData: Data) async throws {
        guard vpnManager != nil else {
            throw TunnelProviderBridgeError.notRunning
        }
        // Parsing the config data would happen here in a full implementation.
        // For the bridge abstraction, we just record the intent.
        mode = .tun
    }

    private func makeSnapshot(running: Bool) -> TunnelProviderSnapshot {
        TunnelProviderSnapshot(
            status: runtimeStatus,
            mode: mode,
            recentErrors: recentErrors,
            isRunning: running
        )
    }
}
