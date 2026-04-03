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

public actor TransportConnectionPool {
    private let dialer: any TransportDialer
    private let maxIdlePerNode: Int
    private let maxIdleLifetime: Duration
    private var idleByNodeKey: [PoolKey: [PooledConnection]]

    public init(
        dialer: any TransportDialer,
        maxIdlePerNode: Int = 5,
        maxIdleLifetime: Duration = .seconds(300)
    ) {
        self.dialer = dialer
        self.maxIdlePerNode = maxIdlePerNode
        self.maxIdleLifetime = maxIdleLifetime
        self.idleByNodeKey = [:]
    }

    public func acquire(for node: ProxyNode) async throws -> PooledTransportConnection {
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

    public func acquire(for node: ProxyNode, using dialer: any TransportDialer) async throws -> PooledTransportConnection {
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
        guard var idle = idleByNodeKey[key], !idle.isEmpty else { return }
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
