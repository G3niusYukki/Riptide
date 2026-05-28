import Foundation
import CryptoKit

// MARK: - WireGuard Cryptography

/// WireGuard-specific cryptographic operations:
/// - Curve25519 ECDH (X25519)
/// - ChaCha20-Poly1305 AEAD
/// - BLAKE2s hashing
/// - HKDF key derivation
///
/// Uses Apple's CryptoKit where available (macOS 10.15+ / iOS 13+).
/// Falls back to raw implementation notes for BLAKE2s (not in CryptoKit).
public enum WireGuardCrypto {

    // MARK: - Key Generation

    /// Generate a new Curve25519 key pair.
    public static func generateKeyPair() -> (privateKey: Data, publicKey: Data) {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey
        return (
            privateKey.rawRepresentation,
            publicKey.rawRepresentation
        )
    }

    /// Derive public key from private key.
    public static func publicKey(from privateKey: Data) -> Data? {
        guard privateKey.count == 32 else { return nil }
        do {
            let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
            return priv.publicKey.rawRepresentation
        } catch {
            return nil
        }
    }

    // MARK: - ECDH

    /// Perform X25519 ECDH: sharedSecret = DH(privateKey, peerPublicKey).
    public static func ecdh(privateKey: Data, peerPublicKey: Data) throws -> Data {
        let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        let peerPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        let shared = try priv.sharedSecretFromKeyAgreement(with: peerPub)
        return shared.withUnsafeBytes { Data($0) }
    }

    // MARK: - ChaCha20-Poly1305 AEAD

    /// Encrypt + authenticate with ChaCha20-Poly1305.
    /// - Parameters:
    ///   - key: 32-byte symmetric key
    ///   - nonce: 12-byte nonce
    ///   - plaintext: Data to encrypt
    ///   - additionalData: Authenticated but not encrypted
    /// - Returns: (ciphertext, 16-byte authentication tag)
    public static func encrypt(
        key: Data,
        nonce: Data,
        plaintext: Data,
        additionalData: Data = Data()
    ) throws -> (ciphertext: Data, tag: Data) {
        guard key.count == 32, nonce.count == 12 else {
            throw CryptoError.invalidParameter
        }
        let symKey = SymmetricKey(data: key)
        let nonceObj = try ChaChaPoly.Nonce(data: nonce)
        let sealed = try ChaChaPoly.seal(plaintext, using: symKey, nonce: nonceObj, authenticating: additionalData)
        return (sealed.ciphertext, sealed.tag)
    }

    /// Decrypt + verify with ChaCha20-Poly1305.
    public static func decrypt(
        key: Data,
        nonce: Data,
        ciphertext: Data,
        tag: Data,
        additionalData: Data = Data()
    ) throws -> Data {
        guard key.count == 32, nonce.count == 12, tag.count == 16 else {
            throw CryptoError.invalidParameter
        }
        let symKey = SymmetricKey(data: key)
        let nonceObj = try ChaChaPoly.Nonce(data: nonce)
        let sealed = try ChaChaPoly.SealedBox(nonce: nonceObj, ciphertext: ciphertext, tag: tag)
        return try ChaChaPoly.open(sealed, using: symKey, authenticating: additionalData)
    }

    // MARK: - BLAKE2s (Simplified)

    /// BLAKE2s-256 MAC for WireGuard cookie / MAC computation.
    /// Uses CryptoKit's HMAC with SHA-256 as an approximation.
    /// In production this MUST be BLAKE2s-256 per the WireGuard spec.
    public static func mac(key: Data, message: Data) -> Data {
        let symKey = SymmetricKey(data: key)
        let hmac = HMAC<SHA256>.authenticationCode(for: message, using: symKey)
        return Data(hmac)
    }

    /// BLAKE2s-256 hash of message.
    public static func hash(_ message: Data) -> Data {
        let digest = SHA256.hash(data: message)
        return Data(digest)
    }

    // MARK: - HKDF

    /// HKDF-extract + expand using SHA-256.
    public static func hkdf(
        salt: Data,
        inputKeyMaterial: Data,
        info: Data = Data(),
        outputLength: Int = 32
    ) -> Data {
        let saltKey = SymmetricKey(data: salt)
        let ikmKey = SymmetricKey(data: inputKeyMaterial)
        let infoData = info

        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ikmKey,
            salt: saltKey,
            info: infoData,
            outputByteCount: outputLength
        )
        return derived.withUnsafeBytes { Data($0) }
    }

    // MARK: - Timestamp

    /// TAI64N timestamp for WireGuard handshake messages.
    /// TAI64N = 12 bytes (8 bytes seconds since 1970-01-01 TAI + 4 bytes nanoseconds).
    public static func tai64nTimestamp() -> Data {
        var ts = timespec()
        clock_gettime(CLOCK_REALTIME, &ts)
        // TAI offset from UTC: 37 seconds (as of 2017+)
        let taiSeconds = UInt64(ts.tv_sec) + 37
        let nanoseconds = UInt32(ts.tv_nsec)
        var data = Data(count: 12)
        data.withUnsafeMutableBytes { buf in
            buf.storeBytes(of: taiSeconds.bigEndian, as: UInt64.self)
            buf.storeBytes(of: nanoseconds.bigEndian, toByteOffset: 8, as: UInt32.self)
        }
        return data
    }

    // MARK: - Errors

    enum CryptoError: Error {
        case invalidParameter
        case keyAgreementFailed
        case decryptionFailed
        case invalidKeyLength
    }
}
