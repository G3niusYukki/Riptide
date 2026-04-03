import Foundation
import Testing

@testable import Riptide

@Suite("Proxy group runtime")
struct ProxyGroupRuntimeTests {
    @Test("select group respects persisted user choice")
    func selectGroupUsesPersistedChoice() async throws {
        let healthChecker = HealthChecker()
        let config = RiptideConfig(
            mode: .rule,
            proxies: [
                ProxyNode(name: "proxy-a", kind: .socks5, server: "1.2.3.4", port: 1080),
                ProxyNode(name: "proxy-b", kind: .socks5, server: "5.6.7.8", port: 1080),
            ],
            rules: [],
            proxyGroups: [
                ProxyGroup(id: "group-select", kind: .select, proxies: ["proxy-a", "proxy-b"])
            ]
        )
        let resolver = ProxyGroupResolver(healthChecker: healthChecker, config: config)

        try await resolver.setSelectedProxy(forGroup: "group-select", proxyName: "proxy-b")
        let resolved = try await resolver.resolve(groupID: "group-select")
        #expect(resolved == "proxy-b")
    }

    @Test("select group falls back to first available when no choice persisted")
    func selectGroupFallsBack() async throws {
        let healthChecker = HealthChecker()
        let config = RiptideConfig(
            mode: .rule,
            proxies: [
                ProxyNode(name: "proxy-a", kind: .socks5, server: "1.2.3.4", port: 1080),
                ProxyNode(name: "proxy-b", kind: .socks5, server: "5.6.7.8", port: 1080),
            ],
            rules: [],
            proxyGroups: [
                ProxyGroup(id: "group-select", kind: .select, proxies: ["proxy-a", "proxy-b"])
            ]
        )
        let resolver = ProxyGroupResolver(healthChecker: healthChecker, config: config)

        // No choice made — should return first proxy in list
        let resolved = try await resolver.resolve(groupID: "group-select")
        #expect(resolved == "proxy-a")
    }

    @Test("select group throws when group not found")
    func selectGroupNotFound() async throws {
        let healthChecker = HealthChecker()
        let config = RiptideConfig(mode: .rule, proxies: [], rules: [])
        let resolver = ProxyGroupResolver(healthChecker: healthChecker, config: config)

        do {
            _ = try await resolver.resolve(groupID: "nonexistent")
            Issue.record("Expected an error for nonexistent group")
        } catch ProxyGroupResolverError.groupNotFound {
            // expected
        }
    }

    @Test("resolvePolicy resolves group name to concrete proxy name")
    func resolvePolicyResolvesGroup() async throws {
        let healthChecker = HealthChecker()
        let config = RiptideConfig(
            mode: .rule,
            proxies: [
                ProxyNode(name: "proxy-a", kind: .socks5, server: "1.2.3.4", port: 1080),
            ],
            rules: [],
            proxyGroups: [
                ProxyGroup(id: "group-select", kind: .select, proxies: ["proxy-a"])
            ]
        )
        let resolver = ProxyGroupResolver(healthChecker: healthChecker, config: config)
        try await resolver.setSelectedProxy(forGroup: "group-select", proxyName: "proxy-a")

        let policy = try await resolver.resolvePolicy(.proxyNode(name: "group-select"))
        #expect(policy == .proxyNode(name: "proxy-a"))
    }

    @Test("resolvePolicy passes through non-group proxy nodes unchanged")
    func resolvePolicyPassesThrough() async throws {
        let healthChecker = HealthChecker()
        let config = RiptideConfig(
            mode: .rule,
            proxies: [
                ProxyNode(name: "direct-proxy", kind: .socks5, server: "1.2.3.4", port: 1080),
            ],
            rules: []
        )
        let resolver = ProxyGroupResolver(healthChecker: healthChecker, config: config)

        let policy = try await resolver.resolvePolicy(.proxyNode(name: "direct-proxy"))
        #expect(policy == .proxyNode(name: "direct-proxy"))
    }

    @Test("setSelectedProxy throws for unknown proxy")
    func setSelectedProxyThrowsForUnknownProxy() async throws {
        let healthChecker = HealthChecker()
        let config = RiptideConfig(
            mode: .rule,
            proxies: [
                ProxyNode(name: "proxy-a", kind: .socks5, server: "1.2.3.4", port: 1080),
            ],
            rules: [],
            proxyGroups: [
                ProxyGroup(id: "group-select", kind: .select, proxies: ["proxy-a"])
            ]
        )
        let resolver = ProxyGroupResolver(healthChecker: healthChecker, config: config)

        do {
            try await resolver.setSelectedProxy(forGroup: "group-select", proxyName: "nonexistent")
            Issue.record("Expected an error for nonexistent proxy")
        } catch ProxyGroupResolverError.unknownNode {
            // expected
        }
    }
}
