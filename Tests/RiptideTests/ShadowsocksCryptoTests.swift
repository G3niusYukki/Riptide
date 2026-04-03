import Foundation
import Testing
import CryptoKit

@testable import Riptide

@Suite("Shadowsocks crypto provider")
struct ShadowsocksCryptoTests {
    @Test("HKDF derives subkey from password and salt for aes-256-gcm")
    func deriveSubkeyAES256GCM() throws {
        let provider = try ShadowsocksCryptoProvider(
            cipher: "aes-256-gcm",
            password: "test-password"
        )
        let salt = Data([UInt8](repeating: 0x01, count: 32))
        let subkey = try provider.deriveSubkey(salt: salt)

        #expect(subkey.count == 32)

        let inputKey = SymmetricKey(data: Data("test-password".utf8))
        let reference = HKDF<SHA256>.extract(inputKeyMaterial: inputKey, salt: salt)
        let expanded = HKDF<SHA256>.expand(
            pseudoRandomKey: reference,
            info: Data("ss-subkey".utf8),
            outputByteCount: 32
        )
        #expect(expanded.withUnsafeBytes { Data($0) } == subkey)
    }

    @Test("HKDF derives subkey from password and salt for aes-128-gcm")
    func deriveSubkeyAES128GCM() throws {
        let provider = try ShadowsocksCryptoProvider(
            cipher: "aes-128-gcm",
            password: "test-password"
        )
        let salt = Data([UInt8](repeating: 0x02, count: 32))
        let subkey = try provider.deriveSubkey(salt: salt)

        #expect(subkey.count == 16)
    }

    @Test("HKDF derives subkey for chacha20-ietf-poly1305")
    func deriveSubkeyChaCha20() throws {
        let provider = try ShadowsocksCryptoProvider(
            cipher: "chacha20-ietf-poly1305",
            password: "test-password"
        )
        let salt = Data([UInt8](repeating: 0x03, count: 32))
        let subkey = try provider.deriveSubkey(salt: salt)

        #expect(subkey.count == 32)
    }

    @Test("generates random salt of correct length for cipher")
    func generateSalt() throws {
        let provider256 = try ShadowsocksCryptoProvider(cipher: "aes-256-gcm", password: "pass")
        let salt256 = provider256.generateSalt()
        #expect(salt256.count == 32)

        let provider128 = try ShadowsocksCryptoProvider(cipher: "aes-128-gcm", password: "pass")
        let salt128 = provider128.generateSalt()
        #expect(salt128.count == 32)

        let providerChaCha = try ShadowsocksCryptoProvider(cipher: "chacha20-ietf-poly1305", password: "pass")
        let saltChaCha = providerChaCha.generateSalt()
        #expect(saltChaCha.count == 32)
    }

    @Test("nonce encodes counter in big-endian at correct offset")
    func nonceEncoding() throws {
        let provider = try ShadowsocksCryptoProvider(cipher: "aes-256-gcm", password: "pass")
        let nonce0 = provider.makeNonce(counter: 0)
        #expect(nonce0.count == 12)

        let nonce1 = provider.makeNonce(counter: 1)
        #expect(nonce1.count == 12)
        #expect(nonce0 != nonce1)

        let nonce255 = provider.makeNonce(counter: 255)
        #expect(nonce255[11] == 255)
        #expect(nonce255[10] == 0)
    }

    @Test("throws for unsupported cipher")
    func unsupportedCipher() {
        #expect(throws: ShadowsocksCryptoError.self) {
            _ = try ShadowsocksCryptoProvider(cipher: "rc4", password: "pass")
        }
    }
}

@Suite("Shadowsocks AEAD stream")
struct ShadowsocksAEADStreamTests {
    @Test("AEAD encrypt then decrypt round-trips data")
    func encryptDecryptRoundTrip() async throws {
        let provider = try ShadowsocksCryptoProvider(cipher: "aes-256-gcm", password: "test-pass")
        let salt = provider.generateSalt()
        let subkey = try provider.deriveSubkey(salt: salt)

        let plaintext = Data("Hello, Shadowsocks AEAD!".utf8)
        let encrypted = try ShadowsocksAEAD.encryptChunk(
            payload: plaintext,
            subkey: subkey,
            counter: 0,
            provider: provider
        )
        let decrypted = try ShadowsocksAEAD.decryptChunk(
            data: encrypted,
            subkey: subkey,
            counter: 0,
            provider: provider
        )

        #expect(decrypted.payload == plaintext)
    }

