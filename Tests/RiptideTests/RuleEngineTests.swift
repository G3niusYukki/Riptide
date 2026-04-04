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

    @Test("matches geoip with injected country resolver")
    func matchesGeoIP() {
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

        let cnPolicy = engine.resolve(target: RuleTarget(domain: nil, ipAddress: "1.1.1.1"))
        let usPolicy = engine.resolve(target: RuleTarget(domain: nil, ipAddress: "8.8.8.8"))
        let unknownPolicy = engine.resolve(target: RuleTarget(domain: nil, ipAddress: "9.9.9.9"))

        #expect(cnPolicy == .proxyNode(name: "cn-proxy"))
        #expect(usPolicy == .direct)
        #expect(unknownPolicy == .direct)
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

    @Test("matches IPv6 CIDR")
    func matchesIPCIDR6() {
        let rules: [ProxyRule] = [
            .ipCIDR6(cidr: "2001:db8::/32", policy: .proxyNode(name: "ipv6-proxy")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let inside = engine.resolve(target: RuleTarget(domain: nil, ipAddress: "2001:db8::1"))
        let outside = engine.resolve(target: RuleTarget(domain: nil, ipAddress: "2001:4860:4860::8888"))
        let noIP = engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil))

        #expect(inside == .proxyNode(name: "ipv6-proxy"))
        #expect(outside == .direct)
        #expect(noIP == .direct)
    }

    @Test("matches source IP CIDR")
    func matchesSrcIPCIDR() {
        let rules: [ProxyRule] = [
            .srcIPCIDR(cidr: "192.168.0.0/16", policy: .proxyNode(name: "lan-proxy")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let inside = engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, sourceIP: "192.168.1.100"))
        let outside = engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, sourceIP: "10.0.0.1"))
        let noSourceIP = engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, sourceIP: nil))

        #expect(inside == .proxyNode(name: "lan-proxy"))
        #expect(outside == .direct)
        #expect(noSourceIP == .direct)
    }

    @Test("matches source port")
    func matchesSrcPort() {
        let rules: [ProxyRule] = [
            .srcPort(port: 443, policy: .proxyNode(name: "https-proxy")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let match = engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, sourcePort: 443))
        let noMatch = engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, sourcePort: 80))
        let noPort = engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, sourcePort: nil))

        #expect(match == .proxyNode(name: "https-proxy"))
        #expect(noMatch == .direct)
        #expect(noPort == .direct)
    }

    @Test("matches destination port")
    func matchesDstPort() {
        let rules: [ProxyRule] = [
            .dstPort(port: 80, policy: .proxyNode(name: "http-proxy")),
            .final(policy: .direct),
        ]
        let engine = RuleEngine(rules: rules)

        let match = engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, destinationPort: 80))
        let noMatch = engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, destinationPort: 443))
        let noPort = engine.resolve(target: RuleTarget(domain: nil, ipAddress: nil, destinationPort: nil))

        #expect(match == .proxyNode(name: "http-proxy"))
        #expect(noMatch == .direct)
        #expect(noPort == .direct)
    }
}
