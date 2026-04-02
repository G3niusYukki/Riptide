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
}
