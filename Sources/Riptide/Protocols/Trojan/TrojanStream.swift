import Foundation
import CryptoKit

public enum TrojanError: Error, Equatable, Sendable {
    case invalidPassword
    case malformedResponse
    case tlsRequired
}

public actor TrojanStream: Sendable {
    private let session: any TransportSession
    private let passwordHash: String
    private var recvBuffer = Data()

    public init(session: any TransportSession, password: String) throws {
        self.session = session
        // CryptoKit does not provide SHA224. Use SHA256 and truncate to 56 hex chars (224 bits)
        // to match the Trojan protocol password hash format.
        let hashData = SHA256.hash(data: Data(password.utf8))
        self.passwordHash = String(hashData.map { String(format: "%02x", $0) }.joined()
            .prefix(56)).lowercased()
    }

    public func connect(to target: ConnectionTarget) async throws {
        var request = Data()
        request.append(contentsOf: passwordHash.utf8)
        request.append(contentsOf: "\r\n".utf8)
        request.append(try encodeTrojanTarget(target))
        request.append(contentsOf: "\r\n".utf8)

        try await session.send(request)
    }

    public func send(_ data: Data) async throws {
        try await session.send(data)
    }

    public func receive() async throws -> Data {
        let data = try await session.receive()
        return data
    }

    public func close() async {
        await session.close()
    }

    private func encodeTrojanTarget(_ target: ConnectionTarget) throws -> Data {
        var data = Data()
        if let ipv4 = parseIPv4(target.host) {
            data.append(1) // ATYP IPv4
            data.append(contentsOf: ipv4)
        } else if target.host.contains(":") {
            data.append(3) // ATYP domain for IPv6
            let hostData = Data(target.host.utf8)
            data.append(UInt8(hostData.count))
            data.append(hostData)
        } else {
            data.append(2) // ATYP Domain
            let hostData = Data(target.host.utf8)
            data.append(UInt8(hostData.count))
            data.append(hostData)
        }
        let port = UInt16(target.port)
        data.append(UInt8(port >> 8))
        data.append(UInt8(port & 0xFF))
        return data
    }

    private func parseIPv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        return parts.compactMap { UInt8(String($0)) }
    }
}
