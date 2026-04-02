import Foundation
import Network

public struct IPHeader {
    public let version: UInt8
    public let ihl: UInt8
    public let totalLength: UInt16
    public let protocol: UInt8
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
        protocol = data[9]

        sourceAddress = "\(data[12]).\(data[13]).\(data[14]).\(data[15])"
        destinationAddress = "\(data[16]).\(data[17]).\(data[18]).\(data[19])"

        payload = headerLength < data.count ? Data(data[headerLength...]) : Data()
    }
}

public struct TCPHeader {
    public let sourcePort: UInt16
    public let destinationPort: UInt16
    public let sequenceNumber: UInt32
    public let ackNumber: UInt32
    public let dataOffset: UInt8
    public let flags: UInt8
    public let window: UInt16
    public let payload: Data

    public init?(_ data: Data) {
        guard data.count >= 20 else { return nil }
        sourcePort = UInt16(data[0]) << 8 | UInt16(data[1])
        destinationPort = UInt16(data[2]) << 8 | UInt16(data[3])
        sequenceNumber = UInt32(data[4]) << 24 | UInt32(data[5]) << 16 | UInt32(data[6]) << 8 | UInt32(data[7])
        ackNumber = UInt32(data[8]) << 24 | UInt32(data[9]) << 16 | UInt32(data[10]) << 8 | UInt32(data[11])
        dataOffset = (data[12] >> 4) * 4
        flags = data[13]
        window = UInt16(data[14]) << 8 | UInt16(data[15])

        let headerLen = Int(dataOffset)
        payload = headerLen < data.count ? Data(data[headerLen...]) : Data()
    }

    public var isSYN: Bool { (flags & 0x02) != 0 }
    public var isACK: Bool { (flags & 0x10) != 0 }
    public var isFIN: Bool { (flags & 0x01) != 0 }
    public var isRST: Bool { (flags & 0x04) != 0 }
    public var isPSH: Bool { (flags & 0x08) != 0 }
}

public struct UDPHeader {
    public let sourcePort: UInt16
    public let destinationPort: UInt16
    public let length: UInt16
    public let payload: Data

    public init?(_ data: Data) {
        guard data.count >= 8 else { return nil }
        sourcePort = UInt16(data[0]) << 8 | UInt16(data[1])
        destinationPort = UInt16(data[2]) << 8 | UInt16(data[3])
        length = UInt16(data[4]) << 8 | UInt16(data[5])
        payload = data.count > 8 ? Data(data[8...]) : Data()
    }
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
}
