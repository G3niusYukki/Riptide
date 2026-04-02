import Foundation
import Testing

@testable import Riptide

@Suite("Live tunnel runtime")
struct LiveTunnelRuntimeTests {
    @Test("REJECT policy returns explicit rejection error")
    func rejectPolicy() async throws {
        let config = RiptideConfig(
            mode: .rule,
            proxies: [],
            rules: [.final(policy: .reject)]
        )
        let profile = TunnelProfile(name: "reject", config: config)
        let dialer = LiveRuntimeMockDialer([])
        let runtime = LiveTunnelRuntime(proxyDialer: dialer, directDialer: dialer)

        try await runtime.start(profile: profile)

        await #expect(throws: LiveTunnelRuntimeError.self) {
            _ = try await runtime.openConnection(target: ConnectionTarget(host: "example.com", port: 443))
        }
    }

    @Test("DIRECT policy uses direct dialer")
    func directPolicyUsesDirectDialer() async throws {
        let config = RiptideConfig(
            mode: .rule,
            proxies: [ProxyNode(name: "proxy", kind: .socks5, server: "1.1.1.1", port: 1080)],
            rules: [.final(policy: .direct)]
        )
        let profile = TunnelProfile(name: "direct", config: config)

        let directSession = MockTransportSession(receiveQueue: [])
        let directDialer = LiveRuntimeMockDialer([directSession])
        let proxyDialer = LiveRuntimeMockDialer([])
        let runtime = LiveTunnelRuntime(proxyDialer: proxyDialer, directDialer: directDialer)

        try await runtime.start(profile: profile)
        let context = try await runtime.openConnection(target: ConnectionTarget(host: "example.com", port: 443))
        #expect(context.node.kind == .http)
        #expect(await directDialer.openRequests.count == 1)
        #expect(await proxyDialer.openRequests.count == 0)
    }

    @Test("Proxy policy uses proxy dialer and protocol handshake path")
    func proxyPolicyUsesProxyDialer() async throws {
        let node = ProxyNode(name: "socks-node", kind: .socks5, server: "10.0.0.2", port: 1080)
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .proxyNode(name: "socks-node"))]
        )
        let profile = TunnelProfile(name: "proxy", config: config)

        let proxySession = MockTransportSession(receiveQueue: [
            Data([0x05, 0x00]),
            Data([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90]),
        ])
        let proxyDialer = LiveRuntimeMockDialer([proxySession])
        let directDialer = LiveRuntimeMockDialer([])
        let runtime = LiveTunnelRuntime(proxyDialer: proxyDialer, directDialer: directDialer)

        try await runtime.start(profile: profile)
        let context = try await runtime.openConnection(target: ConnectionTarget(host: "example.com", port: 443))

        #expect(context.node.name == "socks-node")
        #expect(await proxyDialer.openRequests.count == 1)
        #expect(await directDialer.openRequests.count == 0)
    }

    @Test("GEOIP policy uses proxy path with injected resolver")
    func geoIPPolicyUsesResolver() async throws {
        let node = ProxyNode(name: "socks-node", kind: .socks5, server: "10.0.0.2", port: 1080)
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [
                .geoIP(countryCode: "CN", policy: .proxyNode(name: "socks-node")),
                .final(policy: .direct),
            ]
        )
        let profile = TunnelProfile(name: "geoip-proxy", config: config)

        let proxySession = MockTransportSession(receiveQueue: [
            Data([0x05, 0x00]),
            Data([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90]),
        ])
        let proxyDialer = LiveRuntimeMockDialer([proxySession])
        let directDialer = LiveRuntimeMockDialer([])
        let runtime = LiveTunnelRuntime(
            proxyDialer: proxyDialer,
            directDialer: directDialer,
            geoIPResolver: GeoIPResolver(resolveCountryCode: { ip in
                if ip == "1.1.1.1" { return "CN" }
                return nil
            })
        )

        try await runtime.start(profile: profile)
        _ = try await runtime.openConnection(target: ConnectionTarget(host: "1.1.1.1", port: 443))

        #expect(await proxyDialer.openRequests.count == 1)
        #expect(await directDialer.openRequests.count == 0)
    }

    @Test("direct mode bypasses rules and proxies")
    func directModeBypassesRulesAndProxies() async throws {
        let config = RiptideConfig(
            mode: .direct,
            proxies: [],
            rules: []
        )
        let profile = TunnelProfile(name: "direct-mode", config: config)

        let directSession = MockTransportSession(receiveQueue: [])
        let directDialer = LiveRuntimeMockDialer([directSession])
        let proxyDialer = LiveRuntimeMockDialer([])
        let runtime = LiveTunnelRuntime(proxyDialer: proxyDialer, directDialer: directDialer)

        try await runtime.start(profile: profile)
        let context = try await runtime.openConnection(target: ConnectionTarget(host: "example.com", port: 443))

        #expect(context.node.name == "DIRECT")
        #expect(await directDialer.openRequests.count == 1)
        #expect(await proxyDialer.openRequests.count == 0)
    }

    @Test("global mode uses first configured proxy when rules are absent")
    func globalModeUsesFirstProxy() async throws {
        let first = ProxyNode(name: "first-node", kind: .socks5, server: "10.0.0.2", port: 1080)
        let second = ProxyNode(name: "second-node", kind: .http, server: "10.0.0.3", port: 8080)
        let config = RiptideConfig(
            mode: .global,
            proxies: [first, second],
            rules: []
        )
        let profile = TunnelProfile(name: "global-mode", config: config)

        let proxySession = MockTransportSession(receiveQueue: [
            Data([0x05, 0x00]),
            Data([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90]),
        ])
        let proxyDialer = LiveRuntimeMockDialer([proxySession])
        let directDialer = LiveRuntimeMockDialer([])
        let runtime = LiveTunnelRuntime(proxyDialer: proxyDialer, directDialer: directDialer)

        try await runtime.start(profile: profile)
        let context = try await runtime.openConnection(target: ConnectionTarget(host: "example.com", port: 443))

        #expect(context.node.name == "first-node")
        #expect(await proxyDialer.openRequests.count == 1)
        #expect(await directDialer.openRequests.count == 0)
    }
}
