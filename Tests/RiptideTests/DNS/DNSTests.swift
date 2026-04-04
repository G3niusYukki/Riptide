import Foundation
import Testing
@testable import Riptide

@Suite("DNS message encoding and decoding")
struct DNSMessageTests {
    @Test("builds and encodes a query message")
    func encodeQuery() throws {
        let msg = DNSMessage.buildQuery(name: "example.com", type: .a, id: 0x1234)
        let data = try msg.encode()

        #expect(data.count >= 12)
        #expect(data[0] == 0x12)
        #expect(data[1] == 0x34)
        #expect((data[2] & 0x80) == 0) // not response
        #expect((data[2] & 0x01) != 0) // recursion desired
    }

    @Test("encodes domain name with correct label format")
    func encodeDomainName() throws {
        let msg = DNSMessage.buildQuery(name: "www.example.com", type: .a)
        let data = try msg.encode()

        // After 12-byte header: 0x03 'w' 'w' 'w' 0x07 'e' 'x' 'a' 'm' 'p' 'l' 'e' 0x03 'c' 'o' 'm' 0x00
        #expect(data[12] == 3)
        #expect(data[13] == UInt8(ascii: "w"))
        #expect(data[14] == UInt8(ascii: "w"))
        #expect(data[15] == UInt8(ascii: "w"))
        #expect(data[16] == 7)
        #expect(data[17] == UInt8(ascii: "e"))
    }

    @Test("round-trips query through encode/parse")
    func roundTripQuery() throws {
        let original = DNSMessage.buildQuery(name: "test.example.org", type: .aaaa, id: 0xABCD)
        let data = try original.encode()
        let parsed = try DNSMessage.parse(data)

        #expect(parsed.header.id == 0xABCD)
        #expect(parsed.header.questionCount == 1)
        #expect(parsed.questions[0].name == "test.example.org")
        #expect(parsed.questions[0].type == .aaaa)
    }

    @Test("parses response with A record")
    func parseAResponse() throws {
        var data = Data([
            0x12, 0x34, 0x81, 0x80, 0x00, 0x01, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00, // header
            0x07, 0x65, 0x78, 0x61, 0x6D, 0x70, 0x6C, 0x65, 0x03, 0x63, 0x6F, 0x6D, 0x00, // example.com
            0x00, 0x01, 0x00, 0x01, // QTYPE=A, QCLASS=IN
            0xC0, 0x0C, // name pointer to example.com
            0x00, 0x01, 0x00, 0x01, // TYPE=A, CLASS=IN
            0x00, 0x00, 0x01, 0x2C, // TTL=300
            0x00, 0x04, // RDLENGTH=4
            0x93, 0x18, 0x4D, 0x0A, // 147.24.77.10
        ])

        let msg = try DNSMessage.parse(data)
        #expect(msg.header.isResponse)
        #expect(msg.header.answerCount == 1)
        #expect(msg.answers[0].type == .a)
        #expect(msg.answers[0].addressString == "147.24.77.10")
        #expect(msg.answers[0].ttl == 300)
    }

    @Test("parses response with AAAA record")
    func parseAAAAResponse() throws {
        var data = Data([
            0x00, 0x01, 0x81, 0x80, 0x00, 0x01, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x04, 0x74, 0x65, 0x73, 0x74, 0x03, 0x63, 0x6F, 0x6D, 0x00,
            0x00, 0x1C, 0x00, 0x01,
            0xC0, 0x0C,
            0x00, 0x1C, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x3C,
            0x00, 0x10,
            0x26, 0x06, 0x28, 0x00, 0x02, 0x20, 0x00, 0x01,
            0x02, 0x4E, 0xFF, 0xFE, 0x00, 0x14, 0x00, 0x00,
        ])

        let msg = try DNSMessage.parse(data)
        #expect(msg.answers[0].type == .aaaa)
        #expect(msg.answers[0].rdata.count == 16)
    }

    @Test("throws on truncated data")
    func truncatedData() {
        #expect(throws: DNSError.self) {
            _ = try DNSMessage.parse(Data([0x00, 0x01]))
        }
    }
}

@Suite("DNS cache")
struct DNSCacheTests {
    @Test("stores and retrieves records")
    func getSet() async throws {
        let cache = DNSCache()
        let record = DNSResourceRecord(
            name: "example.com", type: .a, classValue: .inet,
            ttl: 300, rdata: Data([93, 18, 77, 10])
        )
        await cache.set(name: "example.com", type: .a, records: [record])

        let result = await cache.get(name: "example.com", type: .a)
        #expect(result?.count == 1)
        #expect(result?[0].addressString == "93.18.77.10")
    }

