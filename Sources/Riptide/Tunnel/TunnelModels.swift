import Foundation

public enum TunnelLifecycleState: Equatable, Sendable, Codable {
    case stopped
    case starting
    case running
    case stopping
    case error
}

public struct TunnelProfile: Equatable, Sendable {
    public let name: String
    public let config: RiptideConfig

    public init(name: String, config: RiptideConfig) {
        self.name = name
        self.config = config
    }

    /// Proxy provider configurations sourced from the profile's config file.
    public var proxyProviders: [String: ProxyProviderConfig] {
        config.proxyProviders
    }
}

public struct TunnelRuntimeStatus: Equatable, Sendable, Codable {
    public let bytesUp: UInt64
    public let bytesDown: UInt64
    public let activeConnections: Int

    public init(bytesUp: UInt64 = 0, bytesDown: UInt64 = 0, activeConnections: Int = 0) {
        self.bytesUp = bytesUp
        self.bytesDown = bytesDown
        self.activeConnections = activeConnections
    }
}

public struct TunnelStatusSnapshot: Equatable, Sendable {
    public let state: TunnelLifecycleState
    public let activeProfileName: String?
    public let bytesUp: UInt64
    public let bytesDown: UInt64
    public let activeConnections: Int
    public let lastError: String?

    public init(
        state: TunnelLifecycleState,
        activeProfileName: String?,
        bytesUp: UInt64,
        bytesDown: UInt64,
        activeConnections: Int,
        lastError: String?
    ) {
        self.state = state
        self.activeProfileName = activeProfileName
        self.bytesUp = bytesUp
        self.bytesDown = bytesDown
        self.activeConnections = activeConnections
        self.lastError = lastError
    }
}
