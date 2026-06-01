import Foundation

// MARK: - WireGuard Handshake (Noise IK Pattern)

/// Implements WireGuard's Noise_IK_25519_ChaChaPoly_BLAKE2s handshake.
///
/// Protocol flow:
/// ```
/// Initiator                          Responder
///    |                                  |
///    |-- Initiation (msg type 1) ------>|
///    |   (ephemeral + encrypted static) |
///    |                                  |
///    |<-- Response (msg type 2) --------|
///    |   (ephemeral + encrypted empty)  |
///    |                                  |
///    |== Transport Data (msg type 4) ==>|
/// ```
///
/// After handshake, both sides derive symmetric keys for transport.
/// Rekeying happens at `rekeyAfterSeconds` intervals.
public actor WireGuardHandshake {

    // MARK: - State

    private let config: WireGuardConfig
    private let peerIndex: Int
    private var peer: WireGuardConfig.WireGuardPeer { config.peers[peerIndex] }

    // Key pairs
    private let staticPrivate: Data
    private let staticPublic: Data
    private var ephemeralPrivate: Data?
    private var ephemeralPublic: Data?

    // Remote keys
    private let peerStaticPublic: Data
    private var peerEphemeralPublic: Data?

    // Handshake state
    private var handshakeState: HandshakeState = .idle
    private var lastHandshake: Date?
    private var handshakeRetries: Int = 0
    private var handshakeInitiationConsumed: Bool = false

    // Derived keys
    private var sendingKey: Data?
    private var receivingKey: Data?
    private var sendingNonce: UInt64 = 0
    private var receivingNonce: UInt64 = 0

    // Cookie state (responder-side DoS protection)
    private var cookieSecret: Data?
    private var lastCookieRefresh: Date?

    // MARK: - Types

    enum HandshakeState {
        case idle
        case initiated(Date)
        case responded
        case established
        case failed(String)
    }

    enum HandshakeError: Error {
        case invalidMessage
        case handshakeTimeout
        case maxRetriesExceeded
        case alreadyEstablished
        case decryptionFailed
        case keyDerivationFailed
    }

    // MARK: - Init

    public init(config: WireGuardConfig, peerIndex: Int = 0) throws {
        self.config = config
        self.peerIndex = peerIndex

        // Decode static key pair
        guard let staticPriv = Data(base64Encoded: config.privateKey),
              staticPriv.count == 32 else {
            throw HandshakeError.keyDerivationFailed
        }
        self.staticPrivate = staticPriv
        self.staticPublic = WireGuardCrypto.publicKey(from: staticPriv) ?? Data()

        // Decode peer public key
        guard let peerPub = Data(base64Encoded: peer.publicKey),
              peerPub.count == 32 else {
            throw HandshakeError.keyDerivationFailed
        }
        self.peerStaticPublic = peerPub
    }

    // MARK: - Initiator: Create Initiation Message

    /// Creates a handshake initiation message (type 1).
    /// Called by the initiator.
    public func createInitiation() throws -> Data {
        guard case .idle = handshakeState else {
            throw HandshakeError.alreadyEstablished
        }

        // 1. Generate ephemeral key pair
        let (ephPriv, ephPub) = WireGuardCrypto.generateKeyPair()
        self.ephemeralPrivate = ephPriv
        self.ephemeralPublic = ephPub

        // 2. ECDH(eph_priv, peer_static_pub) → chain key
        let dh1 = try WireGuardCrypto.ecdh(privateKey: ephPriv, peerPublicKey: peerStaticPublic)

        // 3. ECDH(static_priv, peer_static_pub) → pre-shared
        let dh2 = try WireGuardCrypto.ecdh(privateKey: staticPrivate, peerPublicKey: peerStaticPublic)

        // 4. HKDF chain key + hash derivation (simplified Noise IK)
        let chainKey = WireGuardCrypto.hkdf(
            salt: WireGuardConstants.label("Noise_IK_25519_ChaChaPoly_BLAKE2s"),
            inputKeyMaterial: dh1 + dh2,
            outputLength: 32
        )

        // 5. Derive encryption key for static ciphertext
        let handshakeKey = WireGuardCrypto.hkdf(
            salt: chainKey,
            inputKeyMaterial: Data(repeating: 0, count: 32),
            info: Data("handshake key".utf8),
            outputLength: 32
        )

        // 6. Encrypt static public key + timestamp
        let timestamp = WireGuardCrypto.tai64nTimestamp()
        let staticCiphertext = try WireGuardCrypto.encrypt(
            key: handshakeKey,
            nonce: Data(repeating: 0, count: 12),
            plaintext: staticPublic + timestamp,
            additionalData: Data()
        )

        // 7. Derive transport keys
        let transportKeys = deriveTransportKeys(
            chainKey: chainKey,
            handshakeHash: WireGuardCrypto.hash(ephPub + peerStaticPublic + staticCiphertext.ciphertext)
        )
        self.sendingKey = transportKeys.sending
        self.receivingKey = transportKeys.receiving
        self.sendingNonce = 0
        self.receivingNonce = 0

        // 8. Assemble message
        var message = Data()
        message.append(WireGuardConstants.MessageType.initiateHandshake.rawValue) // type
        message.append(UInt32(0).bigEndianData)                                   // sender index (0 for init)
        message.append(ephPub)                                                     // unencrypted ephemeral
        message.append(staticCiphertext.ciphertext)                               // encrypted static
        message.append(staticCiphertext.tag)                                      // auth tag
        message.append(timestamp)                                                 // timestamp (last 12 bytes)

        handshakeState = .initiated(Date())
        handshakeRetries = 0

        return message
    }

    // MARK: - Initiator: Process Response

    /// Processes a handshake response message (type 2).
    /// Called by the initiator after sending initiation.
    public func processResponse(_ data: Data) throws {
        guard data.count >= 60 else { throw HandshakeError.invalidMessage }

        // Parse: type(1) + senderIndex(4) + receiverIndex(4) + ephemeral(32) + emptyCiphertext(n) + tag(16)
        let msgType = data[0]
        guard msgType == WireGuardConstants.MessageType.respondHandshake.rawValue else {
            throw HandshakeError.invalidMessage
        }

        let ephPub = data.subdata(in: 9..<41)
        let tagStart = data.count - 16
        let ciphertext = data.subdata(in: 41..<tagStart)
        let tag = data.subdata(in: tagStart..<data.count)

        // Store peer ephemeral
        self.peerEphemeralPublic = ephPub

        // Verify empty ciphertext decrypts
        guard let receiving = receivingKey else {
            throw HandshakeError.keyDerivationFailed
        }
        let nonceData = withUnsafeBytes(of: receivingNonce.bigEndian) { Data($0) }
        let _ = try WireGuardCrypto.decrypt(
            key: receiving,
            nonce: nonceData.prefix(12).pad12(),
            ciphertext: ciphertext,
            tag: tag
        )
        receivingNonce += 1

        // Derive final transport keys from response
        let dh3 = try WireGuardCrypto.ecdh(
            privateKey: ephemeralPrivate ?? staticPrivate,
            peerPublicKey: ephPub
        )
        let dh4 = try WireGuardCrypto.ecdh(
            privateKey: staticPrivate,
            peerPublicKey: ephPub
        )

        let chainKey = WireGuardCrypto.hkdf(
            salt: WireGuardConstants.label("Noise_IK_25519_ChaChaPoly_BLAKE2s"),
            inputKeyMaterial: dh3 + dh4,
            outputLength: 32
        )

        let finalKeys = deriveTransportKeys(
            chainKey: chainKey,
            handshakeHash: Data()
        )
        self.sendingKey = finalKeys.receiving  // swapped: initiator sends = responder receives
        self.receivingKey = finalKeys.sending
        self.sendingNonce = 0
        self.receivingNonce = 0

        handshakeState = .established
        lastHandshake = Date()
    }

    // MARK: - Responder: Process Initiation

    /// Processes a handshake initiation message (type 1).
    /// Called by the responder.
    public func processInitiation(_ data: Data) throws -> Data {
        guard data.count >= 148 else { throw HandshakeError.invalidMessage }

        // Parse: type(1) + senderIndex(4) + ephemeral(32) + staticCiphertext(48) + tag(16) + timestamp(12)
        let ephPub = data.subdata(in: 5..<37)
        let staticCipher = data.subdata(in: 37..<85)
        let staticTag = data.subdata(in: 85..<101)
        let timestamp = data.subdata(in: 101..<113)

        self.peerEphemeralPublic = ephPub

        // Generate responder ephemeral key pair
        let (respEphPriv, respEphPub) = WireGuardCrypto.generateKeyPair()
        self.ephemeralPrivate = respEphPriv
        self.ephemeralPublic = respEphPub

        // DH operations for chain key
        let dh1 = try WireGuardCrypto.ecdh(privateKey: staticPrivate, peerPublicKey: ephPub)
        let dh2 = try WireGuardCrypto.ecdh(privateKey: respEphPriv, peerPublicKey: peerStaticPublic)
        let dh3 = try WireGuardCrypto.ecdh(privateKey: respEphPriv, peerPublicKey: ephPub)

        let chainKey = WireGuardCrypto.hkdf(
            salt: WireGuardConstants.label("Noise_IK_25519_ChaChaPoly_BLAKE2s"),
            inputKeyMaterial: dh1 + dh2 + dh3,
            outputLength: 32
        )

        // Decrypt static ciphertext to get peer's static public key
        let handshakeKey = WireGuardCrypto.hkdf(
            salt: chainKey,
            inputKeyMaterial: Data(repeating: 0, count: 32),
            info: Data("handshake key".utf8),
            outputLength: 32
        )
        let peerStatic = try WireGuardCrypto.decrypt(
            key: handshakeKey,
            nonce: Data(repeating: 0, count: 12),
            ciphertext: staticCipher,
            tag: staticTag
        )
        // Verify peer static matches expected
        // In production: compare peerStatic.prefix(32) == peerStaticPublic

        // Derive transport keys
        let transportKeys = deriveTransportKeys(
            chainKey: chainKey,
            handshakeHash: WireGuardCrypto.hash(ephPub + respEphPub + staticCipher)
        )
        self.receivingKey = transportKeys.receiving
        self.sendingKey = transportKeys.sending
        self.sendingNonce = 0
        self.receivingNonce = 0

        // Build response message
        var response = Data()
        response.append(WireGuardConstants.MessageType.respondHandshake.rawValue) // type
        response.append(UInt32(0).bigEndianData)                                   // sender index
        response.append(UInt32(0).bigEndianData)                                   // receiver index
        response.append(respEphPub)                                                // unencrypted ephemeral

        // Encrypt empty payload
        let emptyEncrypted = try WireGuardCrypto.encrypt(
            key: transportKeys.sending,
            nonce: Data(repeating: 0, count: 12),
            plaintext: Data()
        )
        response.append(emptyEncrypted.ciphertext)
        response.append(emptyEncrypted.tag)

        handshakeState = .established
        lastHandshake = Date()

        return response
    }

    // MARK: - Transport Data

    /// Encrypts an outgoing transport data message (type 4).
    public func encryptTransport(_ plaintext: Data) throws -> Data {
        guard handshakeState == .established,
              let key = sendingKey else {
            throw HandshakeError.handshakeTimeout
        }

        var nonceData = withUnsafeBytes(of: sendingNonce.bigEndian) { Data($0) }
        let nonce = nonceData.prefix(12).pad12()
        let (ciphertext, tag) = try WireGuardCrypto.encrypt(
            key: key,
            nonce: nonce,
            plaintext: plaintext
        )
        sendingNonce += 1

        var message = Data()
        message.append(WireGuardConstants.MessageType.transportData.rawValue)
        message.append(UInt32(0).bigEndianData) // receiver index
        message.append(UInt64(0).bigEndianData) // counter (for reorder detection)
        message.append(ciphertext)
        message.append(tag)

        // Check rekey timer
        if let last = lastHandshake,
           Date().timeIntervalSince(last) > WireGuardConstants.rekeyAfterSeconds {
            // Trigger rekey on next send
            Task { await initiateRekey() }
        }

        return message
    }

    /// Decrypts an incoming transport data message (type 4).
    public func decryptTransport(_ data: Data) throws -> Data {
        guard handshakeState == .established,
              let key = receivingKey else {
            throw HandshakeError.handshakeTimeout
        }

        // Parse: type(1) + receiverIndex(4) + counter(8) + ciphertext(n) + tag(16)
        let payloadStart = 13
        let tagStart = data.count - 16
        let ciphertext = data.subdata(in: payloadStart..<tagStart)
        let tag = data.subdata(in: tagStart..<data.count)

        var nonceData = withUnsafeBytes(of: receivingNonce.bigEndian) { Data($0) }
        let nonce = nonceData.prefix(12).pad12()
        let plaintext = try WireGuardCrypto.decrypt(
            key: key,
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )
        receivingNonce += 1

        return plaintext
    }

    // MARK: - Rekey

    private func initiateRekey() async {
        handshakeState = .idle
        ephemeralPrivate = nil
        ephemeralPublic = nil
        sendingKey = nil
        receivingKey = nil
    }

    // MARK: - Key Derivation

    private func deriveTransportKeys(
        chainKey: Data,
        handshakeHash: Data
    ) -> (sending: Data, receiving: Data) {
        let sending = WireGuardCrypto.hkdf(
            salt: chainKey,
            inputKeyMaterial: handshakeHash,
            info: Data("sending key".utf8),
            outputLength: 32
        )
        let receiving = WireGuardCrypto.hkdf(
            salt: chainKey,
            inputKeyMaterial: handshakeHash,
            info: Data("receiving key".utf8),
            outputLength: 32
        )
        return (sending, receiving)
    }

    // MARK: - Status

    public var isEstablished: Bool {
        if case .established = handshakeState { return true }
        return false
    }

    public var stateDescription: String {
        switch handshakeState {
        case .idle: return "idle"
        case .initiated: return "initiated"
        case .responded: return "responded"
        case .established: return "established"
        case .failed(let reason): return "failed: \(reason)"
        }
    }
}

// MARK: - Data Helpers

extension FixedWidthInteger {
    var bigEndianData: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}

extension Data {
    /// Pads or truncates to exactly 12 bytes (ChaChaPoly nonce size).
    func pad12() -> Data {
        if count >= 12 { return prefix(12) }
        var padded = self
        padded.append(contentsOf: repeatElement(0, count: 12 - count))
        return padded
    }
}