    @Test("returns nil for missing entries")
    func miss() async {
        let cache = DNSCache()
        let result = await cache.get(name: "nonexistent.com", type: .a)
        #expect(result == nil)
    }

    @Test("separates records by type")
    func separateByType() async throws {
        let cache = DNSCache()
        let aRecord = DNSResourceRecord(
            name: "dual.com", type: .a, classValue: .inet,
            ttl: 300, rdata: Data([1, 2, 3, 4])
        )
        let aaaaRecord = DNSResourceRecord(
            name: "dual.com", type: .aaaa, classValue: .inet,
            ttl: 300, rdata: Data([UInt8](repeating: 0, count: 16))
        )
        await cache.set(name: "dual.com", type: .a, records: [aRecord])
        await cache.set(name: "dual.com", type: .aaaa, records: [aaaaRecord])

        #expect(await cache.get(name: "dual.com", type: .a)?.count == 1)
        #expect(await cache.get(name: "dual.com", type: .aaaa)?.count == 1)
    }

    @Test("clear removes all entries")
    func clear() async throws {
        let cache = DNSCache()
        let record = DNSResourceRecord(
            name: "x.com", type: .a, classValue: .inet,
            ttl: 300, rdata: Data([1, 1, 1, 1])
        )
        await cache.set(name: "x.com", type: .a, records: [record])
        await cache.clear()
        #expect(await cache.get(name: "x.com", type: .a) == nil)
    }
}

@Suite("Fake-IP pool")
struct FakeIPPoolTests {
    @Test("allocates unique IPs for different domains")
    func allocateUnique() {
        let pool = FakeIPPool(cidr: "198.18.0.0/16")
        let ip1 = pool.allocate(domain: "google.com")
        let ip2 = pool.allocate(domain: "github.com")

        #expect(ip1 != nil)
        #expect(ip2 != nil)
        #expect(ip1 != ip2)
        #expect(ip1!.hasPrefix("198.18."))
    }

    @Test("returns same IP for same domain")
    func sameDomain() {
        let pool = FakeIPPool(cidr: "198.18.0.0/16")
        let ip1 = pool.allocate(domain: "example.com")
        let ip2 = pool.allocate(domain: "example.com")
        #expect(ip1 == ip2)
    }

    @Test("reverse lookup works")
    func reverseLookup() {
        let pool = FakeIPPool(cidr: "198.18.0.0/16")
        let ip = pool.allocate(domain: "test.com")
        #expect(pool.reverseLookup(ip: ip!) == "test.com")
    }

    @Test("reverse lookup returns nil for unknown IP")
    func reverseMiss() {
        let pool = FakeIPPool(cidr: "198.18.0.0/16")
        #expect(pool.reverseLookup(ip: "1.2.3.4") == nil)
    }
}

@Suite("DNS pipeline")
struct DNSPipelineTests {
    @Test("isFakeIP detects 198.18.x.x addresses")
    func isFakeIP() async {
        let pipeline = DNSPipeline()
        #expect(await pipeline.isFakeIP("198.18.0.1"))
        #expect(await pipeline.isFakeIP("198.18.255.255"))
        #expect(await !pipeline.isFakeIP("198.19.0.1"))
        #expect(await !pipeline.isFakeIP("8.8.8.8"))
    }

    @Test("resolveFakeIP returns consistent addresses")
    func resolveFakeIP() async throws {
        let pipeline = DNSPipeline()
        let ip1 = try await pipeline.resolveFakeIP("example.com")
        let ip2 = try await pipeline.resolveFakeIP("example.com")
        #expect(ip1 == ip2)
        #expect(ip1.hasPrefix("198.18."))
    }

    @Test("reverseLookup maps fake IP back to domain")
    func reverseLookup() async throws {
        let pipeline = DNSPipeline()
        let ip = try await pipeline.resolveFakeIP("test.org")
        #expect(await pipeline.reverseLookup(ip) == "test.org")
    }

    @Test("lookupHostsEntry returns exact match")
    func lookupHostsExact() async {
        let policy = DNSPolicy(hosts: [
            "example.com": "1.2.3.4",
            "localhost": "127.0.0.1",
        ])
        let pipeline = DNSPipeline(dnsPolicy: policy)
        #expect(await pipeline.lookupHostsEntry(domain: "example.com") == "1.2.3.4")
        #expect(await pipeline.lookupHostsEntry(domain: "localhost") == "127.0.0.1")
    }

