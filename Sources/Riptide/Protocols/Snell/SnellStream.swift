import Foundation
import CryptoKit
import CommonCrypto
import Network

// MARK: - Snell Protocol

/// Snell protocol implementation.
///
/// Snell is a simple proxy protocol that uses:
/// - Version byte (currently v2 or v3)
/// - Command byte (CONNECT = 0x01)
/// - Random 16 bytes
/// - Address type + address + port
/// - PSK-HMAC for authentication
///
/// Snell v3 adds AEAD encryption using ChaCha20-Poly1305.
public final class SnellStream {

    // MARK: - Errors

    public enum SnellError: Error, Equatable, Sendable {
        case missingParameter(String)
        case handshakeFailed(String)
        case invalidVersion
        case encryptionFailed(String)
        case decryptionFailed(String)

        public var localizedDescription: String {
            switch self {
            case .missingParameter(let msg): return "Missing parameter: \(msg)"
            case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
            case .invalidVersion: return "Invalid Snell version"
            case .encryptionFailed(let msg): return "Encryption failed: \(msg)"
            case .decryptionFailed(let msg): return "Decryption failed: \(msg)"
            }
        }
    }

    // MARK: - State

    private let session: any TransportSession
    private let password: String
    private let version: Int

    public init(session: any TransportSession, password: String, version: Int = 2) {
        self.session = session
        self.password = password
        self.version = version
    }

    // MARK: - Public

    /// Perform the Snell handshake.
    public func connect(to target: ConnectionTarget) async throws {
        switch version {
        case 2:
            try await performV2Handshake(target: target)
        case 3:
            try await performV3Handshake(target: target)
        default:
            throw SnellError.invalidVersion
        }
    }

    /// Send data through the Snell tunnel.
    public func send(_ data: Data) async throws {
        switch version {
        case 2:
            try await session.send(data)
        case 3:
            let encrypted = try encryptPayload(data)
            try await session.send(encrypted)
        default:
            throw SnellError.invalidVersion
        }
    }

    /// Receive data from the Snell tunnel.
    public func receive() async throws -> Data {
        let data = try await session.receive()
        switch version {
        case 2:
            return data
        case 3:
            return try decryptPayload(data)
        default:
            throw SnellError.invalidVersion
        }
    }

    /// Close the session.
    public func close() async {
        await session.close()
    }

    // MARK: - V2 Handshake

    /// Snell v2 handshake.
    ///
    /// Format:
    /// - Version (1 byte): 0x02
    /// - Command (1 byte): 0x01 (CONNECT)
    /// - Random (16 bytes)
    /// - Address type (1 byte): 0x01=IPv4, 0x03=domain, 0x04=IPv6
    /// - Address (variable)
    /// - Port (2 bytes, big-endian)
    /// - HMAC-SHA256 (32 bytes): HMAC(PSK, version + command + random + address)
    private func performV2Handshake(target: ConnectionTarget) async throws {
        var request = Data()

        // Version
        request.append(0x02)

        // Command (CONNECT)
        request.append(0x01)

        // Random 16 bytes
        var randomBytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess else {
            throw SnellError.handshakeFailed("failed to generate random bytes")
        }
        request.append(contentsOf: randomBytes)

        // Address
        try encodeAddress(for: target, into: &request)

        // Port
        let port = UInt16(target.port)
        request.append(UInt8(port >> 8))
        request.append(UInt8(port & 0xFF))

        // HMAC-SHA256
        let hmac = try computeHMAC(for: request)
        request.append(contentsOf: hmac)

        try await session.send(request)

        // Read response (1 byte: status)
        let response = try await session.receive()
        guard !response.isEmpty else {
            throw SnellError.handshakeFailed("empty response")
        }

        let status = response[0]
        if status != 0x00 {
            throw SnellError.handshakeFailed("server returned error status: \(status)")
        }
    }

    // MARK: - V3 Handshake

