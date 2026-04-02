import Foundation

public enum LiveTunnelRuntimeError: Error, Equatable, Sendable {
    case notStarted
    case rejectPolicy
    case missingProxyNode(String)
}

public actor LiveTunnelRuntime: TunnelRuntime {
    private let proxyDialer: any TransportDialer
    private let directDialer: any TransportDialer
    private var currentProfile: TunnelProfile?
    private var currentStatus: TunnelRuntimeStatus
    private var activeConnections: [UUID: ConnectedProxyContext]

    public init(proxyDialer: any TransportDialer, directDialer: any TransportDialer) {
        self.proxyDialer = proxyDialer
        self.directDialer = directDialer
        self.currentProfile = nil
        self.currentStatus = TunnelRuntimeStatus()
        self.activeConnections = [:]
    }

    public func start(profile: TunnelProfile) async throws {
        currentProfile = profile
        currentStatus = TunnelRuntimeStatus()
        activeConnections.removeAll()
    }

    public func stop() async throws {
        for context in activeConnections.values {
            await context.connection.session.close()
        }
        activeConnections.removeAll()
        currentProfile = nil
        currentStatus = TunnelRuntimeStatus()
    }

    public func update(profile: TunnelProfile) async throws {
        currentProfile = profile
    }

    public func status() async -> TunnelRuntimeStatus {
        currentStatus
    }

    public func openConnection(target: ConnectionTarget) async throws -> ConnectedProxyContext {
        guard let profile = currentProfile else {
            throw LiveTunnelRuntimeError.notStarted
        }

        let policy = resolvePolicy(profile: profile, target: target)
        switch policy {
        case .reject:
            throw LiveTunnelRuntimeError.rejectPolicy

        case .direct:
            let directNode = ProxyNode(
                name: "DIRECT",
                kind: .http,
                server: target.host,
                port: target.port
            )
            let pool = TransportConnectionPool(dialer: directDialer)
            let connection = try await pool.acquire(for: directNode)
            let context = ConnectedProxyContext(node: directNode, connection: connection)
            activeConnections[context.connection.id] = context
            currentStatus = TunnelRuntimeStatus(
                bytesUp: currentStatus.bytesUp,
                bytesDown: currentStatus.bytesDown,
                activeConnections: activeConnections.count
            )
            return context

        case .proxyNode(let name):
            guard let node = profile.config.proxies.first(where: { $0.name == name }) else {
                throw LiveTunnelRuntimeError.missingProxyNode(name)
            }
            let pool = TransportConnectionPool(dialer: proxyDialer)
            let connector = ProxyConnector(pool: pool)
            let context = try await connector.connect(via: node, to: target)
            activeConnections[context.connection.id] = context
            currentStatus = TunnelRuntimeStatus(
                bytesUp: currentStatus.bytesUp,
                bytesDown: currentStatus.bytesDown,
                activeConnections: activeConnections.count
            )
            return context
        }
    }

    private func resolvePolicy(profile: TunnelProfile, target: ConnectionTarget) -> RoutingPolicy {
        let ipAddress = IPv4AddressParser.parse(target.host) != nil ? target.host : nil
        let ruleTarget = RuleTarget(domain: target.host, ipAddress: ipAddress)
        let engine = RuleEngine(rules: profile.config.rules)
        return engine.resolve(target: ruleTarget)
    }
}