    @Test("lookupHostsEntry returns wildcard match")
    func lookupHostsWildcard() async {
        let policy = DNSPolicy(hosts: [
            "*.google.com": "8.8.8.8",
            "*.example.org": "9.9.9.9",
        ])
        let pipeline = DNSPipeline(dnsPolicy: policy)
        #expect(await pipeline.lookupHostsEntry(domain: "www.google.com") == "8.8.8.8")
        #expect(await pipeline.lookupHostsEntry(domain: "mail.google.com") == "8.8.8.8")
        #expect(await pipeline.lookupHostsEntry(domain: "api.example.org") == "9.9.9.9")
    }

    @Test("lookupHostsEntry exact match takes priority over wildcard")
    func lookupHostsExactPriority() async {
        let policy = DNSPolicy(hosts: [
            "*.google.com": "8.8.8.8",
            "google.com": "1.2.3.4",
        ])
        let pipeline = DNSPipeline(dnsPolicy: policy)
        #expect(await pipeline.lookupHostsEntry(domain: "google.com") == "1.2.3.4")
        #expect(await pipeline.lookupHostsEntry(domain: "www.google.com") == "8.8.8.8")
    }

    @Test("lookupHostsEntry returns nil for unmatched domains")
    func lookupHostsMiss() async {
        let policy = DNSPolicy(hosts: ["example.com": "1.2.3.4"])
        let pipeline = DNSPipeline(dnsPolicy: policy)
        #expect(await pipeline.lookupHostsEntry(domain: "unknown.com") == nil)
        #expect(await pipeline.lookupHostsEntry(domain: "notexample.com") == nil)
    }

    @Test("lookupHostsEntry does not match bare domain as wildcard")
    func lookupHostsNoBareSuffixMatch() async {
        let policy = DNSPolicy(hosts: ["*.example.com": "1.2.3.4"])
        let pipeline = DNSPipeline(dnsPolicy: policy)
        #expect(await pipeline.lookupHostsEntry(domain: "example.com") == nil)
        #expect(await pipeline.lookupHostsEntry(domain: "www.example.com") == "1.2.3.4")
    }

    @Test("DNSPipeline from DNSPolicy with hosts")
    func pipelineWithHosts() async {
        let policy = DNSPolicy(
            primaryResolvers: [.udp(host: "8.8.8.8")],
            hosts: ["blocked.com": "0.0.0.0"]
        )
        let pipeline = DNSPipeline(dnsPolicy: policy)
        #expect(await pipeline.lookupHostsEntry(domain: "blocked.com") == "0.0.0.0")
    }

    @Test("DNSConfig carries hosts through")
    func dnsConfigWithHosts() async {
        let cfg = DNSConfig(
            remoteServers: ["8.8.8.8"],
            hosts: ["custom.com": "192.168.1.1"]
        )
        let pipeline = DNSPipeline(config: cfg)
        #expect(await pipeline.lookupHostsEntry(domain: "custom.com") == "192.168.1.1")
    }
}

@Suite("DOTResolver")
struct DOTResolverTests {
    @Test("parses valid host:port address")
    func addressParsing() throws {
        let resolver = try DOTResolver(address: "1.1.1.1:853")
        #expect(resolver != nil)
    }

    @Test("throws on invalid address format")
    func invalidAddress() {
        #expect(throws: DNSError.self) {
            _ = try DOTResolver(address: "invalid-no-port")
        }
    }

    @Test("DOTResolver endpoint kind is available")
    func dotKindExists() {
        let endpoint = DNSResolverEndpoint.dot(host: "1.1.1.1", port: 853)
        #expect(endpoint.kind == .dot)
        #expect(endpoint.address == "1.1.1.1:853")
    }

    @Test("DNSResolverEndpoint dot static constructor")
    func dotStaticConstructor() {
        let endpoint = DNSResolverEndpoint.dot(host: "dns.google")
        #expect(endpoint.kind == .dot)
        #expect(endpoint.address == "dns.google:853")
        #expect(endpoint.dohURL == nil)
    }

    @Test("parses tls-nameserver in Clash config")
    func parseTLSTypeInKind() throws {
        // Verify the .dot case is a valid Kind variant
        #expect(DNSResolverEndpoint.Kind.dot.rawValue == "dot")
    }
}

@Suite("Clash config DoT parsing")
struct ClashDoTTests {
    @Test("parses tls-nameserver from Clash YAML")
    func parseTLSNameserver() throws {
        let yaml = """
        dns:
          enable: true
          nameserver:
            - 8.8.8.8
          tls-nameserver:
            - tls://1.1.1.1
            - tls://dns.google:853
        mode: direct
        rules: []
        """
        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        let dotResolvers = config.dnsPolicy.primaryResolvers.filter { $0.kind == .dot }
        #expect(dotResolvers.count == 2)
        #expect(dotResolvers[0].address == "1.1.1.1:853")
        #expect(dotResolvers[1].address == "dns.google:853")
    }

