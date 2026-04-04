import Foundation

public struct ConnectionTarget: Equatable, Sendable {
    public let host: String
    public let port: Int
    /// Domain extracted from HTTP Host header or TLS SNI for rule matching.
    public let sniffedDomain: String?

    public init(host: String, port: Int, sniffedDomain: String? = nil) {
        self.host = host
        self.port = port
        self.sniffedDomain = sniffedDomain
    }
}

public enum ConnectResponse: Equatable, Sendable {
    case success
}

public enum ProtocolError: Error, Equatable, Sendable {
    case invalidTarget(String)
    case malformedResponse(String)
    case authenticationRejected
    case connectionRejected(String)
}

public protocol OutboundProxyProtocol: Sendable {
    func makeConnectRequest(for target: ConnectionTarget) throws -> [Data]
    func parseConnectResponse(_ data: Data) throws -> ConnectResponse
}

enum TargetAddressEncoding {
    case ipv4([UInt8])
    case domain(String)
    case ipv6([UInt8])
}

enum TargetAddressEncoder {
    static func encode(_ target: ConnectionTarget) throws -> (address: TargetAddressEncoding, portBytes: [UInt8]) {
        guard (1...65_535).contains(target.port) else {
            throw ProtocolError.invalidTarget("port out of range")
        }
        let portBytes: [UInt8] = [UInt8((target.port >> 8) & 0xFF), UInt8(target.port & 0xFF)]

        if let ipv4 = parseIPv4(target.host) {
            return (.ipv4(ipv4), portBytes)
        }
        if let ipv6 = parseIPv6(target.host) {
            return (.ipv6(ipv6), portBytes)
        }

        let host = target.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host.utf8.count <= 255 else {
            throw ProtocolError.invalidTarget("invalid domain host")
        }
        return (.domain(host), portBytes)
    }

    private static func parseIPv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [UInt8] = []
        octets.reserveCapacity(4)
        for part in parts {
            guard let value = UInt8(String(part)) else { return nil }
            octets.append(value)
        }
        return octets
    }

    private static func parseIPv6(_ host: String) -> [UInt8]? {
        var address = in6_addr()
        let result = host.withCString { ptr in
            inet_pton(AF_INET6, ptr, &address)
        }
        guard result == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }
}
