import Foundation

public struct ConnectedProxyContext: Sendable {
    public let node: ProxyNode
    public let connection: PooledTransportConnection
    public let encryptedStream: ShadowsocksStream?
    /// Outer relay session when this context is the inner hop of a relay chain.
    public let relaySession: (any TransportSession)?

    public init(
        node: ProxyNode,
        connection: PooledTransportConnection,
        encryptedStream: ShadowsocksStream? = nil,
        relaySession: (any TransportSession)? = nil
    ) {
        self.node = node
        self.connection = connection
        self.encryptedStream = encryptedStream
        self.relaySession = relaySession
    }
}

public struct ProxyConnector: Sendable {
    /// The transport connection pool used by this connector.
    public let pool: TransportConnectionPool

    public init(pool: TransportConnectionPool) {
        self.pool = pool
    }

    public func connect(via node: ProxyNode, to target: ConnectionTarget) async throws -> ConnectedProxyContext {
        // Reality path: use RealityTransportDialer for TLS camouflage (SNI, ALPN, cert verification).
        // Reality connections bypass the transport pool because they require per-connection
        // TLS configuration that cannot be reused across different targets.
        if node.kind == .vless, let reality = RealityConfig.from(node: node) {
            return try await performVLESSRealityConnect(node: node, reality: reality, target: target)
        }

        let connection = try await pool.acquire(for: node)
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
            case .snell:
                return try await performSnellConnect(connection: connection, node: node, target: target)
            case .tuic:
                return try await performTUICConnect(connection: connection, node: node, target: target)
            case .wireguard:
                return try await performWireGuardConnect(connection: connection, node: node, target: target)
            case .relay:
                // Relay is handled at the LiveTunnelRuntime level where the full proxy
                // profile is available to resolve the chain. A relay node should never
                // reach ProxyConnector.connect() directly; it is always unwrapped there.
                throw ProtocolError.malformedResponse("unexpected relay node in ProxyConnector")
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

    /// Establishes a VLESS + Reality connection using RealityTransportDialer for TLS
    /// camouflage. Reality connections bypass the transport pool because each connection
    /// requires unique TLS configuration (SNI set to camouflage target, not proxy server).
    private func performVLESSRealityConnect(
        node: ProxyNode,
        reality: RealityConfig,
        target: ConnectionTarget
    ) async throws -> ConnectedProxyContext {
        guard let uuidString = node.uuid, let uuid = UUID(uuidString: uuidString) else {
            throw ProtocolError.malformedResponse("VLESS Reality node missing uuid")
        }
        let dialer = RealityTransportDialer(
            reality: reality,
            proxyServer: node.server,
            proxyPort: node.port
        )
        let session = try await dialer.openSession(to: node)
        let vlessStream = VLESSStream(session: session, uuid: uuid, reality: reality)
        try await vlessStream.connect(to: target, flow: nil) // flow is nil in Reality mode
        let connection = PooledTransportConnection(node: node, session: session)
        return ConnectedProxyContext(node: node, connection: connection)
    }

    /// Standard (non-Reality) VLESS connection.
    private func performVLESSConnect(
        connection: PooledTransportConnection,
        node: ProxyNode,
        target: ConnectionTarget
    ) async throws -> ConnectedProxyContext {
        guard let uuidString = node.uuid, let uuid = UUID(uuidString: uuidString) else {
            throw ProtocolError.malformedResponse("VLESS node missing uuid")
        }
        // Reality nodes are handled by performVLESSRealityConnect() before pool acquire.
        // This method only processes standard VLESS connections.
        let vlessStream = VLESSStream(session: connection.session, uuid: uuid, reality: nil)
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

        // Try QUIC first, fall back to the provided transport session
        let h2Stream: Hysteria2Stream
        let useQuic = node.sni != nil || true // Always try QUIC for Hysteria2

        if useQuic {
            do {
                let quicSession = QUICTransportSession.makeSession(
                    host: node.server,
                    port: UInt16(node.port),
                    alpn: ["hysteria2"]
                )
                try await quicSession.connect()
                h2Stream = Hysteria2Stream(quicSession: quicSession, password: password, obfuscated: false)
                try await h2Stream.connect(to: target)
                return ConnectedProxyContext(node: node, connection: connection)
            } catch QUICTransportSession.QUICTransportError.quicNotAvailable {
                // QUIC not available — Hysteria2 requires QUIC, do not silently fall back to TCP
                // (Hysteria2 over TCP is non-standard and violates "no silent fallbacks" principle)
                throw ProtocolError.transportUnavailable(
                    "Hysteria2 requires QUIC support (macOS 14+). QUIC is not available on this system."
                )
            }
        } else {
            let fallbackStream = Hysteria2Stream(session: connection.session, password: password)
            try await fallbackStream.connect(to: target)
            return ConnectedProxyContext(node: node, connection: connection)
        }
    }

    private func performTUICConnect(
        connection: PooledTransportConnection,
        node: ProxyNode,
        target: ConnectionTarget
    ) async throws -> ConnectedProxyContext {
        guard let uuidString = node.uuid, let uuid = UUID(uuidString: uuidString), let password = node.password else {
            throw ProtocolError.malformedResponse("TUIC node missing uuid or password")
        }
        let tuicConfig = TUICConfig(
            uuid: uuid,
            password: password,
            server: node.server,
            port: node.port,
            congestionControl: .bbr,
            alpn: node.alpn
        )
        if #available(macOS 14.0, *) {
            let client = TUICClient(config: tuicConfig)
            _ = try await client.connect()
            _ = try await client.openStream(to: target)
            return ConnectedProxyContext(node: node, connection: connection)
        } else {
            throw ProtocolError.connectionRejected("TUIC requires macOS 14+")
        }
    }