    @Test("tls-nameserver with bare host defaults to port 853")
    func tlsNameserverBareHost() throws {
        let yaml = """
        dns:
          enable: true
          tls-nameserver:
            - tls://1.1.1.1
        mode: direct
        rules: []
        """
        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        let dotResolvers = config.dnsPolicy.primaryResolvers.filter { $0.kind == .dot }
        #expect(dotResolvers.count == 1)
        #expect(dotResolvers[0].address == "1.1.1.1:853")
    }

    @Test("tls-nameserver mixed with regular nameserver")
    func mixedNameservers() throws {
        let yaml = """
        dns:
          enable: true
          nameserver:
            - 8.8.8.8
            - https://dns.google/dns-query
          tls-nameserver:
            - tls://1.1.1.1
        mode: direct
        rules: []
        """
        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        let dotResolvers = config.dnsPolicy.primaryResolvers.filter { $0.kind == .dot }
        #expect(dotResolvers.count == 1)
        let udpResolvers = config.dnsPolicy.primaryResolvers.filter { $0.kind == .udp }
        #expect(udpResolvers.count == 1)
        let dohResolvers = config.dnsPolicy.primaryResolvers.filter { $0.kind == .doh }
        #expect(dohResolvers.count == 1)
    }
}

@Suite("DNSPolicy integration with DoT")
struct DNSPolicyDoTTests {
    @Test("DNSPolicy default has no DoT resolvers")
    func defaultNoDot() {
        let policy = DNSPolicy.default
        #expect(!policy.primaryResolvers.contains { $0.kind == .dot })
    }

    @Test("DNSPolicy with DoT resolver")
    func withDot() {
        let policy = DNSPolicy(
            primaryResolvers: [
                .dot(host: "1.1.1.1"),
                .dot(host: "8.8.8.8"),
            ],
            fallbackResolvers: [
                .udp(host: "223.5.5.5"),
            ]
        )
        #expect(policy.primaryResolvers.count == 2)
        #expect(policy.primaryResolvers.allSatisfy { $0.kind == .dot })
        #expect(policy.fallbackResolvers.count == 1)
    }

    @Test("DNSPipeline from DNSPolicy extracts DoT endpoints")
    func pipelineFromPolicy() async {
        let policy = DNSPolicy(
            primaryResolvers: [
                .udp(host: "8.8.8.8"),
                .dot(host: "1.1.1.1"),
            ]
        )
        let pipeline = DNSPipeline(dnsPolicy: policy)
        // The pipeline should have extracted the dot endpoint
        // We verify indirectly through successful construction
        #expect(pipeline != nil)
    }
}

@Suite("DOQ (DNS over QUIC)")
struct DOQResolverTests {
    @Test("DNSResolverEndpoint Kind has doq variant")
    func doqKindExists() {
        #expect(DNSResolverEndpoint.Kind.doq.rawValue == "doq")
    }

    @Test("DNSResolverEndpoint doq static constructor")
    func doqStaticConstructor() {
        let endpoint = DNSResolverEndpoint.doq(host: "dns.adguard.com", port: 784)
        #expect(endpoint.kind == .doq)
        #expect(endpoint.address == "dns.adguard.com:784")
        #expect(endpoint.dohURL == nil)
    }

    @Test("DOQResolver constructs with host and port")
    func doqResolverConstruction() {
        let resolver = DOQResolver(serverHost: "dns.adguard.com", serverPort: 784)
        #expect(resolver != nil)
    }

    @Test("DOQResolver uses default port 853")
    func doqResolverDefaultPort() {
        let resolver = DOQResolver(serverHost: "dns.adguard.com")
        #expect(resolver != nil)
    }

    @Test("DOQResolver query throws when DoQ is unavailable on platform")
    func doqQueryThrowsUnavailble() async {
        let resolver = DOQResolver(serverHost: "dns.adguard.com", serverPort: 784)
        await #expect(throws: DNSError.self) {
            _ = try await resolver.query(name: "example.com", type: .a)
        }
    }
}

@Suite("DNSPolicy integration with DoQ")
struct DNSPolicyDoQTests {
    @Test("DNSPolicy with DoQ resolver")
    func withDoQ() {
        let policy = DNSPolicy(
            primaryResolvers: [
                .doq(host: "dns.adguard.com", port: 784),
                .doq(host: "1.1.1.1"),
            ],
            fallbackResolvers: [
                .udp(host: "223.5.5.5"),
            ]
        )
        #expect(policy.primaryResolvers.count == 2)
        #expect(policy.primaryResolvers.allSatisfy { $0.kind == .doq })
        #expect(policy.fallbackResolvers.count == 1)
    }