    /// Snell v3 handshake with AEAD encryption.
    ///
    /// Format (encrypted):
    /// - Version (1 byte): 0x03
    /// - Command (1 byte): 0x01 (CONNECT)
    /// - Random (16 bytes)
    /// - Address (variable)
    /// - Port (2 bytes)
    /// All encrypted with ChaCha20-Poly1305 using PSK-derived key.
    private func performV3Handshake(target: ConnectionTarget) async throws {
        var plaintext = Data()

        // Version
        plaintext.append(0x03)

        // Command (CONNECT)
        plaintext.append(0x01)

        // Random 16 bytes
        var randomBytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess else {
            throw SnellError.handshakeFailed("failed to generate random bytes")
        }
        plaintext.append(contentsOf: randomBytes)

        // Address
        try encodeAddress(for: target, into: &plaintext)

        // Port
        let port = UInt16(target.port)
        plaintext.append(UInt8(port >> 8))
        plaintext.append(UInt8(port & 0xFF))

        // Encrypt with AEAD
        let encrypted = try encryptPayload(plaintext)
        try await session.send(encrypted)

        // Read and decrypt response
        let response = try await session.receive()
        let _ = try decryptPayload(response)
    }

    // MARK: - Encryption (v3)

    private func encryptPayload(_ data: Data) throws -> Data {
        // Derive 32-byte key from password using SHA256
        let keyData = password.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: keyData)
        let symmetricKey = SymmetricKey(data: hash)

        // Generate nonce (12 bytes for ChaCha20-Poly1305)
        var nonce = [UInt8](repeating: 0, count: 12)
        guard SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce) == errSecSuccess else {
            throw SnellError.encryptionFailed("failed to generate nonce")
        }

        let seal = try ChaChaPoly.seal(data, using: symmetricKey, nonce: ChaChaPoly.Nonce(data: Data(nonce)))
        // seal.combined already contains nonce + ciphertext + tag
        return seal.combined
    }

    private func decryptPayload(_ data: Data) throws -> Data {
        guard data.count > 12 else {
            throw SnellError.decryptionFailed("data too short")
        }

        // seal.combined format: nonce (12 bytes) + ciphertext + tag (16 bytes)
        let nonce = data.prefix(12)
        let ciphertextWithTag = data.suffix(from: 12)

        let keyData = password.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: keyData)
        let symmetricKey = SymmetricKey(data: hash)

        let sealedBox = try ChaChaPoly.SealedBox(combined: Data(nonce) + ciphertextWithTag)
        return try ChaChaPoly.open(sealedBox, using: symmetricKey)
    }

    // MARK: - Helpers

    private func encodeAddress(for target: ConnectionTarget, into data: inout Data) throws {
        let address = target.host
        if let _ = IPv4AddressParser.parse(address) {
            // IPv4
            data.append(0x01)
            let octets = address.split(separator: ".").compactMap { UInt8($0) }
            guard octets.count == 4 else {
                throw SnellError.handshakeFailed("invalid IPv4 address")
            }
            data.append(contentsOf: octets)
        } else if address.contains(":") {
            // IPv6
            data.append(0x04)
            // Simplified: just use placeholder for IPv6
            data.append(contentsOf: [UInt8](repeating: 0, count: 16))
        } else {
            // Domain
            guard address.utf8.count <= 255 else {
                throw SnellError.handshakeFailed("domain too long")
            }
            data.append(0x03)
            data.append(UInt8(address.utf8.count))
            data.append(contentsOf: address.utf8)
        }
    }

    private func computeHMAC(for data: Data) throws -> [UInt8] {
        let keyData = password.data(using: .utf8) ?? Data()
        var mac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyData.withUnsafeBytes { keyPtr in
            data.withUnsafeBytes { dataPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                       keyPtr.baseAddress, keyData.count,
                       dataPtr.baseAddress, data.count,
                       &mac)
            }
        }
        return mac
    }
}
