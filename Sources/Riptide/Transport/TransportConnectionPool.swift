import Foundation

struct PoolKey: Hashable, Equatable, Sendable {
    let kind: ProxyKind
    let server: String
    let port: Int

    init(from node: ProxyNode) {
        self.kind = node.kind
        self.server = node.server
        self.port = node.port
    }
}

struct PooledConnection: Sendable {
    let connection: PooledTransportConnection
    let releasedAt: ContinuousClock.Instant
}

/// Dialer selector type — selects the appropriate TransportDialer for a given ProxyNode.
/// Used by TransportConnectionPool to determine which dialer to use per-connection.
public struct DialerSelector: @unchecked Sendable {
    private let _select: @Sendable (ProxyNode) -> any TransportDialer

    public init(select: @escaping @Sendable (ProxyNode) -> any TransportDialer) {
        self._select = select
    }

    public func select(for node: ProxyNode) -> any TransportDialer {
        _select(node)
    }

    /// Default selector matching Riptide's transport selection rules.
    public static var defaultSelector: DialerSelector {
        DialerSelector { node in
            let useTLS = node.port == 443 || node.sni != nil || node.skipCertVerify == true
            if node.network == "ws" {
                return WSTransportDialer()
            } else if node.network == "grpc" {
                return TLSTransportDialer()
            } else if node.network == "h2" || node.network == "http" {
                // HTTP2 transport not yet implemented; fall back to TLS.
                return TLSTransportDialer()
            } else if useTLS {
                return TLSTransportDialer()
            } else {
                return TCPTransportDialer()
            }
        }
    }
}

public actor TransportConnectionPool {
    private let dialer: any TransportDialer
    private let dialerSelector: DialerSelector
    private let maxIdlePerNode: Int
    private let maxIdleLifetime: Duration
    private var idleByNodeKey: [PoolKey: [PooledConnection]]

    public init(
        dialer: any TransportDialer = TCPTransportDialer(),
        dialerSelector: DialerSelector? = nil,
        maxIdlePerNode: Int = 5,
        maxIdleLifetime: Duration = .seconds(300)
    ) {
        self.dialer = dialer
        // If no selector provided, wrap the injected dialer so it is always used.
        // If a selector IS provided, use it (allows test injection via dialer parameter instead).
        if let selector = dialerSelector {
            self.dialerSelector = selector
        } else {
            // Default: wrap the injected dialer so acquire() uses it instead of creating dialers.
            self.dialerSelector = DialerSelector { _ in dialer }
        }
        self.maxIdlePerNode = maxIdlePerNode
        self.maxIdleLifetime = maxIdleLifetime
        self.idleByNodeKey = [:]
    }

    /// Acquires a connection by selecting the dialer via the pool's DialerSelector.
    public func acquire(for node: ProxyNode) async throws -> PooledTransportConnection {
        let key = PoolKey(from: node)
        await evictStale(key: key)

        if var idle = idleByNodeKey[key], !idle.isEmpty {
            let pooled = idle.removeFirst()
            idleByNodeKey[key] = idle
            return pooled.connection
        }

        let resolvedDialer = dialerSelector.select(for: node)
        let session = try await resolvedDialer.openSession(to: node)
        return PooledTransportConnection(node: node, session: session)
    }

    /// Acquires a connection using a caller-provided dialer.
    /// Useful for tests that inject mock dialers.
    public func acquire(for node: ProxyNode, using dialer: any TransportDialer) async throws -> PooledTransportConnection {
        let key = PoolKey(from: node)
        await evictStale(key: key)

        if var idle = idleByNodeKey[key], !idle.isEmpty {
            let pooled = idle.removeFirst()
            idleByNodeKey[key] = idle
            return pooled.connection
        }

        let session = try await dialer.openSession(to: node)
        return PooledTransportConnection(node: node, session: session)
    }

    public func release(_ connection: PooledTransportConnection) {
        let key = PoolKey(from: connection.node)
        let pooled = PooledConnection(connection: connection, releasedAt: ContinuousClock.now)
        var idle = idleByNodeKey[key] ?? []
        idle.append(pooled)
        if idle.count > maxIdlePerNode {
            let evicted = idle.removeFirst()
            Task { await evicted.connection.session.close() }
        }
        idleByNodeKey[key] = idle
    }

    public func discard(_ connection: PooledTransportConnection) async {
        await connection.session.close()
    }

    private func evictStale(key: PoolKey) async {
        guard let idle = idleByNodeKey[key], !idle.isEmpty else { return }
        let now = ContinuousClock.now
        var kept: [PooledConnection] = []
        for pooled in idle {
            let age = now - pooled.releasedAt
            if age >= maxIdleLifetime {
                await pooled.connection.session.close()
            } else {
                kept.append(pooled)
            }
        }
        idleByNodeKey[key] = kept
    }
}
