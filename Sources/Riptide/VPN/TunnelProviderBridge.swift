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
    private var mode: RuntimeMode
    private var recentErrors: [RuntimeErrorSnapshot]
    private var runtimeStatus: TunnelRuntimeStatus
    private let maxErrors = 20

    public init() {
        self.mode = .tun
        self.recentErrors = []
        self.runtimeStatus = TunnelRuntimeStatus()
    }

    /// Handle a command from the tunnel extension.
    public func handle(command: TunnelProviderCommand) async throws -> TunnelProviderSnapshot {
        switch command {
        case .start:
            mode = .tun
            return makeSnapshot()

        case .stop:
            return makeSnapshot()

        case .snapshot:
            return makeSnapshot()
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
        makeSnapshot()
    }

    private func makeSnapshot() -> TunnelProviderSnapshot {
        TunnelProviderSnapshot(
            status: runtimeStatus,
            mode: mode,
            recentErrors: recentErrors,
            isRunning: true
        )
    }
}
