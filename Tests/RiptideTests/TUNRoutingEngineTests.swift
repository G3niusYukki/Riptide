import XCTest
@testable import Riptide

/// Tests for TUN routing engine types: error enums, stats, configuration,
/// and packet handler static methods.
final class TUNRoutingEngineTests: XCTestCase {

    // MARK: - TunnelError

    func testTunnelErrorEquatable() {
        XCTAssertEqual(TunnelError.sessionLimitReached, TunnelError.sessionLimitReached)
        XCTAssertEqual(TunnelError.connectionFailed("a"), TunnelError.connectionFailed("a"))
        XCTAssertNotEqual(TunnelError.sessionLimitReached, TunnelError.connectionNotFound)
        XCTAssertNotEqual(TunnelError.connectionFailed("a"), TunnelError.connectionFailed("b"))
    }

    func testTunnelErrorLocalizedDescription() {
        let cases: [TunnelError] = [
            .sessionLimitReached,
            .connectionNotFound,
            .connectionFailed("test"),
            .invalidPacket,
            .routingFailed("test"),
            .dnsResolutionFailed("test"),
            .proxyError("test"),
            .packetFlowNotAvailable,
        ]
        for error in cases {
            XCTAssertFalse(error.localizedDescription.isEmpty,
                "Expected non-empty description for \(error)")
        }
    }

    // MARK: - TUNRoutingEngineError

    func testTUNRoutingEngineErrorEquatable() {
        XCTAssertEqual(
            TUNRoutingEngineError.parseError("bad"),
            TUNRoutingEngineError.parseError("bad")
        )
        XCTAssertNotEqual(
            TUNRoutingEngineError.parseError("a"),
            TUNRoutingEngineError.parseError("b")
        )
        XCTAssertNotEqual(
            TUNRoutingEngineError.sessionLimitReached,
            TUNRoutingEngineError.parseError("x")
        )
    }

    func testTUNRoutingEngineErrorLocalizedDescription() {
        let cases: [TUNRoutingEngineError] = [
            .parseError("bad packet"),
            .sessionLimitReached,
            .connectionFailed("timeout"),
            .routingFailed("no route"),
            .dnsResolutionFailed("no dns"),
            .proxyError("refused"),
            .tcpStateError("invalid"),
            .udpSessionError("expired"),
        ]
        for error in cases {
            XCTAssertFalse(error.localizedDescription.isEmpty,
                "Expected non-empty description for \(error)")
        }
    }

    // MARK: - VPNConfiguration

    func testVPNConfigurationDefaults() {
        let config = VPNConfiguration()
        XCTAssertEqual(config.tunnelAddress, "198.18.0.1")
        XCTAssertEqual(config.tunnelSubnetMask, "255.255.0.0")
        XCTAssertEqual(config.tunnelRemoteAddress, "127.0.0.1")
        XCTAssertEqual(config.dnsServers, ["198.18.0.1"])
        XCTAssertEqual(config.mtu, 9000)
        XCTAssertTrue(config.includedRoutes.contains("0.0.0.0/0"))
        XCTAssertTrue(config.excludedRoutes.contains("192.168.0.0/16"))
        XCTAssertTrue(config.excludedRoutes.contains("10.0.0.0/8"))
    }

    func testVPNConfigurationCustom() {
        let config = VPNConfiguration(
            tunnelAddress: "10.0.0.1",
            tunnelSubnetMask: "255.255.255.0",
            tunnelRemoteAddress: "10.0.0.2",
            dnsServers: ["8.8.8.8"],
            includedRoutes: ["10.0.0.0/8"],
            excludedRoutes: ["10.0.0.1/32"],
            mtu: 1500
        )
        XCTAssertEqual(config.tunnelAddress, "10.0.0.1")
        XCTAssertEqual(config.mtu, 1500)
    }

    // MARK: - TUNRoutingStats

