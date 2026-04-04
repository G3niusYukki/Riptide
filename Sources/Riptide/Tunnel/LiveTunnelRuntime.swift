import Foundation

public enum LiveTunnelRuntimeError: Error, Equatable, Sendable {
    case notStarted
    case rejectPolicy
    case missingProxyNode(String)
}

public actor LiveTunnelRuntime: TunnelRuntime {
    private let proxyDialer: any TransportDialer
    private let directDialer: any TransportDialer
    private let geoIPResolver: GeoIPResolver
    private let dnsPipeline: DNSPipeline
    private var proxyPool: TransportConnectionPool
    private var directPool: TransportConnectionPool
    private var connector: ProxyConnector
    private var currentProfile: TunnelProfile?
    private var currentStatus: TunnelRuntimeStatus
    private var activeConnections: [UUID: ConnectedProxyContext]
    /// Active rule-set providers, keyed by provider name.
    private var ruleSetProviders: [String: RuleSetProvider] = [:]
    /// Most-recently-loaded rules for each provider.
    private var ruleSetRules: [String: [ProxyRule]] = [:]
    private var ruleSetRefreshTask: Task<Void, Never>?

    public init(
        proxyDialer: any TransportDialer,
        directDialer: any TransportDialer,
        geoIPResolver: GeoIPResolver = .none,
        dnsPipeline: DNSPipeline
    ) {
        self.proxyDialer = proxyDialer
        self.directDialer = directDialer
        self.geoIPResolver = geoIPResolver
        self.dnsPipeline = dnsPipeline
        self.proxyPool = TransportConnectionPool(dialer: proxyDialer)
        self.directPool = TransportConnectionPool(dialer: directDialer)
        self.connector = ProxyConnector(pool: proxyPool)
        self.currentProfile = nil
        self.currentStatus = TunnelRuntimeStatus()
        self.activeConnections = [:]
    }

    public func start(profile: TunnelProfile) async throws {
        currentProfile = profile
        currentStatus = TunnelRuntimeStatus()
        activeConnections.removeAll()
        proxyPool = TransportConnectionPool(dialer: proxyDialer)
        directPool = TransportConnectionPool(dialer: directDialer)
        connector = ProxyConnector(pool: proxyPool)
        // Fake-IP pool is initialized in DNSPipeline.init from dnsPolicy.fakeIPRange;
        // no separate start call needed.

        // Start rule-set providers.
        ruleSetProviders.removeAll()
        ruleSetRules.removeAll()
        ruleSetRefreshTask?.cancel()
        ruleSetRefreshTask = nil

        for (_, config) in profile.config.ruleProviders {
            let provider = RuleSetProvider(config: config)
            ruleSetProviders[config.name] = provider
            await provider.start()
        }

        // Wait for initial load of all providers before accepting connections.
        await refreshRuleSets()

        // Schedule periodic refreshes every 60 seconds.
        ruleSetRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await refreshRuleSets()
            }
        }
    }

    /// Refresh all rule-set providers and update the cached rules.
    private func refreshRuleSets() async {
        for (name, provider) in ruleSetProviders {
            let rules = await provider.rules()
            ruleSetRules[name] = rules
        }
    }

    public func stop() async throws {
        for context in activeConnections.values {
            await context.connection.session.close()
        }
        activeConnections.removeAll()
        currentProfile = nil
        currentStatus = TunnelRuntimeStatus()

        ruleSetRefreshTask?.cancel()
        ruleSetRefreshTask = nil
        for provider in ruleSetProviders.values {
            await provider.stop()
        }
        ruleSetProviders.removeAll()
        ruleSetRules.removeAll()
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

        let policy = await resolvePolicy(profile: profile, target: target)
        switch policy {
        case .reject:
            throw LiveTunnelRuntimeError.rejectPolicy

        case .direct:
            let directNode = ProxyNode(
                name: "DIRECT",
                kind: .shadowsocks,
                server: target.host,
                port: target.port
            )
            let connection = try await directPool.acquire(for: directNode)
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
            let context: ConnectedProxyContext
            if node.kind == .relay {
                // Relay: follow the chain to find the terminal non-relay node, connect to it,
                // and wrap the connection in a RelayTransportSession so all traffic is tunneled
                // through the relay hop.
                guard let chainName = node.chainProxyName else {
                    throw LiveTunnelRuntimeError.missingProxyNode("\(name) (relay with no chain target)")
                }
                guard let terminalNode = profile.config.proxies.first(where: { $0.name == chainName }) else {
                    throw LiveTunnelRuntimeError.missingProxyNode(chainName)
                }
                let innerContext = try await connector.connect(via: terminalNode, to: target)
                let relaySession: any TransportSession = RelayTransportSession(inner: innerContext.connection.session)
                context = ConnectedProxyContext(
                    node: node,
                    connection: innerContext.connection,
                    encryptedStream: innerContext.encryptedStream,
                    relaySession: relaySession
                )
            } else {
                context = try await connector.connect(via: node, to: target)
            }
            activeConnections[context.connection.id] = context
            currentStatus = TunnelRuntimeStatus(
                bytesUp: currentStatus.bytesUp,
                bytesDown: currentStatus.bytesDown,
                activeConnections: activeConnections.count
            )
            return context
        }
    }

    public func recordTransfer(connectionID: UUID, bytesUp: UInt64 = 0, bytesDown: UInt64 = 0) {
        guard activeConnections[connectionID] != nil else {
            return
        }

        currentStatus = TunnelRuntimeStatus(
            bytesUp: currentStatus.bytesUp + bytesUp,
            bytesDown: currentStatus.bytesDown + bytesDown,
            activeConnections: activeConnections.count
        )
    }

    public func closeConnection(id: UUID) async {
        guard let context = activeConnections.removeValue(forKey: id) else {
            return
        }

        // Close the relay session wrapping the inner connection, if any.
        if let relaySession = context.relaySession as? RelayTransportSession {
            await relaySession.close()
        }

        if context.node.name == "DIRECT" {
            await directPool.release(context.connection)
        } else {
            // Proxy connections (SOCKS5, HTTP CONNECT, etc.) become tunnels to a specific
            // target after the protocol handshake. They cannot be reused for different
            // targets, so discard rather than release back to the pool.
            await proxyPool.discard(context.connection)
        }

        currentStatus = TunnelRuntimeStatus(
            bytesUp: currentStatus.bytesUp,
            bytesDown: currentStatus.bytesDown,
            activeConnections: activeConnections.count
        )
    }

    private func resolvePolicy(profile: TunnelProfile, target: ConnectionTarget) async -> RoutingPolicy {
        switch profile.config.mode {
        case .direct:
            return .direct
        case .global:
            guard let firstProxy = profile.config.proxies.first else {
                return .reject
            }
            return .proxyNode(name: firstProxy.name)
        case .rule:
            break
        }

        // Resolve the host to an IP before rule matching.
        // In fakeIP mode: if already a fake IP, use it directly; otherwise allocate one.
        // In realIP mode: resolve domain via DNS, pass-through if already an IP.
        let resolvedIP: String?
        if profile.config.dnsPolicy.fakeIPEnabled {
            if await dnsPipeline.isFakeIP(target.host) {
                resolvedIP = target.host
            } else {
                resolvedIP = (try? await dnsPipeline.resolveFakeIP(target.host)) ?? target.host
            }
        } else if IPv4AddressParser.parse(target.host) == nil {
            // Domain — resolve it
            resolvedIP = (try? await dnsPipeline.resolve(target.host)).flatMap { $0.first }
        } else {
            resolvedIP = target.host
        }

        let ruleTarget = RuleTarget(domain: target.host, ipAddress: resolvedIP)
        let engine = RuleEngine(
            rules: profile.config.rules,
            ruleSets: ruleSetRules,
            geoIPResolver: geoIPResolver
        )
        return engine.resolve(target: ruleTarget)
    }
}
