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
        #expect(msg.answers[0].addressString == "93.18.77.10")
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
}
