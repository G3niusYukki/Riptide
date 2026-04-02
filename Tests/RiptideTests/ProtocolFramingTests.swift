import Foundation
import Testing

@testable import Riptide

@Suite("Protocol framing")
struct ProtocolFramingTests {
    @Test("HTTP CONNECT request is correctly framed")
    func httpConnectFraming() throws {
        let target = ConnectionTarget(host: "example.com", port: 443)
        let proto = HTTPConnectProtocol()

        let frames = try proto.makeConnectRequest(for: target)
        #expect(frames.count == 1)

        let request = String(data: frames[0], encoding: .utf8)
        #expect(request == "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n")
    }

    @Test("HTTP CONNECT parses success and reject responses")
    func httpConnectParsing() throws {
        let proto = HTTPConnectProtocol()

        let ok = try proto.parseConnectResponse(Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8))
        #expect(ok == .success)

        #expect(throws: ProtocolError.self) {
            _ = try proto.parseConnectResponse(Data("HTTP/1.1 403 Forbidden\r\n\r\n".utf8))
        }
    }

    @Test("SOCKS5 greeting and connect frames are correctly built")
    func socks5Framing() throws {
        let target = ConnectionTarget(host: "example.com", port: 443)
        let proto = SOCKS5Protocol()

        let frames = try proto.makeConnectRequest(for: target)
        #expect(frames.count == 2)
        #expect(frames[0] == Data([0x05, 0x01, 0x00]))

        let expectedConnect = Data([
            0x05, 0x01, 0x00, 0x03, 0x0B,
            0x65, 0x78, 0x61, 0x6D, 0x70, 0x6C, 0x65, 0x2E, 0x63, 0x6F, 0x6D,
            0x01, 0xBB,
        ])
        #expect(frames[1] == expectedConnect)
    }

    @Test("SOCKS5 parser accepts no-auth and success reply")
    func socks5ParsingSuccess() throws {
        let proto = SOCKS5Protocol()
        try proto.parseMethodSelection(Data([0x05, 0x00]))

        let reply = Data([0x05, 0x00, 0x00, 0x01, 127, 0, 0, 1, 0x1F, 0x90])
        let result = try proto.parseConnectResponse(reply)
        #expect(result == .success)
    }

    @Test("Shadowsocks target preamble encodes domain and IPv4")
    func shadowsocksTargetEncoding() throws {
        let proto = ShadowsocksProtocol()

        let domainTarget = ConnectionTarget(host: "example.com", port: 80)
        let domainData = try proto.makeConnectRequest(for: domainTarget)
        #expect(domainData.count == 1)
        #expect(domainData[0] == Data([
            0x03, 0x0B,
            0x65, 0x78, 0x61, 0x6D, 0x70, 0x6C, 0x65, 0x2E, 0x63, 0x6F, 0x6D,
            0x00, 0x50,
        ]))

        let ipv4Target = ConnectionTarget(host: "1.2.3.4", port: 53)
        let ipv4Data = try proto.makeConnectRequest(for: ipv4Target)
        #expect(ipv4Data[0] == Data([0x01, 0x01, 0x02, 0x03, 0x04, 0x00, 0x35]))
    }
}
