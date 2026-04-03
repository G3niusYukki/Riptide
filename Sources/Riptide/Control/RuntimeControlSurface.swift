import Foundation

/// The operating mode of the Riptide runtime.
public enum RuntimeMode: String, Sendable, Codable, Equatable {
    case systemProxy
    case tun
}

/// A snapshot of a single active connection passing through the runtime.
public struct RuntimeConnectionSnapshot: Sendable, Equatable, Codable {
    public let id: UUID
    public let targetHost: String
    public let targetPort: Int
    public let routeDescription: String

    public init(id: UUID, targetHost: String, targetPort: Int, routeDescription: String) {
        self.id = id
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.routeDescription = routeDescription
    }
}

/// A structured snapshot of a runtime error suitable for diagnostics.
public struct RuntimeErrorSnapshot: Sendable, Equatable, Codable {
    public let code: String
    public let message: String
    public let timestamp: Date

    public init(code: String, message: String, timestamp: Date = Date()) {
        self.code = code
        self.message = message
        self.timestamp = timestamp
    }
}

/// Unified runtime event type emitted across all control surfaces.
public enum RuntimeEvent: Sendable, Equatable, Codable {
    case stateChanged(TunnelLifecycleState)
    case modeChanged(RuntimeMode)
    case degraded(RuntimeMode, String)
    case connectionOpened(RuntimeConnectionSnapshot)
    case connectionClosed(UUID)
    case error(RuntimeErrorSnapshot)
}

/// A lightweight surface carrying runtime mode and configuration context.
/// Used by the app shell to expose mode-aware diagnostics.
public struct RuntimeControlSurface: Sendable, Equatable {
    public let mode: RuntimeMode

    public init(mode: RuntimeMode) {
        self.mode = mode
    }
}
