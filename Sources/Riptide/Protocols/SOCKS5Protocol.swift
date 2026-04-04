import Foundation

public struct SOCKS5Protocol: OutboundProxyProtocol {
    public init() {}

    public func makeConnectRequest(for target: ConnectionTarget) throws -> [Data] {
        let greeting = Data([0x05, 0x01, 0x00])
        let connect = try buildConnectRequest(for: target)
        return [greeting, connect]
    }

    public func parseMethodSelection(_ data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 2, bytes[0] == 0x05 else {
            throw ProtocolError.malformedResponse("invalid method selection response")
        }
        if bytes[1] == 0xFF {
            throw ProtocolError.authenticationRejected
        }
        if bytes[1] != 0x00 {
            throw ProtocolError.connectionRejected("unsupported auth method: \(bytes[1])")
        }
    }

    public func parseConnectResponse(_ data: Data) throws -> ConnectResponse {
        let bytes = [UInt8](data)
        guard bytes.count >= 5, bytes[0] == 0x05 else {
            throw ProtocolError.malformedResponse("invalid connect response")
        }
        if bytes[1] == 0x00 {
            return .success
        }
        throw ProtocolError.connectionRejected("SOCKS5 REP=\(bytes[1])")
    }

    // MARK: - UDP Associate

    /// Build a SOCKS5 UDP ASSOCIATE request.
    /// - Parameter clientAddress: The address the client expects UDP relay datagrams from.
    /// - Returns: Method selection + UDP ASSOCIATE request.
    public func makeUDPAssociateRequest(clientAddress: ConnectionTarget) throws -> [Data] {
        let greeting = Data([0x05, 0x01, 0x00])
        let associate = try buildUDPAssociateRequest(for: clientAddress)
        return [greeting, associate]
    }

    /// Parse the UDP ASSOCIATE response.
    /// - Parameter data: The response data.
    /// - Returns: The relay endpoint address (IP:port) where UDP datagrams should be sent.
    public func parseUDPAssociateResponse(_ data: Data) throws -> ConnectionTarget {
        let bytes = [UInt8](data)
        guard bytes.count >= 5, bytes[0] == 0x05 else {
            throw ProtocolError.malformedResponse("invalid UDP associate response")
        }
        guard bytes[1] == 0x00 else {
            throw ProtocolError.connectionRejected("SOCKS5 UDP REP=\(bytes[1])")
        }

        // Parse bound address
        let atyp = bytes[3]
        var offset = 4
        var host: String
        var port: UInt16

        switch atyp {
        case 0x01:  // IPv4
            guard offset + 6 <= bytes.count else {
                throw ProtocolError.malformedResponse("truncated IPv4 in UDP associate response")
            }
            host = "\(bytes[offset]).\(bytes[offset + 1]).\(bytes[offset + 2]).\(bytes[offset + 3])"
            offset += 4
            port = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])

