import Foundation
import Network

public struct IPHeader {
    public let version: UInt8
    public let ihl: UInt8
    public let totalLength: UInt16
    public let ipProtocol: UInt8
    public let sourceAddress: String
    public let destinationAddress: String
    public let payload: Data

    public init?(_ data: Data) {
        guard data.count >= 20 else { return nil }
        let firstByte = data[0]
        version = firstByte >> 4
        ihl = firstByte & 0x0F
        guard version == 4 else { return nil }
        let headerLength = Int(ihl) * 4
        guard data.count >= headerLength else { return nil }

        totalLength = UInt16(data[2]) << 8 | UInt16(data[3])
        ipProtocol = data[9]

        sourceAddress = "\(data[12]).\(data[13]).\(data[14]).\(data[15])"
        destinationAddress = "\(data[16]).\(data[17]).\(data[18]).\(data[19])"

        payload = headerLength < data.count ? Data(data[headerLength...]) : Data()
    }
}

public struct TCPHeader {
    public let sourcePort: UInt16
    public let destinationPort: UInt16
    public let sequenceNumber: UInt32
    public let acknowledgmentNumber: UInt32
    public let dataOffset: UInt8
    public let flags: TCPFlags
    public let windowSize: UInt16
    public let checksum: UInt16
    public let urgentPointer: UInt16
    public let options: Data

    public init(
        sourcePort: UInt16,
        destinationPort: UInt16,
        sequenceNumber: UInt32,
        acknowledgmentNumber: UInt32,
        dataOffset: UInt8,
        flags: TCPFlags,
        windowSize: UInt16,
        checksum: UInt16,
        urgentPointer: UInt16,
        options: Data
    ) {
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.sequenceNumber = sequenceNumber
        self.acknowledgmentNumber = acknowledgmentNumber
        self.dataOffset = dataOffset
        self.flags = flags
        self.windowSize = windowSize
        self.checksum = checksum
        self.urgentPointer = urgentPointer
        self.options = options
    }

    public init?(_ data: Data) {
        guard data.count >= 20 else { return nil }
        sourcePort = UInt16(data[0]) << 8 | UInt16(data[1])
        destinationPort = UInt16(data[2]) << 8 | UInt16(data[3])
        sequenceNumber = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
        acknowledgmentNumber = UInt32(data[8]) << 24 | UInt32(data[9]) << 16 | UInt32(data[10]) << 8 | UInt32(data[11])
        dataOffset = (data[12] >> 4) * 4
        flags = TCPFlags(raw: data[13])
        windowSize = UInt16(data[14]) << 8 | UInt16(data[15])
        checksum = UInt16(data[16]) << 8 | UInt16(data[17])
        urgentPointer = UInt16(data[18]) << 8 | UInt16(data[19])
        let headerLen = Int(dataOffset)
        options = headerLen > 20 ? Data(data[20..<headerLen]) : Data()
    }

    public var syn: Bool { flags.syn }
    public var ack: Bool { flags.ack }
    public var fin: Bool { flags.fin }
    public var rst: Bool { flags.rst }
    public var psh: Bool { flags.psh }
    public var urg: Bool { flags.urg }
}

public struct UDPHeader {
    public let sourcePort: UInt16
    public let destinationPort: UInt16
    public let length: UInt16
    public let checksum: UInt16
    public let payload: Data

    public init(
        sourcePort: UInt16,
        destinationPort: UInt16,
        length: UInt16,
        checksum: UInt16
    ) {
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.length = length
        self.checksum = checksum
        self.payload = Data()
    }

    public init?(_ data: Data) {
        guard data.count >= 8 else { return nil }
        sourcePort = UInt16(data[0]) << 8 | UInt16(data[1])
        destinationPort = UInt16(data[2]) << 8 | UInt16(data[3])
        length = UInt16(data[4]) << 8 | UInt16(data[5])
        checksum = UInt16(data[6]) << 8 | UInt16(data[7])
        payload = data.count > 8 ? Data(data[8...]) : Data()
    }
}

public struct TCPFlags: Sendable {
    public let raw: UInt8

    public init(raw: UInt8) {
        self.raw = raw
    }

    public var syn: Bool { (raw & 0x02) != 0 }
    public var ack: Bool { (raw & 0x10) != 0 }
    public var fin: Bool { (raw & 0x01) != 0 }
    public var rst: Bool { (raw & 0x04) != 0 }
    public var psh: Bool { (raw & 0x08) != 0 }
    public var urg: Bool { (raw & 0x20) != 0 }
    public var ece: Bool { (raw & 0x40) != 0 }
    public var cwr: Bool { (raw & 0x80) != 0 }
}

public enum PacketHandler {
    public static func parseIPPacket(_ data: Data) -> (ip: IPHeader, remaining: Data)? {
        guard let ip = IPHeader(data) else { return nil }
        return (ip, data)
    }

