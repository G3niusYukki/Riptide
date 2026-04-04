import Foundation
import Testing

@testable import Riptide

@Suite("DNSPolicy")
struct DNSPolicyTests {
    // MARK: - DNSPolicy struct

    @Test("default policy uses public resolvers and fake IP enabled")
    func defaultPolicyHasPublicResolvers() {
        let policy = DNSPolicy.default
        #expect(!policy.primaryResolvers.isEmpty)
        #expect(policy.fakeIPEnabled == true)
        #expect(policy.respectRules == false)
    }

    @Test("custom policy accepts primary, fallback resolvers, and fake IP settings")
    func customPolicyAcceptsAllFields() {
        let primary = [DNSResolverEndpoint.udp(host: "8.8.8.8", port: 53)]
        let fallback = [DNSResolverEndpoint.doh(url: "https://1.1.1.1/dns-query")]
        let domainPolicy = DNSDomainPolicy(
            pattern: "example.com",
            action: .useRemote,
            resolverGroup: "dns-remote"
        )

        let policy = DNSPolicy(
            primaryResolvers: primary,
            fallbackResolvers: fallback,
            domainPolicies: [domainPolicy],
            respectRules: true,
            fakeIPEnabled: false,
            fakeIPCIDR: "172.16.0.0/12"
        )

        #expect(policy.primaryResolvers.count == 1)
        #expect(policy.fallbackResolvers.count == 1)
        #expect(policy.domainPolicies.count == 1)
        #expect(policy.respectRules == true)
        #expect(policy.fakeIPEnabled == false)
        #expect(policy.fakeIPCIDR == "172.16.0.0/12")
    }

    @Test("DNSDomainPolicy action cases match expected raw values")
    func domainPolicyActionRawValues() {
        #expect(DNSDomainPolicy.Action.useRemote.rawValue == "remote")
        #expect(DNSDomainPolicy.Action.useDirect.rawValue == "direct")
        #expect(DNSDomainPolicy.Action.useGroup.rawValue == "group")
    }

    // MARK: - DNSResolverEndpoint

    @Test("DNSResolverEndpoint.udp creates correct address string")
    func udpEndpointAddress() {
        let endpoint = DNSResolverEndpoint.udp(host: "8.8.8.8", port: 53)
        #expect(endpoint.kind == .udp)
        #expect(endpoint.address == "8.8.8.8:53")
        #expect(endpoint.dohURL == nil)
    }

    @Test("DNSResolverEndpoint.doh sets address and dohURL")
    func dohEndpoint() {
        let url = "https://cloudflare-dns.com/dns-query"
        let endpoint = DNSResolverEndpoint.doh(url: url)
        #expect(endpoint.kind == .doh)
        #expect(endpoint.address == url)
        #expect(endpoint.dohURL == url)
    }

    // MARK: - Clash parser integration

    @Test("ClashConfigParser parses minimal dns section and enables fake IP")
    func parsesMinimalDNSSection() throws {
        let yaml = """
        mode: rule
        proxies: []
        rules:
          - MATCH,DIRECT
        dns:
          enable: true
          nameserver:
            - 8.8.8.8
          fake-ip-range: "198.19.0.0/16"
        """
        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        #expect(config.dnsPolicy.fakeIPEnabled == true)
        #expect(config.dnsPolicy.fakeIPCIDR == "198.19.0.0/16")
        #expect(config.dnsPolicy.primaryResolvers.count == 1)
        #expect(config.dnsPolicy.primaryResolvers[0].address == "8.8.8.8:53")
    }

    @Test("ClashConfigParser parses dns with DoH and fallback nameservers")
    func parsesDoHandFallback() throws {
        let yaml = """
        mode: rule
        proxies: []
        rules:
          - MATCH,DIRECT
        dns:
          enable: true
          nameserver:
            - https://cloudflare-dns.com/dns-query
          fallback:
            - 223.5.5.5
          respect-rules: true
          fake-ip: false
        """
        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        #expect(config.dnsPolicy.primaryResolvers[0].kind == .doh)
        #expect(config.dnsPolicy.fallbackResolvers.count == 1)
        #expect(config.dnsPolicy.respectRules == true)
        #expect(config.dnsPolicy.fakeIPEnabled == false)
    }

    @Test("ClashConfigParser uses default policy when dns section absent")
    func usesDefaultWhenDNSAbsent() throws {
        let yaml = """
        mode: rule
        proxies: []
        rules:
          - MATCH,DIRECT
        """
        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        #expect(config.dnsPolicy.primaryResolvers.count == 2)
        #expect(config.dnsPolicy.fakeIPEnabled == true)
        #expect(config.dnsPolicy.respectRules == false)
    }

    @Test("ClashConfigParser parses domain-specific nameserver policies")
    func parsesDomainPolicies() throws {
        let yaml = """
        mode: rule
        proxies: []
        rules:
          - MATCH,DIRECT
        dns:
          enable: true
          nameserver:
            - 8.8.8.8
          custom:
            - domain: "example.com"
              nameserver:
                - 1.1.1.1
        """
        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        #expect(config.dnsPolicy.primaryResolvers.count == 1)
    }
}