    @Test("AEAD encrypt produces salt + length header + encrypted payload")
    func encryptProducesCorrectFormat() async throws {
        let provider = try ShadowsocksCryptoProvider(cipher: "aes-256-gcm", password: "test-pass")
        let salt = provider.generateSalt()
        let subkey = try provider.deriveSubkey(salt: salt)

        let plaintext = Data([0x01, 0x02, 0x03])
        let encrypted = try ShadowsocksAEAD.encryptChunk(
            payload: plaintext,
            subkey: subkey,
            counter: 0,
            provider: provider
        )

        let lengthTotal = 2 + 12 + 16
        let payloadTotal = 3 + 12 + 16
        #expect(encrypted.count == lengthTotal + payloadTotal)
    }

    @Test("AEAD encrypt/decrypt works with chacha20-ietf-poly1305")
    func chaCha20RoundTrip() async throws {
        let provider = try ShadowsocksCryptoProvider(cipher: "chacha20-ietf-poly1305", password: "pass")
        let salt = provider.generateSalt()
        let subkey = try provider.deriveSubkey(salt: salt)

        let plaintext = Data("ChaCha20 test payload".utf8)
        let encrypted = try ShadowsocksAEAD.encryptChunk(
            payload: plaintext, subkey: subkey, counter: 2, provider: provider
        )
        let decrypted = try ShadowsocksAEAD.decryptChunk(
            data: encrypted, subkey: subkey, counter: 2, provider: provider
        )

        #expect(decrypted.payload == plaintext)
    }

    @Test("AEAD decrypt fails with wrong key")
    func decryptFailsWithWrongKey() async throws {
        let provider = try ShadowsocksCryptoProvider(cipher: "aes-256-gcm", password: "pass")
        let salt1 = Data([UInt8](repeating: 0x01, count: 32))
        let salt2 = Data([UInt8](repeating: 0x02, count: 32))
        let subkey1 = try provider.deriveSubkey(salt: salt1)
        let subkey2 = try provider.deriveSubkey(salt: salt2)

        let plaintext = Data("secret".utf8)
        let encrypted = try ShadowsocksAEAD.encryptChunk(
            payload: plaintext, subkey: subkey1, counter: 0, provider: provider
        )

        #expect(throws: Error.self) {
            _ = try ShadowsocksAEAD.decryptChunk(
                data: encrypted, subkey: subkey2, counter: 0, provider: provider
            )
        }
    }

    @Test("ShadowsocksStream sendHandshake produces salt + encrypted chunk")
    func streamSendHandshake() async throws {
        let innerSession = MockTransportSession(receiveQueue: [])
        let stream = try ShadowsocksStream(
            session: innerSession,
            cipher: "aes-256-gcm",
            password: "test-pass"
        )

        let preamble = Data([0x03, 0x0B] + "example.com".utf8 + [0x00, 0x50])
        try await stream.sendHandshake(preamble)

        let sent = await innerSession.sentFrames
        #expect(sent.count == 1)

        let frame = sent[0]
        let salt = frame.prefix(32)
        #expect(salt.count == 32)

        let afterSalt = frame.dropFirst(32)
        let provider = try ShadowsocksCryptoProvider(cipher: "aes-256-gcm", password: "test-pass")
        let subkey = try provider.deriveSubkey(salt: Data(salt))
        let decrypted = try ShadowsocksAEAD.decryptChunk(
            data: Data(afterSalt), subkey: subkey, counter: 0, provider: provider
        )
        #expect(decrypted.payload == preamble)
    }

    @Test("ShadowsocksStream send after handshake increments counter")
    func streamSendAfterHandshake() async throws {
        let innerSession = MockTransportSession(receiveQueue: [])
        let stream = try ShadowsocksStream(
            session: innerSession,
            cipher: "aes-256-gcm",
            password: "test-pass"
        )

        try await stream.sendHandshake(Data([0x01]))
        try await stream.send(Data("data".utf8))

        let sent = await innerSession.sentFrames
        #expect(sent.count == 2)
        #expect(sent[1].count > 0)
    }
}

