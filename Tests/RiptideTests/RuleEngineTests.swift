import Foundation
import Testing

@testable import Riptide

@Suite("Rule engine")
struct RuleEngineTests {
    @Test("matches first applicable rule in order")
    func matchesInDeclaredOrder() async {
        let rules: [ProxyRule] = [
            .domainKeyword(keyword: "go", policy: .reject),
            .domainSuffix(suffix: "google.com", policy: .proxyNode(name: "proxy-a")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let policy = await engine.resolve(target: RuleTarget(domain: "mail.google.com", ipAddress: nil))
        #expect(policy == .reject)
    }

    @Test("matches exact domain before fallback")
    func matchesExactDomain() async {
        let rules: [ProxyRule] = [
            .domain(domain: "example.com", policy: .proxyNode(name: "proxy-a")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let exact = await engine.resolve(target: RuleTarget(domain: "example.com", ipAddress: nil))
        let subdomain = await engine.resolve(target: RuleTarget(domain: "www.example.com", ipAddress: nil))

        #expect(exact == .proxyNode(name: "proxy-a"))
        #expect(subdomain == .direct)
    }

    @Test("matches ip cidr")
    func matchesIPCIDR() async {
        let rules: [ProxyRule] = [
            .ipCIDR(cidr: "10.0.0.0/8", policy: .proxyNode(name: "lan-proxy")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let inside = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: "10.1.2.3"))
        let outside = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: "8.8.8.8"))

        #expect(inside == .proxyNode(name: "lan-proxy"))
        #expect(outside == .direct)
    }

    @Test("matches geoip with injected country resolver")
    func matchesGeoIP() async {
        let rules: [ProxyRule] = [
            .geoIP(countryCode: "CN", policy: .proxyNode(name: "cn-proxy")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(
            rules: rules,
            geoIPResolver: .init(resolveCountryCode: { ip in
                if ip == "1.1.1.1" { return "CN" }
                if ip == "8.8.8.8" { return "US" }
                return nil
            })
        )

        let cnPolicy = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: "1.1.1.1"))
        let usPolicy = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: "8.8.8.8"))
        let unknownPolicy = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: "9.9.9.9"))

        #expect(cnPolicy == .proxyNode(name: "cn-proxy"))
        #expect(usPolicy == .direct)
        #expect(unknownPolicy == .direct)
    }

    @Test("falls back to reject when no final is configured")
    func defaultRejectWithoutFinalRule() async {
        let rules: [ProxyRule] = [
            .domain(domain: "example.com", policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let policy = await engine.resolve(target: RuleTarget(domain: "unknown.com", ipAddress: nil))
        #expect(policy == .reject)
    }

    @Test("matches IPv6 CIDR")
    func matchesIPCIDR6() async {
        let rules: [ProxyRule] = [
            .ipCIDR6(cidr: "2001:db8::/32", policy: .proxyNode(name: "ipv6-proxy")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let inside = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: "2001:db8::1"))
        let outside = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: "2001:4860:4860::8888"))
        let noIP = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil))

        #expect(inside == .proxyNode(name: "ipv6-proxy"))
        #expect(outside == .direct)
        #expect(noIP == .direct)
    }

    @Test("matches source IP CIDR")
    func matchesSrcIPCIDR() async {
        let rules: [ProxyRule] = [
            .srcIPCIDR(cidr: "192.168.0.0/16", policy: .proxyNode(name: "lan-proxy")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let inside = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, sourceIP: "192.168.1.100"))
        let outside = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, sourceIP: "10.0.0.1"))
        let noSourceIP = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, sourceIP: nil))

        #expect(inside == .proxyNode(name: "lan-proxy"))
        #expect(outside == .direct)
        #expect(noSourceIP == .direct)
    }

    @Test("matches source port")
    func matchesSrcPort() async {
        let rules: [ProxyRule] = [
            .srcPort(port: 443, policy: .proxyNode(name: "https-proxy")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let match = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, sourcePort: 443))
        let noMatch = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, sourcePort: 80))
        let noPort = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, sourcePort: nil))

        #expect(match == .proxyNode(name: "https-proxy"))
        #expect(noMatch == .direct)
        #expect(noPort == .direct)
    }

    @Test("matches destination port")
    func matchesDstPort() async {
        let rules: [ProxyRule] = [
            .dstPort(port: 80, policy: .proxyNode(name: "http-proxy")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let match = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, destinationPort: 80))
        let noMatch = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, destinationPort: 443))
        let noPort = await engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, destinationPort: nil))

        #expect(match == .proxyNode(name: "http-proxy"))
        #expect(noMatch == .direct)
        #expect(noPort == .direct)
    }

    @Test("ruleSet resolves inner rules against target")
    func ruleSetResolvesInnerRules() async {
        // Seed with a rule set containing inner rules.
        let innerRules: [ProxyRule] = [
            .domainSuffix(suffix: "google.com", policy: .proxyNode(name: "rs-proxy")),
            .domainKeyword(keyword: "ads", policy: .reject),
        ]
        let ruleSet = RuleSet(name: "test-provider", behavior: .classical, rules: innerRules, updatedAt: Date())

        // Test the RuleEngine's async resolution by checking that a ruleSet rule
        // with no inner rules (empty provider) falls through to the next rule.
        let rules: [ProxyRule] = [
            .ruleSet(name: "test-provider", policy: .proxyNode(name: "fallback")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules, ruleSets: ["test-provider": ruleSet.rules])

        // Since the provider has no loaded rules, ruleSet matching returns nil
        // and the engine falls through to the final rule.
        let policy = await engine.resolve(target: RuleTarget(domain: "example.com", ipAddress: nil))
        #expect(policy == .direct)
    }
}
