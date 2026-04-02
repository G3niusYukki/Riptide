import Foundation
import Testing

@testable import Riptide

@Suite("Transport integration")
struct TransportIntegrationTests {
    @Test("connection pool reuses released connection for same node")
    func poolReuse() async throws {
        let node = ProxyNode(name: "socks-node", kind: .socks5, server: "1.2.3.4", port: 1080)
        let session = MockTransportSession(receiveQueue: [])
        let dialer = MockTransportDialer([session])
        let pool = TransportConnectionPool(dialer: dialer)

        let first = try await pool.acquire(for: node)
        await pool.release(first)
        let second = try await pool.acquire(for: node)

        #expect(first.id == second.id)
        #expect(await dialer.openCount == 1)
    }

    @Test("pool enforces max idle connections per node")
    func poolMaxIdlePerNode() async throws {
        let node = ProxyNode(name: "test", kind: .socks5, server: "1.2.3.4", port: 1080)
        let sessions = (0..<7).map { _ in MockTransportSession(receiveQueue: []) }
        let dialer = MockTransportDialer(sessions)
        let pool = TransportConnectionPool(dialer: dialer, maxIdlePerNode: 3)

        var connections: [PooledTransportConnection] = []
        for _ in 0..<7 {
            let conn = try await pool.acquire(for: node)
            connections.append(conn)
        }

        for conn in connections {
            await pool.release(conn)
        }

        let _ = try await pool.acquire(for: node)
        #expect(await dialer.openCount == 7)

        let _ = try await pool.acquire(for: node)
        #expect(await dialer.openCount == 8)
    }

    @Test("pool discards stale connections on acquire")
    func poolEvictsStaleConnections() async throws {
        let node = ProxyNode(name: "test", kind: .socks5, server: "1.2.3.4", port: 1080)
        let session = MockTransportSession(receiveQueue: [])
        let dialer = MockTransportDialer([session])
        let pool = TransportConnectionPool(dialer: dialer, maxIdlePerNode: 5, maxIdleLifetime: .milliseconds(50))

        let conn = try await pool.acquire(for: node)
        await pool.release(conn)

        try await Task.sleep(for: .milliseconds(100))

        let reused = try await pool.acquire(for: node)
        #expect(reused.id != conn.id)
        #expect(await dialer.openCount == 2)
    }

    @Test("HTTP connector performs request response handshake")
    func httpConnectFlow() async throws {
        let node = ProxyNode(name: "http-node", kind: .http, server: "10.0.0.1", port: 8080)
        let session = MockTransportSession(receiveQueue: [Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)])
        let dialer = MockTransportDialer([session])
        let pool = TransportConnectionPool(dialer: dialer)
        let connector = ProxyConnector(pool: pool)

        let context = try await connector.connect(via: node, to: ConnectionTarget(host: "example.com", port: 443))
        #expect(context.node.name == "http-node")
        #expect(await session.sentFrames.count == 1)
        await pool.discard(context.connection)
    }

    @Test("SOCKS5 connector performs two step handshake in order")
    func socks5ConnectFlow() async throws {
        let node = ProxyNode(name: "socks-node", kind: .socks5, server: "10.0.0.2", port: 1080)
        let session = MockTransportSession(receiveQueue: [
            Data([0x05, 0x00]),
            Data([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90]),
        ])
        let dialer = MockTransportDialer([session])
        let pool = TransportConnectionPool(dialer: dialer)
        let connector = ProxyConnector(pool: pool)

        _ = try await connector.connect(via: node, to: ConnectionTarget(host: "example.com", port: 443))

        let sent = await session.sentFrames
        #expect(sent.count == 2)
        #expect(sent[0] == Data([0x05, 0x01, 0x00]))
        #expect(sent[1].prefix(3) == Data([0x05, 0x01, 0x00]))
    }

    @Test("SOCKS5 auth failure closes session and propagates error")
    func socks5FailureFlow() async throws {
        let node = ProxyNode(name: "socks-node", kind: .socks5, server: "10.0.0.2", port: 1080)
        let session = MockTransportSession(receiveQueue: [Data([0x05, 0xFF])])
        let dialer = MockTransportDialer([session])
        let pool = TransportConnectionPool(dialer: dialer)
        let connector = ProxyConnector(pool: pool)

        await #expect(throws: ProtocolError.self) {
            _ = try await connector.connect(via: node, to: ConnectionTarget(host: "example.com", port: 443))
        }
        #expect(await session.isClosed)
    }

    @Test("Shadowsocks connector sends encrypted handshake (salt + AEAD chunk)")
    func shadowsocksEncryptedHandshake() async throws {
        let node = ProxyNode(
            name: "ss-node",
            kind: .shadowsocks,
            server: "10.0.0.3",
            port: 8388,
            cipher: "aes-256-gcm",
            password: "secret"
        )
        let session = MockTransportSession(receiveQueue: [])
        let dialer = MockTransportDialer([session])
        let pool = TransportConnectionPool(dialer: dialer)
        let connector = ProxyConnector(pool: pool)

        let context = try await connector.connect(via: node, to: ConnectionTarget(host: "example.com", port: 443))

        let sent = await session.sentFrames
        #expect(sent.count == 1)

        let frame = sent[0]
        #expect(frame.count > 32)

        let salt = frame.prefix(32)
        #expect(salt.count == 32)

        #expect(context.encryptedStream != nil)
    }
}