@Suite("Shadowsocks AEAD end-to-end")
struct ShadowsocksAEADIntegrationTests {
    @Test("encrypt handshake and decrypt on server side")
    func ssHandshakeRoundTrip() async throws {
        let clientSession = MockTransportSession(receiveQueue: [])

        let clientStream = try ShadowsocksStream(
            session: clientSession,
            cipher: "aes-256-gcm",
            password: "test-password"
        )
        let proto = ShadowsocksProtocol()
        let preamble = try proto.makeConnectRequest(for: ConnectionTarget(host: "example.com", port: 443))
        try await clientStream.sendHandshake(preamble[0])

        let sentToServer = await clientSession.sentFrames
        #expect(sentToServer.count == 1)

        let salt = sentToServer[0].prefix(32)
        let provider = try ShadowsocksCryptoProvider(cipher: "aes-256-gcm", password: "test-password")
        let subkey = try provider.deriveSubkey(salt: Data(salt))

        let afterSalt = sentToServer[0].dropFirst(32)
        let decrypted = try ShadowsocksAEAD.decryptChunk(
            data: Data(afterSalt), subkey: subkey, counter: 0, provider: provider
        )

        #expect(decrypted.payload.count >= 3)
        #expect(decrypted.payload[0] == 0x03)
    }

    @Test("bidirectional SS AEAD encrypted communication")
    func bidirectionalEncryptedComm() async throws {
        let provider = try ShadowsocksCryptoProvider(cipher: "aes-256-gcm", password: "pass")

        let clientSalt = provider.generateSalt()
        let clientSubkey = try provider.deriveSubkey(salt: clientSalt)

        let serverSalt = provider.generateSalt()
        let serverSubkey = try provider.deriveSubkey(salt: serverSalt)

        let proto = ShadowsocksProtocol()
        let preamble = try proto.makeConnectRequest(for: ConnectionTarget(host: "a.com", port: 443))
        let clientEncrypted = try ShadowsocksAEAD.encryptChunk(
            payload: preamble[0], subkey: clientSubkey, counter: 0, provider: provider
        )
        let clientPacket = clientSalt + clientEncrypted

        let recvSalt = clientPacket.prefix(32)
        let recvSubkey = try provider.deriveSubkey(salt: Data(recvSalt))
        let recvAfterSalt = clientPacket.dropFirst(32)
        let decryptedPreamble = try ShadowsocksAEAD.decryptChunk(
            data: Data(recvAfterSalt), subkey: recvSubkey, counter: 0, provider: provider
        )
        #expect(decryptedPreamble.payload == preamble[0])

        let responseData = Data("HTTP/1.1 200 OK".utf8)
        let serverResponse = try ShadowsocksAEAD.encryptChunk(
            payload: responseData, subkey: serverSubkey, counter: 0, provider: provider
        )
        let serverPacket = serverSalt + serverResponse

        let clientRecvSalt = serverPacket.prefix(32)
        let clientRecvSubkey = try provider.deriveSubkey(salt: Data(clientRecvSalt))
        let clientRecvAfterSalt = serverPacket.dropFirst(32)
        let clientDecrypted = try ShadowsocksAEAD.decryptChunk(
            data: Data(clientRecvAfterSalt), subkey: clientRecvSubkey, counter: 0, provider: provider
        )
        #expect(clientDecrypted.payload == responseData)
    }

    @Test("multiple chunks encrypt/decrypt with incrementing counter")
    func multipleChunksWithCounter() async throws {
        let provider = try ShadowsocksCryptoProvider(cipher: "aes-128-gcm", password: "multi-test")
        let salt = provider.generateSalt()
        let subkey = try provider.deriveSubkey(salt: salt)

        let chunk1 = Data("first chunk".utf8)
        let chunk2 = Data("second chunk".utf8)
        let chunk3 = Data("third chunk".utf8)

        let enc1 = try ShadowsocksAEAD.encryptChunk(payload: chunk1, subkey: subkey, counter: 0, provider: provider)
        let enc2 = try ShadowsocksAEAD.encryptChunk(payload: chunk2, subkey: subkey, counter: 2, provider: provider)
        let enc3 = try ShadowsocksAEAD.encryptChunk(payload: chunk3, subkey: subkey, counter: 4, provider: provider)

        let dec1 = try ShadowsocksAEAD.decryptChunk(data: enc1, subkey: subkey, counter: 0, provider: provider)
        let dec2 = try ShadowsocksAEAD.decryptChunk(data: enc2, subkey: subkey, counter: 2, provider: provider)
        let dec3 = try ShadowsocksAEAD.decryptChunk(data: enc3, subkey: subkey, counter: 4, provider: provider)

        #expect(dec1.payload == chunk1)
        #expect(dec2.payload == chunk2)
        #expect(dec3.payload == chunk3)
    }
}
