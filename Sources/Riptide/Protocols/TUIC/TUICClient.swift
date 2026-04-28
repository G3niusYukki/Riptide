import Foundation
import CryptoKit
import Network
import CommonCrypto

/// TUIC protocol client implementation.
/// TUIC (Transparent UDP and ICMP over QUIC) uses QUIC transport with
/// UUID + password authentication and stream multiplexing.
@available(macOS 14.0, *)
public actor TUICClient {
    private let config: TUICConfig
    private var connection: NWConnection?
    private var isConnected = false
    private var nextStreamID: UInt16 = 0

    public init(config: TUICConfig) {
        self.config = config
    }

    /// Establishes QUIC connection and performs authentication handshake.
    public func connect() async throws -> TUICConnection {
        guard !isConnected else {
            return TUICConnection(client: self)
        }

        // Create QUIC connection
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(config.server),
            port: NWEndpoint.Port(rawValue: UInt16(config.port))!
        )

        let quicOptions = NWProtocolQUIC.Options()
        if let alpn = config.alpn, !alpn.isEmpty {
            quicOptions.alpn = alpn
        } else {
            quicOptions.alpn = ["tuic"]
        }
        quicOptions.initialMaxStreamsBidirectional = 100
        quicOptions.initialMaxData = 10 * 1024 * 1024

        let parameters = NWParameters(quic: quicOptions)
        if config.zeroRTTHandshake {
            parameters.allowFastOpen = true
        }
        parameters.requiredInterfaceType = .other

        let conn = NWConnection(to: endpoint, using: parameters)
        self.connection = conn

        // Connect
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    conn.stateUpdateHandler = nil
                    continuation.resume(throwing: TUICError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    conn.stateUpdateHandler = nil
                    continuation.resume(throwing: TUICError.connectionFailed("cancelled"))
                default:
                    break
                }
            }
            conn.start(queue: .global())
        }

        // Perform authentication handshake
        try await performAuthHandshake()

        isConnected = true
        return TUICConnection(client: self)
    }

    /// Opens a new bidirectional stream for TCP data transfer.
    public func openStream(to target: ConnectionTarget) async throws -> TUICStream {
        guard isConnected, let conn = connection else {
            throw TUICError.notConnected
        }

        // Create a new QUIC stream for this TCP connection
        let streamID = nextStreamID
        nextStreamID += 1

        // Build CONNECT command
        var connectCmd = Data()
        connectCmd.append(0x01) // cmd: CONNECT
        connectCmd.append(try encodeAddress(target))

        // Send connect command on a new QUIC stream
        // NWConnection doesn't expose individual QUIC stream APIs directly.
        // We use a separate NWConnection approach: send the connect cmd
        // framed with stream ID, then read the response.
        let streamData = try await sendAndReceiveStream(connection: conn, streamID: streamID, command: connectCmd)

        return TUICStream(connection: conn, streamID: streamID, initialData: streamData)
    }

    /// Disconnects from the server.
    public func disconnect() async {
        isConnected = false
        connection?.cancel()
        connection = nil
    }

    // MARK: - Private

    private func performAuthHandshake() async throws {
        guard let conn = connection else {
            throw TUICError.notConnected
        }

        // TUIC v5 auth: version(1) + cmd(1) + uuid(16) + token_length(2) + token
        let uuidData = withUnsafeBytes(of: config.uuid.uuid) { Data($0) }

        // Token = HMAC-SHA256(password, "tuic-auth" + uuid)
        var tokenInput = Data("tuic-auth".utf8)
        tokenInput.append(uuidData)
        let authKey = SymmetricKey(data: Data(config.password.utf8))
        let token = HMAC<SHA256>.authenticationCode(for: tokenInput, using: authKey)
        let tokenData = Data(token)

        var authCmd = Data()
        authCmd.append(0x05) // version 5
        authCmd.append(0x00) // cmd: AUTH
        authCmd.append(uuidData) // 16 bytes
        var tokenLen = UInt16(tokenData.count)
        authCmd.append(UInt8(tokenLen >> 8))
        authCmd.append(UInt8(tokenLen & 0xFF))
        authCmd.append(tokenData)

        // Send auth command as the first QUIC stream (stream 0)
        let response = try await sendAndReceiveStream(connection: conn, streamID: 0, command: authCmd)

        guard !response.isEmpty, response[0] == 0x00 else {
            throw TUICError.authenticationFailed
        }
    }

    /// Sends a command on a QUIC stream and receives the response.
    /// Since NWConnection doesn't expose individual QUIC stream APIs,
    /// we use a simple framing protocol: [streamID:2][length:2][data][length:2][response]
    private func sendAndReceiveStream(
        connection: NWConnection,
        streamID: UInt16,
        command: Data
    ) async throws -> Data {
        // Frame: [streamID:2][cmd_length:2][command][response_length:2][response]
        var frame = Data()
        frame.append(UInt8(streamID >> 8))
        frame.append(UInt8(streamID & 0xFF))
        let cmdLen = UInt16(command.count)
        frame.append(UInt8(cmdLen >> 8))
        frame.append(UInt8(cmdLen & 0xFF))
        frame.append(command)

        // Send
        try await sendOnConnection(connection, data: frame)

        // Receive response
        let response = try await receiveOnConnection(connection)

        guard response.count >= 2 else {
            throw TUICError.connectionFailed("short response")
        }
        let respLen = Int(UInt16(response[0]) << 8 | UInt16(response[1]))
        guard response.count >= 2 + respLen else {
            throw TUICError.connectionFailed("truncated response")
        }
        return response.subdata(in: 2..<2 + respLen)
    }

    private func sendOnConnection(_ connection: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: TUICError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receiveOnConnection(_ connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: TUICError.connectionFailed(error.localizedDescription))
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    private func encodeAddress(_ target: ConnectionTarget) throws -> Data {
        var data = Data()
        let port = UInt16(target.port)

        if let ipv4 = parseIPv4(target.host) {
            data.append(0x01) // ATYP IPv4
            data.append(contentsOf: ipv4)
        } else if target.host.contains(":") {
            var sin6 = sockaddr_in6()
            let parsed = target.host.withCString { inet_pton(AF_INET6, $0, &sin6.sin6_addr) }
            if parsed == 1 {
                data.append(0x04) // ATYP IPv6
                withUnsafeBytes(of: sin6.sin6_addr) { data.append(contentsOf: $0) }
            } else {
                throw TUICError.invalidConfiguration("invalid IPv6 address")
            }
        } else {
            let hostData = Data(target.host.utf8)
            guard hostData.count <= 255 else {
                throw TUICError.invalidConfiguration("domain too long")
            }
            data.append(0x03) // ATYP Domain
            data.append(UInt8(hostData.count))
            data.append(hostData)
        }

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

/// Represents an established TUIC connection.
@available(macOS 14.0, *)
public struct TUICConnection: Sendable {
    let client: TUICClient

    public func openStream(to target: ConnectionTarget) async throws -> TUICStream {
        try await client.openStream(to: target)
    }

    public func close() async {
        await client.disconnect()
    }
}

/// Individual TUIC stream for TCP data transfer over QUIC.
@available(macOS 14.0, *)
public actor TUICStream {
    private let connection: NWConnection
    private let streamID: UInt16
    private var isClosed = false
    private var recvBuffer = Data()

    init(connection: NWConnection, streamID: UInt16, initialData: Data) {
        self.connection = connection
        self.streamID = streamID
        self.recvBuffer = initialData
    }

    public func send(_ data: Data) async throws {
        guard !isClosed else { throw TUICError.streamClosed }

        // Frame data with stream ID
        var frame = Data()
        frame.append(UInt8(streamID >> 8))
        frame.append(UInt8(streamID & 0xFF))
        let length = UInt16(data.count)
        frame.append(UInt8(length >> 8))
        frame.append(UInt8(length & 0xFF))
        frame.append(data)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: TUICError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func receive() async throws -> Data {
        guard !isClosed else { throw TUICError.streamClosed }

        if !recvBuffer.isEmpty {
            let data = recvBuffer
            recvBuffer = Data()
            return data
        }

        // Read from connection and extract data for this stream
        let raw = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: TUICError.connectionFailed(error.localizedDescription))
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }

        guard raw.count >= 4 else { return Data() }
        let length = Int(UInt16(raw[2]) << 8 | UInt16(raw[3]))
        guard raw.count >= 4 + length else { return Data() }
        return raw.subdata(in: 4..<4 + length)
    }

    public func close() {
        isClosed = true
    }
}