        case 0x04:  // IPv6
            guard offset + 18 <= bytes.count else {
                throw ProtocolError.malformedResponse("truncated IPv6 in UDP associate response")
            }
            var ipv6Parts: [String] = []
            for i in 0..<8 {
                let hi = bytes[offset + i * 2]
                let lo = bytes[offset + i * 2 + 1]
                ipv6Parts.append(String(format: "%02x%02x", hi, lo))
            }
            host = ipv6Parts.joined(separator: ":")
            offset += 16
            port = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])

        case 0x03:  // Domain
            guard offset < bytes.count else {
                throw ProtocolError.malformedResponse("missing domain length in UDP associate response")
            }
            let domainLength = Int(bytes[offset])
            offset += 1
            guard offset + domainLength + 2 <= bytes.count else {
                throw ProtocolError.malformedResponse("truncated domain in UDP associate response")
            }
            host = String(bytes: bytes[offset..<offset + domainLength], encoding: .utf8) ?? ""
            offset += domainLength
            port = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])

        default:
            throw ProtocolError.malformedResponse("invalid ATYP in UDP associate response: \(atyp)")
        }

        return ConnectionTarget(host: host, port: Int(port))
    }

    /// Build a SOCKS5 UDP datagram for sending through the relay.
    /// - Parameters:
    ///   - data: The raw UDP payload.
    ///   - target: The real destination of the UDP datagram.
    /// - Returns: SOCKS5-encapsulated UDP datagram.
    public func encodeUDPDatagram(data: Data, target: ConnectionTarget) throws -> Data {
        var datagram = Data()
        datagram.append(contentsOf: [0x00, 0x00])  // RSV
        datagram.append(0x00)  // FRAG = 0

        let encoded = try TargetAddressEncoder.encode(target)
        switch encoded.address {
        case .ipv4(let octets):
            datagram.append(0x01)  // ATYP = IPv4
            datagram.append(contentsOf: octets)
        case .domain(let host):
            datagram.append(0x03)  // ATYP = domain
            datagram.append(UInt8(host.utf8.count))
            datagram.append(contentsOf: host.utf8)
        case .ipv6(let octets):
            datagram.append(0x04)  // ATYP = IPv6
            datagram.append(contentsOf: octets)
        }

        let portBytes: [UInt8] = [
            UInt8(target.port >> 8),
            UInt8(target.port & 0xFF)
        ]
        datagram.append(contentsOf: portBytes)
        datagram.append(data)

        return datagram
    }

    /// Parse a SOCKS5 UDP datagram received from the relay.
    /// - Parameter data: The received datagram.
    /// - Returns: The raw UDP payload.
    public func decodeUDPDatagram(_ data: Data) throws -> Data {
        guard data.count >= 7 else {  // RSV(2) + FRAG(1) + ATYP(1) + min addr(1) + port(2)
            throw ProtocolError.malformedResponse("UDP datagram too short")
        }

        var offset = 3  // Skip RSV + FRAG
        let atyp = data[offset]
        offset += 1

        switch atyp {
        case 0x01:  // IPv4
            offset += 4
        case 0x04:  // IPv6
            offset += 16
        case 0x03:  // Domain
            guard offset < data.count else {
                throw ProtocolError.malformedResponse("missing domain length")
            }
            let domainLength = Int(data[offset])
            offset += 1 + domainLength
        default:
            throw ProtocolError.malformedResponse("invalid ATYP: \(atyp)")
        }

        offset += 2  // Skip port

        guard offset <= data.count else {
            throw ProtocolError.malformedResponse("payload offset out of range")
        }

        return data.subdata(in: offset..<data.count)
    }

    // MARK: - Private

    private func buildConnectRequest(for target: ConnectionTarget) throws -> Data {
        let encoded = try TargetAddressEncoder.encode(target)

        var bytes: [UInt8] = [0x05, 0x01, 0x00]
        switch encoded.address {
        case .ipv4(let octets):
            bytes.append(0x01)
            bytes.append(contentsOf: octets)
        case .domain(let host):
            bytes.append(0x03)
            bytes.append(UInt8(host.utf8.count))
            bytes.append(contentsOf: host.utf8)
        case .ipv6(let octets):
            bytes.append(0x04)
            bytes.append(contentsOf: octets)
        }
        bytes.append(contentsOf: encoded.portBytes)
        return Data(bytes)
    }

    private func buildUDPAssociateRequest(for target: ConnectionTarget) throws -> Data {
        let encoded = try TargetAddressEncoder.encode(target)

        var bytes: [UInt8] = [0x05, 0x03, 0x00]  // CMD = 0x03 (UDP ASSOCIATE)
        switch encoded.address {
        case .ipv4(let octets):
            bytes.append(0x01)
            bytes.append(contentsOf: octets)
        case .domain(let host):
            bytes.append(0x03)
            bytes.append(UInt8(host.utf8.count))
            bytes.append(contentsOf: host.utf8)
        case .ipv6(let octets):
            bytes.append(0x04)
            bytes.append(contentsOf: octets)
        }
        bytes.append(contentsOf: encoded.portBytes)
        return Data(bytes)
    }
}
