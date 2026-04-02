import Foundation

public actor ShadowsocksStream {
    private let session: any TransportSession
    private let provider: ShadowsocksCryptoProvider
    private var sendCounter: UInt64 = 0
    private var recvCounter: UInt64 = 0
    private var recvBuffer = Data()
    private var sendSubkey: Data?
    private var recvSubkey: Data?

    public init(session: any TransportSession, cipher: String, password: String) throws {
        self.session = session
        self.provider = try ShadowsocksCryptoProvider(cipher: cipher, password: password)
    }

    public func sendHandshake(_ preamble: Data) async throws {
        let salt = provider.generateSalt()
        sendSubkey = try provider.deriveSubkey(salt: salt)
        sendCounter = 0

        let encryptedChunk = try ShadowsocksAEAD.encryptChunk(
            payload: preamble,
            subkey: sendSubkey!,
            counter: sendCounter,
            provider: provider
        )
        sendCounter += 2

        try await session.send(salt + encryptedChunk)
    }

    public func send(_ data: Data) async throws {
        guard let subkey = sendSubkey else {
            throw ShadowsocksCryptoError.encryptionFailed("call sendHandshake first")
        }
        let encrypted = try ShadowsocksAEAD.encryptChunk(
            payload: data, subkey: subkey, counter: sendCounter, provider: provider
        )
        sendCounter += 2
        try await session.send(encrypted)
    }

    public func receive() async throws -> Data {
        if recvSubkey == nil {
            try await consumeRecvSalt()
        }

        while true {
            if let result = tryDecryptNextChunk() {
                return result
            }
            let chunk = try await session.receive()
            guard !chunk.isEmpty else { return Data() }
            recvBuffer.append(chunk)
        }
    }

    private func consumeRecvSalt() async throws {
        let saltLength = provider.cipher.saltLength
        while recvBuffer.count < saltLength {
            let chunk = try await session.receive()
            guard !chunk.isEmpty else {
                throw ShadowsocksCryptoError.decryptionFailed("remote closed before sending salt")
            }
            recvBuffer.append(chunk)
        }
        let salt = recvBuffer.prefix(saltLength)
        recvBuffer.removeFirst(saltLength)
        recvSubkey = try provider.deriveSubkey(salt: Data(salt))
    }

    private func tryDecryptNextChunk() -> Data? {
        guard let subkey = recvSubkey else { return nil }
        guard let result = try? ShadowsocksAEAD.decryptChunk(
            data: recvBuffer, subkey: subkey, counter: recvCounter, provider: provider
        ) else { return nil }
        recvBuffer.removeFirst(result.consumed)
        recvCounter += 2
        return result.payload
    }

    public func close() async {
        await session.close()
    }
}
