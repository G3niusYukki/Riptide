import Foundation
import Network

public struct TCPConnectionState: Sendable {
    public let localIP: String
    public let localPort: UInt16
    public let remoteIP: String
    public let remotePort: UInt16
    public var state: TCPState

    public enum TCPState: String, Sendable {
        case synSent
        case established
        case closing
        case closed
    }
}

public final class UserSpaceTCP: @unchecked Sendable {
    private var connections: [String: TCPConnectionState]
    private let lock = NSLock()

    public init() {
        self.connections = [:]
    }

    public func connectionKey(localIP: String, localPort: UInt16, remoteIP: String, remotePort: UInt16) -> String {
        "\(localIP):\(localPort)-\(remoteIP):\(remotePort)"
    }

    public func onSYN(localIP: String, localPort: UInt16, remoteIP: String, remotePort: UInt16) -> Data {
        let key = connectionKey(localIP: localIP, localPort: localPort, remoteIP: remoteIP, remotePort: remotePort)

        lock.lock()
        defer { lock.unlock() }

        connections[key] = TCPConnectionState(
            localIP: localIP, localPort: localPort,
            remoteIP: remoteIP, remotePort: remotePort,
            state: .synSent
        )

        return buildSYNACK(
            srcIP: remoteIP, srcPort: remotePort,
            dstIP: localIP, dstPort: localPort
        )
    }

    public func onACK(localIP: String, localPort: UInt16, remoteIP: String, remotePort: UInt16) -> Bool {
        let key = connectionKey(localIP: localIP, localPort: localPort, remoteIP: remoteIP, remotePort: remotePort)

        lock.lock()
        defer { lock.unlock() }

        guard var conn = connections[key], conn.state == .synSent else { return false }
        conn.state = .established
        connections[key] = conn
        return true
    }

    public func isEstablished(localIP: String, localPort: UInt16, remoteIP: String, remotePort: UInt16) -> Bool {
        let key = connectionKey(localIP: localIP, localPort: localPort, remoteIP: remoteIP, remotePort: remotePort)
        lock.lock()
        defer { lock.unlock() }
        return connections[key]?.state == .established
    }

    public func closeConnection(localIP: String, localPort: UInt16, remoteIP: String, remotePort: UInt16) {
        let key = connectionKey(localIP: localIP, localPort: localPort, remoteIP: remoteIP, remotePort: remotePort)
        lock.lock()
        defer { lock.unlock() }
        connections.removeValue(forKey: key)
    }

    /// Build a SYN-ACK response packet (IP + TCP headers).
    /// Copilot fix: total length now at ip[2..3] (was incorrectly at ip[8..9] which are TTL/protocol).
    /// TCP checksum now uses proper pseudo-header per RFC 793.
    private func buildSYNACK(srcIP: String, srcPort: UInt16, dstIP: String, dstPort: UInt16) -> Data {
        let srcParts = srcIP.split(separator: ".").compactMap { UInt8($0) }
        let dstParts = dstIP.split(separator: ".").compactMap { UInt8($0) }

        // --- TCP header (20 bytes) ---
        var tcp = Data(count: 20)
        tcp[0] = UInt8(srcPort >> 8)
        tcp[1] = UInt8(srcPort & 0xFF)
        tcp[2] = UInt8(dstPort >> 8)
        tcp[3] = UInt8(dstPort & 0xFF)
        let seq = UInt32.random(in: 0...UInt32.max)
        tcp[4] = UInt8((seq >> 24) & 0xFF)
        tcp[5] = UInt8((seq >> 16) & 0xFF)
        tcp[6] = UInt8((seq >> 8) & 0xFF)
        tcp[7] = UInt8(seq & 0xFF)
        // ACK number = 0 (bytes 8-11 already zero)
        tcp[12] = 0x50 // data offset = 5 (20 bytes)
        tcp[13] = 0x12 // SYN + ACK
        tcp[14] = UInt8(65535 >> 8)  // window size
        tcp[15] = UInt8(65535 & 0xFF)
        // checksum (bytes 16-17) computed below
        // urgent pointer (bytes 18-19) = 0

        // --- IPv4 header (20 bytes) ---
        let totalLength = UInt16(20 + 20)
        var ip = Data(count: 20)
        ip[0] = 0x45  // version=4, IHL=5
        // ip[1] = 0 (DSCP/ECN)
        ip[2] = UInt8(totalLength >> 8)    // Total length (was incorrectly at [8],[9])
        ip[3] = UInt8(totalLength & 0xFF)
        // ip[4..5] = 0 (identification)
        // ip[6..7] = 0 (flags + fragment offset)
        ip[8] = 64    // TTL
        ip[9] = 6     // Protocol = TCP
        // ip[10..11] = 0 (header checksum, computed below)
        ip[12] = srcParts.count >= 1 ? srcParts[0] : 0
        ip[13] = srcParts.count >= 2 ? srcParts[1] : 0
        ip[14] = srcParts.count >= 3 ? srcParts[2] : 0
        ip[15] = srcParts.count >= 4 ? srcParts[3] : 0
        ip[16] = dstParts.count >= 1 ? dstParts[0] : 0
        ip[17] = dstParts.count >= 2 ? dstParts[1] : 0
        ip[18] = dstParts.count >= 3 ? dstParts[2] : 0
        ip[19] = dstParts.count >= 4 ? dstParts[3] : 0

        // IP header checksum
        let ipChecksum = computeChecksum(ip)
        ip[10] = UInt8(ipChecksum >> 8)
        ip[11] = UInt8(ipChecksum & 0xFF)

        // TCP checksum with pseudo-header (RFC 793)
        var pseudoHeader = Data()
        pseudoHeader.append(contentsOf: ip[12...15])  // src IP
        pseudoHeader.append(contentsOf: ip[16...19])  // dst IP
        pseudoHeader.append(0)        // reserved
        pseudoHeader.append(6)        // protocol = TCP
        let tcpLength = UInt16(tcp.count)
        pseudoHeader.append(UInt8(tcpLength >> 8))
        pseudoHeader.append(UInt8(tcpLength & 0xFF))
        let tcpChecksum = computeChecksum(pseudoHeader + tcp)
        tcp[16] = UInt8(tcpChecksum >> 8)
        tcp[17] = UInt8(tcpChecksum & 0xFF)

        return ip + tcp
    }

    private func computeChecksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        let count = data.count
        var i = 0
        while i + 1 < count {
            sum += UInt32(UInt16(data[i]) << 8 | UInt16(data[i + 1]))
            i += 2
        }
        if count % 2 != 0 {
            sum += UInt32(UInt16(data[count - 1]) << 8)
        }
        while sum > 0xFFFF {
            sum = (sum >> 16) + (sum & 0xFFFF)
        }
        return ~UInt16(sum)
    }
}
