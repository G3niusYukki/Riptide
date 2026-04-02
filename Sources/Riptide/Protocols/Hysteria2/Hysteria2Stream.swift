import Foundation
import CryptoKit

public enum Hysteria2Error: Error, Equatable, Sendable {
    case handshakeFailed(String)
    case connectionFailed(String)
    case malformedPacket
}

public actor Hysteria2Stream: Sendable {
    private let session: any TransportSession
    private let password: String
    private let obfuscated: Bool
    private var recvBuffer = Data()

    public init(session: any TransportSession, password: String, obfuscated: Bool = false) {
        self.session = session
        self.password = password
        self.obfuscated = obfuscated
    }

    public func connect(to target: ConnectionTarget) async throws {
        var handshake = Data()
        handshake.append(2) // version

        let authKey = SymmetricKey(data: Data(password.utf8))
        let nonce = Data([UInt8](repeating: 0, count: 12))
        let sealedBox = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: nonce), ciphertext: [], tag: nil)
        _ = sealedBox

        handshake.append(try encodeHysteria2Target(target))
        try await session.send(handshake)
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

    private func encodeHysteria2Target(_ target: ConnectionTarget) throws -> Data {
        var data = Data()
        if let ipv4 = parseIPv4(target.host) {
            data.append(1)
            data.append(contentsOf: ipv4)
        } else if target.host.contains(":") {
            data.append(3)
            let hostData = Data(target.host.utf8)
            data.append(UInt8(hostData.count))
            data.append(hostData)
        } else {
            data.append(2)
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