    public static func isDNS(_ data: Data) -> Bool {
        guard let udp = UDPHeader(data) else { return false }
        return udp.destinationPort == 53 || udp.sourcePort == 53
    }

    public static func extractDNSQuery(_ data: Data) -> Data? {
        guard data.count >= 28 else { return nil }
        return Data(data.dropFirst(28))
    }

    // ============================================================
    // MARK: - IP Packet Building
    // ============================================================

    /// Build a generic IP+TCP packet with the given parameters.
    public static func buildTCPPacket(
        srcIP: String,
        srcPort: UInt16,
        dstIP: String,
        dstPort: UInt16,
        seq: UInt32,
        ack: UInt32,
        flags: UInt8,
        windowSize: UInt16,
        payload: Data
    ) -> Data {
        let tcpHeader = buildTCPHeader(
            srcIP: srcIP,
            dstIP: dstIP,
            srcPort: srcPort,
            dstPort: dstPort,
            seq: seq,
            ack: ack,
            flags: flags,
            windowSize: windowSize,
            payload: payload
        )

        let ipHeader = buildIPv4Header(
            srcIP: srcIP,
            dstIP: dstIP,
            protocolNumber: 6,
            payload: tcpHeader
        )

        return ipHeader + tcpHeader
    }

    /// Build a SYN-ACK packet.
    public static func buildSYNACK(
        srcIP: String,
        srcPort: UInt16,
        dstIP: String,
        dstPort: UInt16,
        seq: UInt32
    ) -> Data {
        buildTCPPacket(
            srcIP: srcIP,
            srcPort: srcPort,
            dstIP: dstIP,
            dstPort: dstPort,
            seq: seq,
            ack: 0,
            flags: 0x12,  // SYN + ACK
            windowSize: 65535,
            payload: Data()
        )
    }

    /// Build an ACK packet.
    public static func buildACK(
        srcIP: String,
        srcPort: UInt16,
        dstIP: String,
        dstPort: UInt16,
        seq: UInt32,
        ack: UInt32
    ) -> Data {
        buildTCPPacket(
            srcIP: srcIP,
            srcPort: srcPort,
            dstIP: dstIP,
            dstPort: dstPort,
            seq: seq,
            ack: ack,
            flags: 0x10,  // ACK
            windowSize: 65535,
            payload: Data()
        )
    }

    /// Build a FIN-ACK packet.
    public static func buildFINACK(
        srcIP: String,
        srcPort: UInt16,
        dstIP: String,
        dstPort: UInt16,
        seq: UInt32,
        ack: UInt32
    ) -> Data {
        buildTCPPacket(
            srcIP: srcIP,
            srcPort: srcPort,
            dstIP: dstIP,
            dstPort: dstPort,
            seq: seq,
            ack: ack,
            flags: 0x11,  // FIN + ACK
            windowSize: 65535,
            payload: Data()
        )
    }

    // ============================================================
    // MARK: - IPv4 Header
    // ============================================================

    private static func buildIPv4Header(
        srcIP: String,
        dstIP: String,
        protocolNumber: UInt8,
        payload: Data
    ) -> Data {
        let srcParts = srcIP.split(separator: ".").compactMap { UInt8($0) }
        let dstParts = dstIP.split(separator: ".").compactMap { UInt8($0) }

        let totalLength = UInt16(20 + payload.count)
        var header = Data(count: 20)
        header[0] = 0x45  // version=4, IHL=5
        header[1] = 0      // DSCP/ECN
        header[2] = UInt8(totalLength >> 8)
        header[3] = UInt8(totalLength & 0xFF)
        header[4] = 0      // identification
        header[5] = 0
        header[6] = 0x40   // Don't fragment
        header[7] = 0      // More fragments = 0
        header[8] = 64     // TTL
        header[9] = protocolNumber
        // bytes 10-11: checksum (filled below)
        header[12] = srcParts.count >= 4 ? srcParts[0] : 0
        header[13] = srcParts.count >= 4 ? srcParts[1] : 0
        header[14] = srcParts.count >= 4 ? srcParts[2] : 0
        header[15] = srcParts.count >= 4 ? srcParts[3] : 0
        header[16] = dstParts.count >= 4 ? dstParts[0] : 0
        header[17] = dstParts.count >= 4 ? dstParts[1] : 0
        header[18] = dstParts.count >= 4 ? dstParts[2] : 0
        header[19] = dstParts.count >= 4 ? dstParts[3] : 0

        // Compute IP header checksum
        header[10] = 0
        header[11] = 0
        let checksum = computeChecksum(header)
        header[10] = UInt8(checksum >> 8)
        header[11] = UInt8(checksum & 0xFF)

        return header
    }

    // ============================================================
    // MARK: - TCP Header
    // ============================================================