    func testTUNRoutingStatsInit() {
        let stats = TUNRoutingStats(
            packetsHandled: 100,
            tcpPacketsHandled: 60,
            udpPacketsHandled: 30,
            dnsPacketsHandled: 10,
            bytesProcessed: 50000,
            activeTCPConnections: 5,
            activeUDPSessions: 3
        )
        XCTAssertEqual(stats.packetsHandled, 100)
        XCTAssertEqual(stats.tcpPacketsHandled, 60)
        XCTAssertEqual(stats.udpPacketsHandled, 30)
        XCTAssertEqual(stats.dnsPacketsHandled, 10)
        XCTAssertEqual(stats.bytesProcessed, 50000)
        XCTAssertEqual(stats.activeTCPConnections, 5)
        XCTAssertEqual(stats.activeUDPSessions, 3)
    }

    // MARK: - PacketHandler — IP Parsing

    func testPacketHandlerParseIPPacketRejectsShortData() {
        let result = PacketHandler.parseIPPacket(Data([0x45]))
        XCTAssertNil(result)
    }

    func testPacketHandlerParseIPPacketRejectsEmptyData() {
        let result = PacketHandler.parseIPPacket(Data())
        XCTAssertNil(result)
    }

    func testPacketHandlerParseIPPacketRejectsIPv6() {
        // Version 6 (0x60 in first nibble)
        var header = Data(count: 20)
        header[0] = 0x60
        let result = PacketHandler.parseIPPacket(header)
        XCTAssertNil(result, "IPv6 should be rejected (only IPv4 supported)")
    }

