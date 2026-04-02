import Foundation

public struct RuntimeStatsViewState: Equatable, Sendable {
    public let isRunning: Bool
    public let profileName: String?
    public let bytesUp: UInt64
    public let bytesDown: UInt64
    public let activeConnections: Int
    public let lastError: String?

    public init(
        isRunning: Bool,
        profileName: String?,
        bytesUp: UInt64,
        bytesDown: UInt64,
        activeConnections: Int,
        lastError: String?
    ) {
        self.isRunning = isRunning
        self.profileName = profileName
        self.bytesUp = bytesUp
        self.bytesDown = bytesDown
        self.activeConnections = activeConnections
        self.lastError = lastError
    }
}

public struct RuntimeStatsPipeline: Sendable {
    public init() {}

    public func map(snapshot: TunnelStatusSnapshot) -> RuntimeStatsViewState {
        RuntimeStatsViewState(
            isRunning: snapshot.state == .running,
            profileName: snapshot.activeProfileName,
            bytesUp: snapshot.bytesUp,
            bytesDown: snapshot.bytesDown,
            activeConnections: snapshot.activeConnections,
            lastError: snapshot.lastError
        )
    }
}
