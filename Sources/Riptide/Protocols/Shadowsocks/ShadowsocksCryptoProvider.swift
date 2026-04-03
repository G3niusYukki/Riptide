import Foundation
import CryptoKit

enum ShadowsocksCipher: String, Sendable {
    case aes128GCM = "aes-128-gcm"
    case aes256GCM = "aes-256-gcm"
    case chacha20IETFPoly1305 = "chacha20-ietf-poly1305"

    var keyLength: Int {
        switch self {
        case .aes128GCM: return 16
        case .aes256GCM: return 32
        case .chacha20IETFPoly1305: return 32
        }
    }

    var saltLength: Int { 32 }

    var nonceLength: Int { 12 }

    var tagLength: Int { 16 }

    static func from(_ name: String) throws -> ShadowsocksCipher {
        guard let cipher = ShadowsocksCipher(rawValue: name) else {
            throw ShadowsocksCryptoError.unsupportedCipher(name)
        }
        return cipher
    }
}

enum ShadowsocksCryptoError: Error, Equatable, Sendable {
    case unsupportedCipher(String)
    case invalidKeyLength
    case encryptionFailed(String)
    case decryptionFailed(String)
}

struct ShadowsocksCryptoProvider: Sendable {
    let cipher: ShadowsocksCipher
    let password: String

    init(cipher: String, password: String) throws {
        self.cipher = try .from(cipher)
        self.password = password
    }

    func deriveSubkey(salt: Data) throws -> Data {
        let inputKey = SymmetricKey(data: Data(password.utf8))
        let prk = HKDF<SHA256>.extract(inputKeyMaterial: inputKey, salt: salt)
        let expanded = HKDF<SHA256>.expand(
            pseudoRandomKey: prk,
            info: Data("ss-subkey".utf8),
            outputByteCount: cipher.keyLength
        )
        return expanded.withUnsafeBytes { Data($0) }
    }

    func generateSalt() -> Data {
        var salt = Data(count: cipher.saltLength)
        salt.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, cipher.saltLength, ptr.baseAddress!)
        }
        return salt
    }

    func makeNonce(counter: UInt64) -> Data {
        var nonce = Data(count: cipher.nonceLength)
        nonce.withUnsafeMutableBytes { ptr in
            var bigEndianCounter = counter.bigEndian
            let nonceBytes = ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let offset = cipher.nonceLength - 8
            for i in 0..<8 {
                nonceBytes[offset + i] = UInt8(truncatingIfNeeded: bigEndianCounter & 0xFF)
                bigEndianCounter >>= 8
            }
        }
        return nonce
    }

    func encrypt(key: Data, nonce: Data, plaintext: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        switch cipher {
        case .aes128GCM, .aes256GCM:
            let aesNonce = try AES.GCM.Nonce(data: nonce)
            let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey, nonce: aesNonce)
            return sealedBox.combined!
        case .chacha20IETFPoly1305:
            let chachaNonce = try ChaChaPoly.Nonce(data: nonce)
            let sealedBox = try ChaChaPoly.seal(plaintext, using: symmetricKey, nonce: chachaNonce)
            return sealedBox.combined
        }
    }

    func decrypt(key: Data, nonce: Data, ciphertext: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        switch cipher {
        case .aes128GCM, .aes256GCM:
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        case .chacha20IETFPoly1305:
            let sealedBox = try ChaChaPoly.SealedBox(combined: ciphertext)
            return try ChaChaPoly.open(sealedBox, using: symmetricKey)
        }
    }
}
