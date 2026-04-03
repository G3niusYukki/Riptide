import Foundation

// ============================================================
// MARK: - UDP Session ID
// ============================================================

/// Uniquely identifies a UDP session by its 4-tuple.
public struct UDPSessionID: Hashable, Sendable {
    public let srcIP: String
    public let srcPort: UInt16
    public let dstIP: String
    public let dstPort: UInt16

    public init(srcIP: String, srcPort: UInt16, dstIP: String, dstPort: UInt16) {
        self.srcIP = srcIP
        self.srcPort = srcPort
        self.dstIP = dstIP
        self.dstPort = dstPort
    }
}

// ============================================================
// MARK: - UDP Session
// ============================================================

/// Errors from UDP session management.
public enum UDPSessionError: Error, Equatable, Sendable {
    case sessionNotFound(UDPSessionID)
    case sessionLimitReached
    case sessionTimeout
    case proxyConnectionFailed(String)
    case invalidSessionState
}

/// A single UDP session — handles bidirectional UDP traffic through a proxy.
public actor UDPSession {
    public let id: UDPSessionID
    private var remoteContext: ConnectedProxyContext?
    private var isActive: Bool
    private var pendingPackets: [Data]
    private var lastActivity: ContinuousClock.Instant

    public init(id: UDPSessionID, remoteContext: ConnectedProxyContext? = nil) {
        self.id = id
        self.remoteContext = remoteContext
        self.isActive = remoteContext != nil
        self.pendingPackets = []
        self.lastActivity = ContinuousClock.now
    }

    public func process(data: Data) async throws -> [Data] {
        guard isActive else {
            throw UDPSessionError.invalidSessionState
        }

        updateActivity()
        pendingPackets.append(data)

        // In a full implementation, we'd forward the data through the proxy connection
        // and return the response. For now, this is a placeholder.
        return []
    }

    /// Forward data through the proxy connection.
    public func forward(data: Data, session: any TransportSession) async throws -> Data {
        try await session.send(data)
        let response = try await session.receive()
        updateActivity()
        return response
    }

    /// Close the session.
    public func close() {
        isActive = false
        pendingPackets.removeAll()
    }

    /// Check if the session is still active.
    public var isSessionActive: Bool {
        isActive
    }

    /// Get the time since last activity.
    public func timeSinceActivity() -> Duration {
        ContinuousClock.now - lastActivity
    }

    private func updateActivity() {
        lastActivity = ContinuousClock.now
    }
}

// ============================================================
// MARK: - UDP Session Manager
// ============================================================

/// Errors from the UDP session manager.
public enum UDPSessionManagerError: Error, Equatable, Sendable {
    case sessionLimitReached
    case sessionNotFound(UDPSessionID)
    case sessionTimeout
    case proxyError(String)
}

/// An actor that manages UDP sessions for the TUN routing engine.
/// Each UDP flow (identified by srcIP:srcPort -> dstIP:dstPort) gets its own session.
public actor UDPSessionManager {
    private var sessions: [UDPSessionID: UDPSession] = [:]
    private var cleanupTasks: [UDPSessionID: Task<Void, Never>] = [:]
    private let maxSessions: Int
    private let sessionTimeout: Duration

    public init(maxSessions: Int = 1000, sessionTimeout: Duration = .seconds(60)) {
        self.maxSessions = maxSessions
        self.sessionTimeout = sessionTimeout
    }

    /// Handle an inbound UDP packet.
    /// Creates a new session if needed, or processes through an existing one.
    public func handlePacket(
        sessionID: UDPSessionID,
        data: Data,
        proxyConnector: ProxyConnector
    ) async throws -> [Data] {
        if let existing = sessions[sessionID] {
            let result = try await existing.process(data: data)
            // Reset the timeout for this session
            resetSessionTimeout(sessionID: sessionID)
            return result
        }

        // Create new UDP session
        guard sessions.count < maxSessions else {
            throw UDPSessionManagerError.sessionLimitReached
        }

        let session = UDPSession(id: sessionID)
        sessions[sessionID] = session

        // Start cleanup task for this session
        let task = Task {
            try? await Task.sleep(for: sessionTimeout)
            await cleanupSession(id: sessionID)
        }
        cleanupTasks[sessionID] = task

        return try await session.process(data: data)
    }

    /// Handle a UDP packet and route it through the proxy.
    /// This method establishes a proxy connection for the UDP session.
    public func routePacket(
        sessionID: UDPSessionID,
        data: Data,
        proxyConnector: ProxyConnector
    ) async throws -> [Data] {
        // Get or create session
        var session = sessions[sessionID]

        if session == nil {
            guard sessions.count < maxSessions else {
                throw UDPSessionManagerError.sessionLimitReached
            }

            // Determine if direct or proxy routing based on destination
            let target = ConnectionTarget(host: sessionID.dstIP, port: Int(sessionID.dstPort))

            // For now, establish the proxy connection
            // In a full implementation, this would determine routing policy
            // and either connect directly or through a proxy node
            let context: ConnectedProxyContext? = nil  // Will be connected via proxyConnector

            let newSession = UDPSession(id: sessionID, remoteContext: context)
            sessions[sessionID] = newSession
            session = newSession

            // Start cleanup task
            let task = Task {
                try? await Task.sleep(for: sessionTimeout)
                await cleanupSession(id: sessionID)
            }
            cleanupTasks[sessionID] = task
        }

        guard let currentSession = session else {
            throw UDPSessionManagerError.sessionNotFound(sessionID)
        }

        return try await currentSession.process(data: data)
    }

    /// Close a specific session.
    public func closeSession(id: UDPSessionID) async {
        cleanupTasks[id]?.cancel()
        cleanupTasks.removeValue(forKey: id)
        if let session = sessions[id] {
            await session.close()
            sessions.removeValue(forKey: id)
        }
    }

    /// Close all sessions.
    public func closeAllSessions() async {
        for id in sessions.keys {
            cleanupTasks[id]?.cancel()
            if let session = sessions[id] {
                await session.close()
            }
        }
        sessions.removeAll()
        cleanupTasks.removeAll()
    }

    /// Get the count of active sessions.
    public var sessionCount: Int {
        sessions.count
    }

    /// Check if a session exists.
    public func hasSession(id: UDPSessionID) -> Bool {
        sessions[id] != nil
    }

    // MARK: - Private

    private func cleanupSession(id: UDPSessionID) {
        cleanupTasks[id]?.cancel()
        cleanupTasks.removeValue(forKey: id)
        sessions[id]?.close()
        sessions.removeValue(forKey: id)
    }

    private func resetSessionTimeout(sessionID: UDPSessionID) {
        // Cancel existing cleanup task and start a new one
        cleanupTasks[sessionID]?.cancel()
        let task = Task {
            try? await Task.sleep(for: sessionTimeout)
            await cleanupSession(id: sessionID)
        }
        cleanupTasks[sessionID] = task
    }
}