    func testPacketHandlerParseIPPacketAcceptsValidIPv4Header() {
        var header = Data(count: 20)
        header[0] = 0x45           // Version 4, IHL 5
        header[1] = 0x00
        header[2] = 0x00           // Total length high
        header[3] = 0x14           // Total length low = 20
        header[8] = 0x40           // TTL=64
        header[9] = 0x06           // Protocol=TCP
        header[12] = 10            // Src: 10.0.0.1
        header[13] = 0
        header[14] = 0
        header[15] = 1
        header[16] = 192           // Dst: 192.168.1.1
        header[17] = 168
        header[18] = 1
        header[19] = 1

        let result = PacketHandler.parseIPPacket(header)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.ip.version, 4)
        XCTAssertEqual(result?.ip.ihl, 5)
        XCTAssertEqual(result?.ip.ipProtocol, 6)
        XCTAssertEqual(result?.ip.sourceAddress, "10.0.0.1")
        XCTAssertEqual(result?.ip.destinationAddress, "192.168.1.1")
        XCTAssertEqual(result?.ip.totalLength, 20)
        XCTAssertTrue(result?.ip.payload.isEmpty ?? false)
    }

    func testPacketHandlerParseIPPacketWithPayload() {
        // IP header (20 bytes) + 10 bytes payload
        var data = Data(count: 30)
        data[0] = 0x45
        data[2] = 0x00; data[3] = 0x1E  // Total length = 30
        data[8] = 0x40  // TTL
        data[9] = 0x11  // Protocol = UDP
        data[12] = 10; data[13] = 0; data[14] = 0; data[15] = 1
        data[16] = 8; data[17] = 8; data[18] = 8; data[19] = 8

        let result = PacketHandler.parseIPPacket(data)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.ip.ipProtocol, 17)  // UDP
        XCTAssertEqual(result?.ip.payload.count, 10)
    }

    // MARK: - PacketHandler — TCP Flags

    func testTCPFlagsSyn() {
        let flags = TCPFlags(raw: 0x02)  // SYN bit set
        XCTAssertTrue(flags.syn)
        XCTAssertFalse(flags.ack)
        XCTAssertFalse(flags.fin)
        XCTAssertFalse(flags.rst)
    }

    func testTCPFlagsSynAck() {
        let flags = TCPFlags(raw: 0x12)  // SYN + ACK
        XCTAssertTrue(flags.syn)
        XCTAssertTrue(flags.ack)
    }

    func testTCPFlagsFinAck() {
        let flags = TCPFlags(raw: 0x11)  // FIN + ACK
        XCTAssertTrue(flags.fin)
        XCTAssertTrue(flags.ack)
    }

    func testTCPFlagsRST() {
        let flags = TCPFlags(raw: 0x04)  // RST
        XCTAssertTrue(flags.rst)
    }

    func testTCPFlagsNone() {
        let flags = TCPFlags(raw: 0x00)
        XCTAssertFalse(flags.syn)
        XCTAssertFalse(flags.ack)
        XCTAssertFalse(flags.fin)
        XCTAssertFalse(flags.rst)
        XCTAssertFalse(flags.psh)
        XCTAssertFalse(flags.urg)
    }

    // MARK: - PacketHandler — TCP Header Parsing

    func testTCPHeaderParsing() {
        var data = Data(count: 20)
        // Source port = 12345
        data[0] = 0x30; data[1] = 0x39
        // Dest port = 80
        data[2] = 0x00; data[3] = 0x50
        // Data offset = 5 (20 bytes), in upper nibble of byte 12
        data[12] = 0x50  // 0101_0000 → offset = 5*4 = 20
        // Flags = SYN
        data[13] = 0x02

        let tcp = TCPHeader(data)
        XCTAssertNotNil(tcp)
        XCTAssertEqual(tcp?.sourcePort, 12345)
        XCTAssertEqual(tcp?.destinationPort, 80)
        XCTAssertEqual(tcp?.dataOffset, 20)
        XCTAssertTrue(tcp?.syn ?? false)
        XCTAssertFalse(tcp?.ack ?? true)
    }

    func testTCPHeaderRejectsShortData() {
        let data = Data(count: 10)
        let tcp = TCPHeader(data)
        XCTAssertNil(tcp)
    }

    // MARK: - PacketHandler — UDP Header Parsing

    func testUDPHeaderParsing() {
        var data = Data(count: 8)
        // Source port = 53
        data[0] = 0x00; data[1] = 0x35
        // Dest port = 12345
        data[2] = 0x30; data[3] = 0x39
        // Length = 8
        data[4] = 0x00; data[5] = 0x08
        // Checksum
        data[6] = 0x00; data[7] = 0x00

        let udp = UDPHeader(data)
        XCTAssertNotNil(udp)
        XCTAssertEqual(udp?.sourcePort, 53)
        XCTAssertEqual(udp?.destinationPort, 12345)
        XCTAssertEqual(udp?.length, 8)
    }

    func testUDPHeaderRejectsShortData() {
        let data = Data(count: 4)
        let udp = UDPHeader(data)
        XCTAssertNil(udp)
    }

    // MARK: - PacketHandler — Checksum

    func testComputeChecksumIsStable() {
        let data = Data([0x45, 0x00, 0x00, 0x14, 0x00, 0x00, 0x40, 0x00, 0x40, 0x06])
        let cs1 = PacketHandler.computeChecksum(data)
        let cs2 = PacketHandler.computeChecksum(data)
        XCTAssertEqual(cs1, cs2, "Checksum should be deterministic")
    }

    // MARK: - PacketHandler — Swap Functions

    func testSwapIPAddresses() {
        var packet = Data(count: 20)
        packet[0] = 0x45
        packet[12] = 10; packet[13] = 0; packet[14] = 0; packet[15] = 1
        packet[16] = 192; packet[17] = 168; packet[18] = 1; packet[19] = 1

        let swapped = PacketHandler.swapIPAddresses(packet)
        XCTAssertEqual(swapped[12], 192)
        XCTAssertEqual(swapped[13], 168)
        XCTAssertEqual(swapped[14], 1)
        XCTAssertEqual(swapped[15], 1)
        XCTAssertEqual(swapped[16], 10)
        XCTAssertEqual(swapped[17], 0)
        XCTAssertEqual(swapped[18], 0)
        XCTAssertEqual(swapped[19], 1)
    }

    func testSwapIPAndPorts() {
        var packet = Data(count: 20)
        packet[0] = 0x45
        // Source port 12345 at bytes 0-1 (but byte 0 is version, so use TCP header offset)
        // For a minimal test, just verify the function doesn't crash
        let swapped = PacketHandler.swapIPAndPorts(packet)
        XCTAssertEqual(swapped.count, 20)
    }

    // MARK: - PacketHandler — DNS Detection

    func testIsDNSWithShortData() {
        let result = PacketHandler.isDNS(Data(repeating: 0, count: 5))
        XCTAssertFalse(result)
    }

    func testExtractDNSQueryWithShortData() {
        let result = PacketHandler.extractDNSQuery(Data(repeating: 0, count: 5))
        XCTAssertNil(result)
    }
}
