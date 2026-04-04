import Foundation
import CryptoKit

public enum Hysteria2Error: Error, Equatable, Sendable {
    case handshakeFailed(String)
    case connectionFailed(String)
    case malformedPacket
    case quicNotAvailable
}

/// Hysteria2 protocol stream.
///
/// Hysteria2 runs over QUIC (not TCP). This implementation:
/// - Creates a QUIC connection to the server
/// - Opens a bidirectional stream for each connection
/// - Performs the Hysteria2 auth handshake (HMAC-SHA256 token)
/// - Sends/receives data over the QUIC stream
public actor Hysteria2Stream: Sendable {

    /// The underlying QUIC session.
    private let quicSession: QUICTransportSession?
    /// Fallback: a generic transport session (for TCP-based fallback).
    private let fallbackSession: (any TransportSession)?
    private let password: String
    private let obfuscated: Bool
    private var connected: Bool = false

    public init(session: any TransportSession, password: String, obfuscated: Bool = false) {
        self.quicSession = nil
        self.fallbackSession = session
        self.password = password
        self.obfuscated = obfuscated
    }

    /// Create a Hysteria2 stream with a QUIC transport.
    public init(quicSession: QUICTransportSession, password: String, obfuscated: Bool = false) {
        self.quicSession = quicSession
        self.fallbackSession = nil
        self.password = password
        self.obfuscated = obfuscated
    }

    // MARK: - Connect

    public func connect(to target: ConnectionTarget) async throws {
        if let quic = quicSession {
            try await connectOverQUIC(quic, target: target)
        } else if let fallback = fallbackSession {
            try await connectOverFallback(fallback, target: target)
        } else {
            throw Hysteria2Error.handshakeFailed("no transport available")
        }
    }

    // MARK: - QUIC Path

    private func connectOverQUIC(_ session: QUICTransportSession, target: ConnectionTarget) async throws {
        guard !connected else { return }

        // Hysteria2 auth: HMAC-SHA256(password, "hysteria2-auth")
        let authKey = SymmetricKey(data: Data(password.utf8))
        let authCode = HMAC<SHA256>.authenticationCode(for: Data("hysteria2-auth".utf8), using: authKey)

        // Build CONNECT request
        var request = Data()
        request.append(0x01) // CONNECT command
        request.append(contentsOf: authCode) // 32 bytes auth code
        request.append(try encodeTarget(target))

        try await session.send(request)

        // Read response (1 byte: status)
        let response = try await session.receive()
        guard !response.isEmpty else {
            throw Hysteria2Error.handshakeFailed("empty response from server")
        }

        let status = response[0]
        guard status == 0x00 else {
            throw Hysteria2Error.handshakeFailed("server rejected auth: status \(status)")
        }

        connected = true
    }

    // MARK: - Fallback Path

    private func connectOverFallback(_ session: any TransportSession, target: ConnectionTarget) async throws {
        guard !connected else { return }

        // Same handshake over TCP/TLS
        let authKey = SymmetricKey(data: Data(password.utf8))
        let authCode = HMAC<SHA256>.authenticationCode(for: Data("hysteria2-auth".utf8), using: authKey)

        var request = Data()
        request.append(0x01)
        request.append(contentsOf: authCode)
        request.append(try encodeTarget(target))

        try await session.send(request)

        let response = try await session.receive()
        guard !response.isEmpty else {
            throw Hysteria2Error.handshakeFailed("empty response")
        }

        let status = response[0]
        guard status == 0x00 else {
            throw Hysteria2Error.handshakeFailed("auth rejected: status \(status)")
        }

        connected = true
    }

    // MARK: - Data Transfer

    public func send(_ data: Data) async throws {
        if let quic = quicSession {
            try await quic.send(data)
        } else if let fallback = fallbackSession {
            try await fallback.send(data)
        } else {
            throw Hysteria2Error.connectionFailed("no transport")
        }
    }

    public func receive() async throws -> Data {
        if let quic = quicSession {
            return try await quic.receive()
        } else if let fallback = fallbackSession {
            return try await fallback.receive()
        } else {
            throw Hysteria2Error.connectionFailed("no transport")
        }
    }

    public func close() async {
        if let quic = quicSession {
            await quic.close()
        } else if let fallback = fallbackSession {
            await fallback.close()
        }
        connected = false
    }

    // MARK: - Helpers

    private func encodeTarget(_ target: ConnectionTarget) throws -> Data {
        var data = Data()

        let port = UInt16(target.port)

        // Address encoding
        if let ipv4 = parseIPv4(target.host) {
            data.append(0x01) // IPv4
            data.append(contentsOf: ipv4)
        } else if let ipv6 = parseIPv6(target.host) {
            data.append(0x04) // IPv6
            data.append(contentsOf: ipv6)
        } else {
            data.append(0x03) // Domain
            let hostBytes = Data(target.host.utf8)
            guard hostBytes.count <= 255 else {
                throw Hysteria2Error.malformedPacket
            }
            data.append(UInt8(hostBytes.count))
            data.append(hostBytes)
        }

        // Port
        data.append(UInt8(port >> 8))
        data.append(UInt8(port & 0xFF))

        return data
    }

    private func parseIPv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        return parts.compactMap { UInt8(String($0)) }
    }

    private func parseIPv6(_ host: String) -> [UInt8]? {
        var addr = in6_addr()
        let result = host.withCString { ptr in
            inet_pton(AF_INET6, ptr, &addr)
        }
        guard result == 1 else { return nil }
        return withUnsafeBytes(of: addr) { Array($0) }
    }
}
