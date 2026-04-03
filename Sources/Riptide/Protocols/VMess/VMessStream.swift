import Foundation
import CryptoKit

public enum VMessError: Error, Equatable, Sendable {
    case invalidUUID
    case invalidRequestHeader
    case decryptionFailed(String)
    case unsupportedSecurity(String)
}

public struct VMessRequestHeader: Sendable {
    public let version: UInt8
    public let dataLength: UInt16
    public let command: UInt8
    public let port: UInt16
    public let address: Data
    public let randomFillLength: UInt8
    public let checksum: UInt32
}

public actor VMessStream: Sendable {
    private let session: any TransportSession
    private let uuid: UUID
    private var sendKey: SymmetricKey?
    private var recvKey: SymmetricKey?
    private var sendNonce: UInt64 = 0
    private var recvNonce: UInt64 = 0
    private var recvBuffer = Data()

    public init(session: any TransportSession, uuid: UUID) {
        self.session = session
        self.uuid = uuid
    }

    public func connect(to target: ConnectionTarget) async throws {
        var header = Data()
        header.append(1) // version
        let targetData = try encodeVMessTarget(target)
        let dataLength = UInt16(targetData.count + 1) // +1 for command
        header.append(UInt8(dataLength >> 8))
        header.append(UInt8(dataLength & 0xFF))
        header.append(1) // command = TCP
        let port = UInt16(target.port)
        header.append(UInt8(port >> 8))
        header.append(UInt8(port & 0xFF))
        header.append(targetData)
        header.append(0) // random fill length

        let uuidData = withUnsafeBytes(of: uuid.uuid) { Data($0) }
        let timestamp = UInt64(Date().timeIntervalSince1970)
        var timestampData = Data(count: 8)
        timestampData.withUnsafeMutableBytes { ptr in
            var t = timestamp.littleEndian
            let bytes = ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for i in 0..<8 {
                bytes[i] = UInt8(t & 0xFF)
                t >>= 8
            }
        }

        let authKey = deriveAuthKey(uuid: uuid)
        let headerKey = deriveSubKey(key: authKey, label: Data("c48619fe-8f02-49e0-b9e9-edf763e17e21".utf8))
        sendKey = deriveSubKey(key: authKey, label: Data("487bb5e6-d2a1-4f6e-8242-3c1f250c8bda".utf8))
        recvKey = deriveSubKey(key: authKey, label: Data("d4712b59-7f38-4a33-8fd0-8a52d3d46a77".utf8))

        let headerIV = Data([UInt8](repeating: 0, count: 16))
        let encryptedHeader = try encryptAES128(header, key: headerKey, iv: headerIV)

        var authData = Data(count: 8)
        for i in 0..<8 { authData.append(UInt8.random(in: 0...255)) }
        authData.append(timestampData)
        authData.append(encryptedHeader)
        authData.append(1) // header length

        let authEncrypted = try encryptAES128(authData, key: authKey, iv: Data([UInt8](repeating: 0, count: 16)))
        try await session.send(authEncrypted)
    }

    public func send(_ data: Data) async throws {
        guard let key = sendKey else { throw VMessError.invalidRequestHeader }
        var frame = Data()
        let length = UInt16(data.count)
        frame.append(UInt8(length >> 8))
        frame.append(UInt8(length & 0xFF))
        frame.append(data)

        let iv = makeNonce(counter: sendNonce)
        let encrypted = try encryptAES128(frame, key: key, iv: iv)
        sendNonce += 1
        try await session.send(encrypted)
    }

    public func receive() async throws -> Data {
        while true {
            if recvBuffer.count >= 2 + 16 {
                let iv = makeNonce(counter: recvNonce)
                guard let key = recvKey else { throw VMessError.invalidRequestHeader }
                let encryptedLength = recvBuffer.prefix(2 + 16)
                let lengthData = try decryptAES128(Data(encryptedLength), key: key, iv: iv)
                let payloadLength = Int(UInt16(lengthData[0]) << 8 | UInt16(lengthData[1]))
                let totalNeeded = 2 + 16 + payloadLength + 16

                if recvBuffer.count >= totalNeeded {
                    let payloadIV = makeNonce(counter: recvNonce + 1)
                    let encryptedPayload = recvBuffer.dropFirst(2 + 16).prefix(payloadLength + 16)
                    let payload = try decryptAES128(Data(encryptedPayload), key: key, iv: payloadIV)
                    recvBuffer.removeFirst(totalNeeded)
                    recvNonce += 2
                    return payload
                }
            }
            let chunk = try await session.receive()
            guard !chunk.isEmpty else { return Data() }
            recvBuffer.append(chunk)
        }
    }

    public func close() async {
        await session.close()
    }

    private func makeNonce(counter: UInt64) -> Data {
        var nonce = Data(count: 16)
        nonce.withUnsafeMutableBytes { ptr in
            var c = counter
            let bytes = ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for i in 0..<8 {
                bytes[i] = UInt8(c & 0xFF)
                c >>= 8
            }
        }
        return nonce
    }

    private func deriveAuthKey(uuid: UUID) -> SymmetricKey {
        let uuidData = withUnsafeBytes(of: uuid.uuid) { Data($0) }
        var key = Data(count: 16)
        for i in 0..<16 {
            key[i] = uuidData[i]
        }
        return SymmetricKey(data: key)
    }

    private func deriveSubKey(key: SymmetricKey, label: Data) -> SymmetricKey {
        let prk = HKDF<SHA256>.extract(inputKeyMaterial: key, salt: Data([UInt8](repeating: 0, count: 16)))
        let expanded = HKDF<SHA256>.expand(pseudoRandomKey: prk, info: label, outputByteCount: 16)
        return SymmetricKey(data: expanded.withUnsafeBytes { Data($0) })
    }

    private func encryptAES128(_ plaintext: Data, key: SymmetricKey, iv: Data) throws -> Data {
        let nonce = try AES.GCM.Nonce(data: Data(iv.prefix(12)))
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
        return Data(sealed.combined!)
    }

    private func decryptAES128(_ ciphertext: Data, key: SymmetricKey, iv: Data) throws -> Data {
        let nonce = try AES.GCM.Nonce(data: Data(iv.prefix(12)))
        let sealed = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(sealed, using: key)
    }

    private func encodeVMessTarget(_ target: ConnectionTarget) throws -> Data {
        var data = Data()
        if let ipv4 = parseIPv4(target.host) {
            data.append(1) // ATYP IPv4
            data.append(contentsOf: ipv4)
        } else if target.host.contains(":") {
            data.append(3) // ATYP IPv6 (simplified)
            let hostData = Data(target.host.utf8)
            data.append(UInt8(hostData.count))
            data.append(hostData)
        } else {
            data.append(2) // ATYP Domain
            let hostData = Data(target.host.utf8)
            data.append(UInt8(hostData.count))
            data.append(hostData)
        }
        return data
    }

    private func parseIPv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        return parts.compactMap { UInt8(String($0)) }
    }
}
