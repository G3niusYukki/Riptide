import Foundation
import CryptoKit

enum ShadowsocksAEAD: Sendable {
    static func encryptChunk(
        payload: Data,
        subkey: Data,
        counter: UInt64,
        provider: ShadowsocksCryptoProvider
    ) throws -> Data {
        let length = UInt16(payload.count).bigEndian
        var lengthBytes = Data(count: 2)
        lengthBytes[0] = UInt8((length >> 8) & 0xFF)
        lengthBytes[1] = UInt8(length & 0xFF)

        let lengthNonce = provider.makeNonce(counter: counter)
        let encryptedLength = try provider.encrypt(key: subkey, nonce: lengthNonce, plaintext: lengthBytes)

        let payloadNonce = provider.makeNonce(counter: counter + 1)
        let encryptedPayload = try provider.encrypt(key: subkey, nonce: payloadNonce, plaintext: payload)

        return encryptedLength + encryptedPayload
    }

    static func decryptChunk(
        data: Data,
        subkey: Data,
        counter: UInt64,
        provider: ShadowsocksCryptoProvider
    ) throws -> (payload: Data, consumed: Int) {
        let lengthTotalSize = 2 + provider.cipher.nonceLength + provider.cipher.tagLength

        guard data.count >= lengthTotalSize else {
            throw ShadowsocksCryptoError.decryptionFailed(
                "insufficient data for length header: got \(data.count), need \(lengthTotalSize)"
            )
        }

        let lengthNonce = provider.makeNonce(counter: counter)
        let encryptedLength = data.prefix(lengthTotalSize)
        let lengthBytes = try provider.decrypt(key: subkey, nonce: lengthNonce, ciphertext: Data(encryptedLength))

        guard lengthBytes.count == 2 else {
            throw ShadowsocksCryptoError.decryptionFailed("invalid length header")
        }

        let payloadLength = Int(UInt16(lengthBytes[0]) << 8) | Int(UInt16(lengthBytes[1]))
        let payloadTotalSize = payloadLength + provider.cipher.nonceLength + provider.cipher.tagLength

        guard data.count >= lengthTotalSize + payloadTotalSize else {
            throw ShadowsocksCryptoError.decryptionFailed(
                "insufficient data for payload: got \(data.count), need \(lengthTotalSize + payloadTotalSize)"
            )
        }

        let payloadNonce = provider.makeNonce(counter: counter + 1)
        let encryptedPayload = data.dropFirst(lengthTotalSize).prefix(payloadTotalSize)
        let payload = try provider.decrypt(key: subkey, nonce: payloadNonce, ciphertext: Data(encryptedPayload))

        return (payload: payload, consumed: lengthTotalSize + payloadTotalSize)
    }
}