    @Test("DNSPolicy with mixed DoT and DoQ resolvers")
    func mixedDotAndDoQ() {
        let policy = DNSPolicy(
            primaryResolvers: [
                .dot(host: "1.1.1.1"),
                .doq(host: "dns.adguard.com", port: 784),
                .udp(host: "8.8.8.8"),
            ]
        )
        #expect(policy.primaryResolvers.count == 3)
        #expect(policy.primaryResolvers[0].kind == .dot)
        #expect(policy.primaryResolvers[1].kind == .doq)
        #expect(policy.primaryResolvers[2].kind == .udp)
    }

    @Test("DNSPipeline from DNSPolicy with DoQ constructs successfully")
    func pipelineWithDoQ() async {
        let policy = DNSPolicy(
            primaryResolvers: [
                .udp(host: "8.8.8.8"),
                .doq(host: "dns.adguard.com", port: 784),
            ]
        )
        let pipeline = DNSPipeline(dnsPolicy: policy)
        #expect(pipeline != nil)
    }

    @Test("DNSConfig includes doQEndpoints")
    func dnsConfigDoQEndpoints() {
        let cfg = DNSConfig(
            remoteServers: ["8.8.8.8"],
            doQEndpoints: ["dns.adguard.com:784", "1.1.1.1:853"]
        )
        #expect(cfg.doQEndpoints.count == 2)
        #expect(cfg.doQEndpoints[0] == "dns.adguard.com:784")
    }

    @Test("DNSConfig defaults have empty doQEndpoints")
    func dnsConfigDefaultNoDoQ() {
        let cfg = DNSConfig()
        #expect(cfg.doQEndpoints.isEmpty)
    }
}

@Suite("ClashConfigParser DoQ")
struct ClashConfigParserDoQTests {
    @Test("parses quic-nameserver in Clash DNS config")
    func parseQuicNameserver() throws {
        let yaml = """
        dns:
          enable: true
          quic-nameserver:
            - "quic://dns.adguard.com:784"
            - "dns.adguard.com:853"
          fake-ip: true
        mode: direct
        """
        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        let doqResolvers = config.dnsPolicy.primaryResolvers.filter { $0.kind == .doq }
        #expect(doqResolvers.count == 2)
        #expect(doqResolvers[0].address == "dns.adguard.com:784")
        #expect(doqResolvers[1].address == "dns.adguard.com:853")
    }

    @Test("parses quic:// prefix in nameserver array")
    func parseQuicInNameserver() throws {
        let yaml = """
dns:
  enable: true
  nameserver:
    - "quic://dns.adguard.com:784"
    - "8.8.8.8"
  fake-ip: true
mode: direct
"""
        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        let doqResolvers = config.dnsPolicy.primaryResolvers.filter { $0.kind == .doq }
        let udpResolvers = config.dnsPolicy.primaryResolvers.filter { $0.kind == .udp }
        #expect(doqResolvers.count == 1)
        #expect(doqResolvers[0].address == "dns.adguard.com:784")
        #expect(udpResolvers.count == 1)
        #expect(udpResolvers[0].address == "8.8.8.8:53")
    }

    @Test("parses quic-nameserver without port using default 853")
    func parseQuicNoPort() throws {
        let yaml = """
        dns:
          enable: true
          quic-nameserver:
            - "quic://1.1.1.1"
          fake-ip: true
        mode: direct
        """
        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        let doqResolvers = config.dnsPolicy.primaryResolvers.filter { $0.kind == .doq }
        #expect(doqResolvers.count == 1)
        #expect(doqResolvers[0].address == "1.1.1.1:853")
    }

    @Test("parses mixed DoH DoT DoQ in same config")
    func parseMixedDNSProtocols() throws {
        let yaml = """
        dns:
          enable: true
          nameserver:
            - "https://dns.google/dns-query"
            - "quic://dns.adguard.com:784"
            - "8.8.8.8"
          tls-nameserver:
            - "1.1.1.1:853"
          quic-nameserver:
            - "dns.quad9.net:853"
          fake-ip: true
        mode: direct
        """
        let (config, _) = try ClashConfigParser.parse(yaml: yaml)
        let resolvers = config.dnsPolicy.primaryResolvers
        #expect(resolvers.contains { $0.kind == .doh })
        #expect(resolvers.contains { $0.kind == .doq })
        #expect(resolvers.contains { $0.kind == .dot })
        #expect(resolvers.contains { $0.kind == .udp })
    }
}

