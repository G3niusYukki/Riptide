import Foundation
import Testing

@testable import Riptide

@Suite("Relay proxy chain")
struct RelayProxyChainTests {

    // MARK: - Parser tests

    @Test("ClashConfigParser parses relay proxy node with chain field")
    func parseRelayProxyNode() throws {
        let yaml = """
        mode: rule
        proxies:
          - name: node-a
            type: ss
            server: 10.0.0.1
            port: 8388
            cipher: aes-256-gcm
            password: pass-a
          - name: node-b
            type: relay
            server: 127.0.0.1
            port: 0
            chain: node-a
        rules:
          - MATCH,node-b
        """
        let config = try ClashConfigParser.parse(yaml: yaml)

        let nodeA = config.proxies.first { $0.name == "node-a" }
        #expect(nodeA != nil)
        #expect(nodeA?.kind == .shadowsocks)

        let nodeB = config.proxies.first { $0.name == "node-b" }
        #expect(nodeB != nil)
        #expect(nodeB?.kind == .relay)
        #expect(nodeB?.chainProxyName == "node-a")
    }

    @Test("ClashConfigParser rejects relay node without chain field")
    func parseRelayProxyNodeMissingChain() throws {
        let yaml = """
        mode: rule
        proxies:
          - name: node-b
            type: relay
            server: 127.0.0.1
            port: 0
        rules:
          - MATCH,node-b
        """
        do {
            _ = try ClashConfigParser.parse(yaml: yaml)
            #expect(false, "Expected ClashConfigError")
        } catch let error as ClashConfigError {
            #expect(error == .invalidProxy(index: 0, reason: "chain proxy name is required for relay"))
        }
    }

    @Test("ClashConfigParser rejects unknown proxy type relay")
    func parseUnknownProxyType() throws {
        let yaml = """
        mode: rule
        proxies:
          - name: node-x
            type: unknown-type
            server: 127.0.0.1
            port: 0
        rules:
          - MATCH,node-x
        """
        do {
            _ = try ClashConfigParser.parse(yaml: yaml)
            #expect(false, "Expected ClashConfigError")
        } catch let error as ClashConfigError {
            #expect(error == .invalidProxy(index: 0, reason: "unsupported proxy type: unknown-type"))
        }
    }

    // MARK: - RelayTransportSession tests

    @Test("RelayTransportSession.send forwards data to inner session")
    func relayTransportSessionSend() async throws {
        let inner = MockTransportSession(receiveQueue: [])
        let relay = RelayTransportSession(inner: inner)

        try await relay.send(Data([0x01, 0x02, 0x03]))

        #expect(inner.sentFrames.count == 1)
        #expect(inner.sentFrames[0] == Data([0x01, 0x02, 0x03]))
    }

    @Test("RelayTransportSession.receive returns data from inner session")
    func relayTransportSessionReceive() async throws {
        let inner = MockTransportSession(receiveQueue: [Data([0xAA, 0xBB])])
        let relay = RelayTransportSession(inner: inner)

        let data = try await relay.receive()

        #expect(data == Data([0xAA, 0xBB]))
    }

    @Test("RelayTransportSession.close closes inner session")
    func relayTransportSessionClose() async throws {
        let inner = MockTransportSession(receiveQueue: [])
        let relay = RelayTransportSession(inner: inner)

        await relay.close()

        #expect(inner.isClosed == true)
    }

    // MARK: - Runtime integration tests

    @Test("LiveTunnelRuntime resolves relay policy and connects to terminal node")
    func relayPolicyConnectsToTerminalNode() async throws {
        // node-b is a relay to node-a; policy routes to node-b
        let nodeA = ProxyNode(name: "node-a", kind: .socks5, server: "10.0.0.1", port: 1080)
        let nodeB = ProxyNode(name: "node-b", kind: .relay, server: "127.0.0.1", port: 0, chainProxyName: "node-a")
        let config = RiptideConfig(
            mode: .rule,
            proxies: [nodeA, nodeB],
            rules: [.final(policy: .proxyNode(name: "node-b"))]
        )
        let profile = TunnelProfile(name: "relay-test", config: config)

        // The terminal node (node-a) responds with SOCKS5 handshake
        let terminalSession = MockTransportSession(receiveQueue: [
            Data([0x05, 0x00]),                        // SOCKS5 method selection response
            Data([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90]), // SOCKS5 connect reply
        ])
        let proxyDialer = LiveRuntimeMockDialer([terminalSession])
        let directDialer = LiveRuntimeMockDialer([])
        let runtime = LiveTunnelRuntime(
            proxyDialer: proxyDialer,
            directDialer: directDialer,
            dnsPipeline: DNSPipeline()
        )

        try await runtime.start(profile: profile)
        let context = try await runtime.openConnection(target: ConnectionTarget(host: "example.com", port: 443))

        // The context should be identified as the relay entry node (node-b)
        #expect(context.node.name == "node-b")
        #expect(context.node.kind == .relay)
        #expect(context.relaySession != nil)

        // The terminal node (node-a) should have been connected
        #expect(await proxyDialer.openRequests.count == 1)
        #expect(await proxyDialer.openRequests.first?.name == "node-a")
        #expect(await directDialer.openRequests.count == 0)
    }

    @Test("LiveTunnelRuntime closeConnection closes relay session and inner connection")
    func relayCloseConnectionClosesBothSessions() async throws {
        let nodeA = ProxyNode(name: "node-a", kind: .socks5, server: "10.0.0.1", port: 1080)
        let nodeB = ProxyNode(name: "node-b", kind: .relay, server: "127.0.0.1", port: 0, chainProxyName: "node-a")
        let config = RiptideConfig(
            mode: .rule,
            proxies: [nodeA, nodeB],
            rules: [.final(policy: .proxyNode(name: "node-b"))]
        )
        let profile = TunnelProfile(name: "relay-close-test", config: config)

        let terminalSession = MockTransportSession(receiveQueue: [
            Data([0x05, 0x00]),
            Data([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90]),
        ])
        let proxyDialer = LiveRuntimeMockDialer([terminalSession])
        let directDialer = LiveRuntimeMockDialer([])
        let runtime = LiveTunnelRuntime(
            proxyDialer: proxyDialer,
            directDialer: directDialer,
            dnsPipeline: DNSPipeline()
        )

        try await runtime.start(profile: profile)
        let context = try await runtime.openConnection(target: ConnectionTarget(host: "example.com", port: 443))
        #expect(terminalSession.isClosed == false)

        await runtime.closeConnection(id: context.connection.id)

        // The inner session should be closed
        #expect(terminalSession.isClosed == true)
    }

    @Test("LiveTunnelRuntime throws when relay chain target is missing")
    func relayChainMissingTarget() async throws {
        let nodeB = ProxyNode(name: "node-b", kind: .relay, server: "127.0.0.1", port: 0, chainProxyName: "nonexistent")
        let config = RiptideConfig(
            mode: .rule,
            proxies: [nodeB],
            rules: [.final(policy: .proxyNode(name: "node-b"))]
        )
        let profile = TunnelProfile(name: "relay-missing", config: config)

        let proxyDialer = LiveRuntimeMockDialer([])
        let directDialer = LiveRuntimeMockDialer([])
        let runtime = LiveTunnelRuntime(
            proxyDialer: proxyDialer,
            directDialer: directDialer,
            dnsPipeline: DNSPipeline()
        )

        try await runtime.start(profile: profile)

        await #expect(throws: LiveTunnelRuntimeError.self) {
            _ = try await runtime.openConnection(target: ConnectionTarget(host: "example.com", port: 443))
        }
    }
}
