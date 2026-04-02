import Foundation

public actor TransportConnectionPool {
    private let dialer: any TransportDialer
    private var idleByNodeKey: [String: [PooledTransportConnection]]

    public init(dialer: any TransportDialer) {
        self.dialer = dialer
        self.idleByNodeKey = [:]
    }

    public func acquire(for node: ProxyNode) async throws -> PooledTransportConnection {
        let key = nodePoolKey(node)
        if var idle = idleByNodeKey[key], !idle.isEmpty {
            let connection = idle.removeFirst()
            idleByNodeKey[key] = idle
            return connection
        }

        let session = try await dialer.openSession(to: node)
        return PooledTransportConnection(node: node, session: session)
    }

    public func release(_ connection: PooledTransportConnection) {
        let key = nodePoolKey(connection.node)
        idleByNodeKey[key, default: []].append(connection)
    }

    public func discard(_ connection: PooledTransportConnection) async {
        await connection.session.close()
    }

    private func nodePoolKey(_ node: ProxyNode) -> String {
        "\(node.kind)-\(node.name)-\(node.server)-\(node.port)"
    }
}
