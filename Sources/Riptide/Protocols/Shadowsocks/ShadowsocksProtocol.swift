import Foundation

public struct ShadowsocksProtocol: OutboundProxyProtocol {
    public init() {}

    public func makeConnectRequest(for target: ConnectionTarget) throws -> [Data] {
        let encoded = try TargetAddressEncoder.encode(target)
        var bytes: [UInt8] = []

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
        return [Data(bytes)]
    }

    public func parseConnectResponse(_ data: Data) throws -> ConnectResponse {
        _ = data
        return .success
    }
}
