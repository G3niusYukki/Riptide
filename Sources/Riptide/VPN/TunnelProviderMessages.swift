import Foundation

/// Commands sent from the host app to the packet tunnel extension via NETunnelProviderSession.
public enum TunnelProviderCommand: Sendable, Codable, Equatable {
    /// Start the tunnel with serialized configuration data.
    case start(Data)
    /// Stop the tunnel.
    case stop
    /// Request a status snapshot from the extension.
    case snapshot
}

/// A snapshot of the tunnel provider's state, serializable for IPC between the
/// host app and the NetworkExtension.
public struct TunnelProviderSnapshot: Sendable, Codable, Equatable {
    public let status: TunnelRuntimeStatus
    public let mode: RuntimeMode
    public let recentErrors: [RuntimeErrorSnapshot]
    public let isRunning: Bool

    public init(
        status: TunnelRuntimeStatus,
        mode: RuntimeMode,
        recentErrors: [RuntimeErrorSnapshot],
        isRunning: Bool
    ) {
        self.status = status
        self.mode = mode
        self.recentErrors = recentErrors
        self.isRunning = isRunning
    }

    public static func from(
        status: TunnelRuntimeStatus,
        mode: RuntimeMode,
        errors: [RuntimeErrorSnapshot],
        running: Bool
    ) -> TunnelProviderSnapshot {
        TunnelProviderSnapshot(
            status: status,
            mode: mode,
            recentErrors: errors,
            isRunning: running
        )
    }
}
