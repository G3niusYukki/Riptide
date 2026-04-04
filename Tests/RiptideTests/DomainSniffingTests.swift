import Foundation
import Testing

@testable import Riptide

@Suite("Domain Sniffing")
struct DomainSniffingTests {

    @Test("HTTPConnectRequestParser extracts sniffed domain from Host header")
    func extractsSniffedDomain() throws {
        // CONNECT request with different Host header (common in some proxy setups)
        let requestLines = [
            "CONNECT 198.18.0.1:443 HTTP/1.1",
            "Host: www.example.com:443",
            "User-Agent: curl/8.0",
            "",
            ""
        ]
        let request = requestLines.joined(separator: "\r\n")
        let data = Data(request.utf8)

        let parsed = try HTTPConnectRequestParser.parse(data)

        #expect(parsed.target.host == "198.18.0.1")
        #expect(parsed.target.port == 443)
        #expect(parsed.target.sniffedDomain == "www.example.com")
    }

    @Test("HTTPConnectRequestParser with matching Host header has no sniffed domain")
    func noSniffedDomainWhenMatching() throws {
        // When Host header matches CONNECT authority, no sniffed domain
        let requestLines = [
            "CONNECT www.example.com:443 HTTP/1.1",
            "Host: www.example.com:443",
            "",
            ""
        ]
        let request = requestLines.joined(separator: "\r\n")
        let data = Data(request.utf8)

        let parsed = try HTTPConnectRequestParser.parse(data)

        #expect(parsed.target.host == "www.example.com")
        #expect(parsed.target.port == 443)
        #expect(parsed.target.sniffedDomain == nil)
    }

    @Test("HTTPConnectRequestParser without Host header has no sniffed domain")
    func noSniffedDomainWithoutHeader() throws {
        let requestLines = [
            "CONNECT www.example.com:443 HTTP/1.1",
            "User-Agent: test",
            "",
            ""
        ]
        let request = requestLines.joined(separator: "\r\n")
        let data = Data(request.utf8)

        let parsed = try HTTPConnectRequestParser.parse(data)

        #expect(parsed.target.host == "www.example.com")
        #expect(parsed.target.sniffedDomain == nil)
    }

    @Test("ConnectionTarget stores sniffed domain correctly")
    func connectionTargetStoresSniffedDomain() {
        let target = ConnectionTarget(host: "10.0.0.1", port: 443, sniffedDomain: "api.example.com")

        #expect(target.host == "10.0.0.1")
        #expect(target.port == 443)
        #expect(target.sniffedDomain == "api.example.com")
    }

    @Test("ConnectionTarget without sniffed domain is nil")
    func connectionTargetWithoutSniffedDomain() {
        let target = ConnectionTarget(host: "example.com", port: 80)

        #expect(target.host == "example.com")
        #expect(target.port == 80)
        #expect(target.sniffedDomain == nil)
    }

    @Test("ConnectionTarget equality considers sniffed domain")
    func equalityConsidersSniffedDomain() {
        let target1 = ConnectionTarget(host: "10.0.0.1", port: 443, sniffedDomain: "example.com")
        let target2 = ConnectionTarget(host: "10.0.0.1", port: 443, sniffedDomain: "example.com")
        let target3 = ConnectionTarget(host: "10.0.0.1", port: 443, sniffedDomain: "other.com")
        let target4 = ConnectionTarget(host: "10.0.0.1", port: 443)

        #expect(target1 == target2)
        #expect(target1 != target3)
        #expect(target1 != target4)
    }
}
