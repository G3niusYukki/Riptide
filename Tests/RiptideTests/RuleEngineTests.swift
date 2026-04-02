import Testing

@testable import Riptide

@Suite("Rule engine")
struct RuleEngineTests {
    @Test("matches first applicable rule in order")
    func matchesInDeclaredOrder() {
        let rules: [ProxyRule] = [
            .domainKeyword(keyword: "go", policy: .reject),
            .domainSuffix(suffix: "google.com", policy: .proxyNode(name: "proxy-a")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let policy = engine.resolve(target: RuleTarget(domain: "mail.google.com", ipAddress: nil))
        #expect(policy == .reject)
    }

    @Test("matches exact domain before fallback")
    func matchesExactDomain() {
        let rules: [ProxyRule] = [
            .domain(domain: "example.com", policy: .proxyNode(name: "proxy-a")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let exact = engine.resolve(target: RuleTarget(domain: "example.com", ipAddress: nil))
        let subdomain = engine.resolve(target: RuleTarget(domain: "www.example.com", ipAddress: nil))

        #expect(exact == .proxyNode(name: "proxy-a"))
        #expect(subdomain == .direct)
    }

    @Test("matches ip cidr")
    func matchesIPCIDR() {
        let rules: [ProxyRule] = [
            .ipCIDR(cidr: "10.0.0.0/8", policy: .proxyNode(name: "lan-proxy")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let inside = engine.resolve(target: RuleTarget(domain: nil, ipAddress: "10.1.2.3"))
        let outside = engine.resolve(target: RuleTarget(domain: nil, ipAddress: "8.8.8.8"))

        #expect(inside == .proxyNode(name: "lan-proxy"))
        #expect(outside == .direct)
    }

    @Test("falls back to reject when no final is configured")
    func defaultRejectWithoutFinalRule() {
        let rules: [ProxyRule] = [
            .domain(domain: "example.com", policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let policy = engine.resolve(target: RuleTarget(domain: "unknown.com", ipAddress: nil))
        #expect(policy == .reject)
    }
}