    private static func buildTCPHeader(
        srcIP: String,
        dstIP: String,
        srcPort: UInt16,
        dstPort: UInt16,
        seq: UInt32,
        ack: UInt32,
        flags: UInt8,
        windowSize: UInt16,
        payload: Data
    ) -> Data {
        var header = Data(count: 20)
        header[0] = UInt8(srcPort >> 8)
        header[1] = UInt8(srcPort & 0xFF)
        header[2] = UInt8(dstPort >> 8)
        header[3] = UInt8(dstPort & 0xFF)
        header[4] = UInt8((seq >> 24) & 0xFF)
        header[5] = UInt8((seq >> 16) & 0xFF)
        header[6] = UInt8((seq >> 8) & 0xFF)
        header[7] = UInt8(seq & 0xFF)
        header[8] = UInt8((ack >> 24) & 0xFF)
        header[9] = UInt8((ack >> 16) & 0xFF)
        header[10] = UInt8((ack >> 8) & 0xFF)
        header[11] = UInt8(ack & 0xFF)
        header[12] = 0x50  // data offset = 5 (20 bytes), no options
        header[13] = flags
        header[14] = UInt8(windowSize >> 8)
        header[15] = UInt8(windowSize & 0xFF)
        // bytes 16-17: checksum (filled below)
        // bytes 18-19: urgent pointer (0)

        // Compute TCP checksum with pseudo-header (RFC 793)
        let tcpLength = UInt16(header.count + payload.count)
        let srcParts = srcIP.split(separator: ".").compactMap { UInt8($0) }
        let dstParts = dstIP.split(separator: ".").compactMap { UInt8($0) }

        // Build pseudo-header with actual IP addresses
        var pseudoHeader = Data(capacity: 12)
        pseudoHeader.append(srcParts.count >= 4 ? srcParts[0] : 0)
        pseudoHeader.append(srcParts.count >= 4 ? srcParts[1] : 0)
        pseudoHeader.append(srcParts.count >= 4 ? srcParts[2] : 0)
        pseudoHeader.append(srcParts.count >= 4 ? srcParts[3] : 0)
        pseudoHeader.append(dstParts.count >= 4 ? dstParts[0] : 0)
        pseudoHeader.append(dstParts.count >= 4 ? dstParts[1] : 0)
        pseudoHeader.append(dstParts.count >= 4 ? dstParts[2] : 0)
        pseudoHeader.append(dstParts.count >= 4 ? dstParts[3] : 0)
        pseudoHeader.append(0)        // reserved
        pseudoHeader.append(6)        // protocol = TCP
        pseudoHeader.append(UInt8(tcpLength >> 8))
        pseudoHeader.append(UInt8(tcpLength & 0xFF))

        let checksum = computeChecksum(pseudoHeader + header + payload)
        header[16] = UInt8(checksum >> 8)
        header[17] = UInt8(checksum & 0xFF)

        return header + payload
    }

    // ============================================================
    // MARK: - Checksum
    // ============================================================

    /// Compute the IP/TCP/UDP checksum over the given data.
    public static func computeChecksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        let count = data.count
        let alignedCount = count - (count % 2)

        for i in stride(from: 0, to: alignedCount, by: 2) {
            let word = UInt32(data[i]) << 8 | UInt32(data[i + 1])
            sum += word
        }

        if count % 2 != 0 {
            sum += UInt32(data[count - 1]) << 8
        }

        // Fold 32-bit sum to 16 bits
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) + (sum >> 16)
        }

        return ~UInt16(truncatingIfNeeded: sum)
    }

    // ============================================================
    // MARK: - Packet Utilities
    // ============================================================

    /// Swap source and destination IP addresses in an IP packet.
    /// Also updates the IP total length field if present.
    public static func swapIPAddresses(_ packet: Data) -> Data {
        guard packet.count >= 20 else { return packet }
        var result = packet

        // Swap source IP (bytes 12-15) with destination IP (bytes 16-19)
        let src0 = result[12], src1 = result[13], src2 = result[14], src3 = result[15]
        result[12] = result[16]
        result[13] = result[17]
        result[14] = result[18]
        result[15] = result[19]
        result[16] = src0
        result[17] = src1
        result[18] = src2
        result[19] = src3

        return result
    }

    /// Swap both IP addresses and UDP/TCP ports in a packet for response.
    public static func swapIPAndPorts(_ packet: Data) -> Data {
        guard packet.count >= 24 else { return packet }
        var result = packet

        // Swap IP addresses
        result = swapIPAddresses(result)

        let ipProtocol = result[9]
        if ipProtocol == 6 || ipProtocol == 17 {  // TCP or UDP
            // Swap ports (bytes 20-23)
            let srcPort0 = result[20], srcPort1 = result[21]
            result[20] = result[22]
            result[21] = result[23]
            result[22] = srcPort0
            result[23] = srcPort1
        }

        return result
    }
}