    private func performSnellConnect(
        connection: PooledTransportConnection,
        node: ProxyNode,
        target: ConnectionTarget
    ) async throws -> ConnectedProxyContext {
        guard let password = node.password else {
            throw ProtocolError.malformedResponse("Snell node missing PSK")
        }
        let version = node.snellVersion ?? 2
        let snellStream = SnellStream(session: connection.session, password: password, version: version)
        try await snellStream.connect(to: target)
        return ConnectedProxyContext(node: node, connection: connection)
    }

    /// Native WireGuard connection via the Swift implementation.
    ///
    /// WireGuard is a Layer 3 tunnel, so this method wraps the connection
    /// target's IP packets through the WireGuard UDP tunnel.
    /// In production, this integrates with the `WireGuardStream` and
    /// reuses the `WireGuardHandshake` state for the given peer.
    private func performWireGuardConnect(
        connection: PooledTransportConnection,
        node: ProxyNode,
        target: ConnectionTarget
    ) async throws -> ConnectedProxyContext {
        // Build WireGuard configuration from ProxyNode fields
        guard let privateKey = node.wireguardPrivateKey,
              let localAddress = node.wireguardIP,
              let peerPublicKey = node.wireguardPublicKey else {
            throw ProtocolError.connectionRejected("WireGuard node missing keys or address")
        }

        let wgConfig = WireGuardConfig(
            privateKey: privateKey,
            localAddress: localAddress,
            mtu: node.wireguardMTU ?? WireGuardConstants.defaultMTU,
            peers: [
                WireGuardConfig.WireGuardPeer(
                    publicKey: peerPublicKey,
                    preSharedKey: node.wireguardPreSharedKey,
                    endpoint: "\(node.host):\(node.port)",
                    allowedIPs: ["0.0.0.0/0"],
                    persistentKeepalive: 25,
                    reserved: node.wireguardReserved.flatMap { Data($0) }
                )
            ]
        )

        let handshake = try WireGuardHandshake(config: wgConfig)
        let wgStream = WireGuardStream(config: wgConfig, handshake: handshake)
        try await wgStream.connect(to: target.host, port: target.port)
        return ConnectedProxyContext(node: node, connection: connection)
    }

}
