import Foundation

public struct ConnectedProxyContext: Sendable {
    public let node: ProxyNode
    public let connection: PooledTransportConnection
    public let encryptedStream: ShadowsocksStream?

    public init(node: ProxyNode, connection: PooledTransportConnection, encryptedStream: ShadowsocksStream? = nil) {
        self.node = node
        self.connection = connection
        self.encryptedStream = encryptedStream
    }
}

public struct ProxyConnector: Sendable {
    private let pool: TransportConnectionPool

    public init(pool: TransportConnectionPool) {
        self.pool = pool
    }

    public func connect(via node: ProxyNode, to target: ConnectionTarget) async throws -> ConnectedProxyContext {
        let dialer = selectDialer(for: node)
        let connection = try await pool.acquire(for: node, using: dialer)
        do {
            switch node.kind {
            case .http:
                try await performHTTPConnect(session: connection.session, target: target)
            case .socks5:
                try await performSOCKS5Connect(session: connection.session, target: target)
            case .shadowsocks:
                return try await performShadowsocksConnect(connection: connection, node: node, target: target)
            case .vless:
                return try await performVLESSConnect(connection: connection, node: node, target: target)
            case .trojan:
                return try await performTrojanConnect(connection: connection, node: node, target: target)
            case .vmess:
                return try await performVMessConnect(connection: connection, node: node, target: target)
            case .hysteria2:
                return try await performHysteria2Connect(connection: connection, node: node, target: target)
            }
            return ConnectedProxyContext(node: node, connection: connection)
        } catch {
            await pool.discard(connection)
            throw error
        }
    }

    private func performHTTPConnect(
        session: any TransportSession,
        target: ConnectionTarget
    ) async throws {
        let proto = HTTPConnectProtocol()
        let frames = try proto.makeConnectRequest(for: target)
        for frame in frames {
            try await session.send(frame)
        }
        let responseData = try await session.receive()
        _ = try proto.parseConnectResponse(responseData)
    }

    private func performSOCKS5Connect(
        session: any TransportSession,
        target: ConnectionTarget
    ) async throws {
        let proto = SOCKS5Protocol()
        let frames = try proto.makeConnectRequest(for: target)
        guard frames.count == 2 else {
            throw ProtocolError.malformedResponse("unexpected SOCKS5 frame count")
        }

        try await session.send(frames[0])
        let methodSelection = try await session.receive()
        try proto.parseMethodSelection(methodSelection)

        try await session.send(frames[1])
        let connectReply = try await session.receive()
        _ = try proto.parseConnectResponse(connectReply)
    }

    private func performShadowsocksConnect(
        connection: PooledTransportConnection,
        node: ProxyNode,
        target: ConnectionTarget
    ) async throws -> ConnectedProxyContext {
        guard let cipher = node.cipher, let password = node.password else {
            throw ProtocolError.malformedResponse("shadowsocks node missing cipher or password")
        }

        let ssStream = try ShadowsocksStream(
            session: connection.session,
            cipher: cipher,
            password: password
        )

        let proto = ShadowsocksProtocol()
        let preamble = try proto.makeConnectRequest(for: target)
        guard let preambleData = preamble.first else {
            throw ProtocolError.malformedResponse("shadowsocks preamble empty")
        }

        try await ssStream.sendHandshake(preambleData)

        return ConnectedProxyContext(
            node: node,
            connection: connection,
            encryptedStream: ssStream
        )
    }

    private func performVLESSConnect(
        connection: PooledTransportConnection,
        node: ProxyNode,
        target: ConnectionTarget
    ) async throws -> ConnectedProxyContext {
        guard let uuidString = node.uuid, let uuid = UUID(uuidString: uuidString) else {
            throw ProtocolError.malformedResponse("VLESS node missing uuid")
        }
        let vlessStream = VLESSStream(session: connection.session, uuid: uuid)
        try await vlessStream.connect(to: target, flow: node.flow)
        return ConnectedProxyContext(node: node, connection: connection)
    }

    private func performTrojanConnect(
        connection: PooledTransportConnection,
        node: ProxyNode,
        target: ConnectionTarget
    ) async throws -> ConnectedProxyContext {
        guard let password = node.password else {
            throw ProtocolError.malformedResponse("Trojan node missing password")
        }
        let trojanStream = try TrojanStream(session: connection.session, password: password)
        try await trojanStream.connect(to: target)
        return ConnectedProxyContext(node: node, connection: connection)
    }

    private func performVMessConnect(
        connection: PooledTransportConnection,
        node: ProxyNode,
        target: ConnectionTarget
    ) async throws -> ConnectedProxyContext {
        guard let uuidString = node.uuid, let uuid = UUID(uuidString: uuidString) else {
            throw ProtocolError.malformedResponse("VMess node missing uuid")
        }
        let vmessStream = VMessStream(session: connection.session, uuid: uuid)
        try await vmessStream.connect(to: target)
        return ConnectedProxyContext(node: node, connection: connection)
    }

    private func performHysteria2Connect(
        connection: PooledTransportConnection,
        node: ProxyNode,
        target: ConnectionTarget
    ) async throws -> ConnectedProxyContext {
        guard let password = node.password else {
            throw ProtocolError.malformedResponse("Hysteria2 node missing password")
        }
        let hysteria2Stream = Hysteria2Stream(session: connection.session, password: password)
        try await hysteria2Stream.connect(to: target)
        return ConnectedProxyContext(node: node, connection: connection)
    }

    private func selectDialer(for node: ProxyNode) -> any TransportDialer {
        let useTLS = node.port == 443 || node.sni != nil || node.skipCertVerify == true
        if node.network == "ws" {
            return WSTransportDialer()
        } else if node.network == "grpc" {
            // gRPC transport not yet wired; fall back to TLS for now.
            return TLSTransportDialer()
        } else if useTLS {
            return TLSTransportDialer()
        } else {
            return TCPTransportDialer()
        }
    }
}
