import Foundation
import Network

/// A UDP tunnel session that forwards UDP datagrams through a proxy.
///
/// Supports:
/// - SOCKS5 UDP Associate (RFC 1928)
/// - Direct UDP forwarding (when no proxy is needed)
///
/// The session manages the lifecycle of the UDP relay connection and
/// handles datagram encapsulation/decapsulation.
public actor UDPTunnelSession {

    // MARK: - Errors

    public enum SessionError: Error, Equatable, Sendable {
        case connectionFailed(String)
        case sendFailed(String)
        case receiveFailed(String)
        case sessionClosed
        case unsupportedProtocol(String)
    }

    // MARK: - Types

    /// The relay mode for this UDP session.
    public enum RelayMode: Sendable {
        /// Direct UDP (no proxy encapsulation).
        case direct
        /// SOCKS5 UDP Associate.
        case socks5UDP
    }

    // MARK: - State

    private let sessionID: UDPSessionID
    private let target: ConnectionTarget
    private let relayMode: RelayMode
    private var relayConnection: (any TransportSession)?
    private var socks5UDPRelayAddress: String?
    private var socks5UDPRelayPort: UInt16?
    private var udpRelayConnection: NWConnection?
    private var isClosed: Bool
    private var lastActivity: ContinuousClock.Instant

    // MARK: - Init

    public init(
        sessionID: UDPSessionID,
        target: ConnectionTarget,
        relayMode: RelayMode = .socks5UDP
    ) {
        self.sessionID = sessionID
        self.target = target
        self.relayMode = relayMode
        self.isClosed = false
        self.lastActivity = ContinuousClock.now
    }

    // MARK: - Lifecycle

    /// Establish the UDP relay connection.
    /// For SOCKS5 UDP, this performs the UDP Associate handshake.
    /// - Parameter proxyNode: The routing-selected proxy node to use.
    public func establish(proxyConnector: ProxyConnector, proxyNode: ProxyNode? = nil) async throws {
        guard !isClosed else {
            throw SessionError.sessionClosed
        }

        switch relayMode {
        case .direct:
            // Direct UDP — no encapsulation needed
            break

        case .socks5UDP:
            // SOCKS5 UDP Associate handshake
            try await performSocks5UDPAssociate(proxyConnector: proxyConnector, proxyNode: proxyNode)
        }
    }

    /// Forward a UDP datagram through the relay.
    public func forward(_ data: Data) async throws -> Data {
        guard !isClosed else {
            throw SessionError.sessionClosed
        }

        lastActivity = ContinuousClock.now

        switch relayMode {
        case .direct:
            return try await forwardDirect(data)

        case .socks5UDP:
            return try await forwardViaSocks5UDP(data)
        }
    }

    /// Close the session and release resources.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        relayConnection = nil
        udpRelayConnection?.cancel()
        udpRelayConnection = nil
        socks5UDPRelayAddress = nil
        socks5UDPRelayPort = nil
    }

    // MARK: - State

    public var isActive: Bool {
        !isClosed
    }

    public var idleDuration: Duration {
        ContinuousClock.now - lastActivity
    }

    // MARK: - Direct UDP

    private func forwardDirect(_ data: Data) async throws -> Data {
        // Create a direct NWConnection to the target
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(sessionID.dstIP),
            port: NWEndpoint.Port(rawValue: sessionID.dstPort)!
        )

        let connection = NWConnection(to: endpoint, using: .udp)
        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error {
                            continuation.resume(throwing: SessionError.sendFailed(error.localizedDescription))
                            return
                        }
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, _ in
                            if let content {
                                continuation.resume(returning: content)
                            } else {
                                continuation.resume(throwing: SessionError.receiveFailed("empty response"))
                            }
                        }
                    })
                } else if case .failed(let error) = state {
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: SessionError.connectionFailed(error.localizedDescription))
                }
            }
            connection.start(queue: .global())
        }
    }

    // MARK: - SOCKS5 UDP Associate

    /// Perform SOCKS5 UDP Associate handshake.
    /// Uses the routing-selected proxy node (or defaults to target server as SOCKS5).
    private func performSocks5UDPAssociate(proxyConnector: ProxyConnector, proxyNode: ProxyNode?) async throws {
        // Use the provided proxy node, or fall back to treating the target as a SOCKS5 proxy
        let actualProxyNode = proxyNode ?? ProxyNode(
            name: "UDP_RELAY",
            kind: .socks5,
            server: target.host,
            port: target.port
        )

        // Connect via the proxy to establish the TCP control channel
        let context = try await proxyConnector.connect(via: actualProxyNode, to: target)
        relayConnection = context.connection.session

        // Build UDP ASSOCIATE request
        var associateRequest = Data()
        associateRequest.append(0x05)  // VER
        associateRequest.append(0x03)  // CMD = UDP ASSOCIATE
        associateRequest.append(0x00)  // RSV

        let clientIP = sessionID.srcIP
        let clientPort = sessionID.srcPort

        if let _ = IPv4AddressParser.parse(clientIP) {
            associateRequest.append(0x01)  // ATYP = IPv4
            let ipBytes = clientIP.split(separator: ".").compactMap { UInt8($0, radix: 10) ?? 0 }
            associateRequest.append(contentsOf: ipBytes)
        } else {
            associateRequest.append(0x01)
            associateRequest.append(contentsOf: [0, 0, 0, 0])
        }
        associateRequest.append(UInt8(clientPort >> 8))
        associateRequest.append(UInt8(clientPort & 0xFF))

        // Send the request
        try await relayConnection?.send(associateRequest)

        // Receive the response
        let response = try await relayConnection?.receive() ?? Data()
        guard response.count >= 10 else {
            throw SessionError.connectionFailed("invalid UDP ASSOCIATE response")
        }

        let version = response[0]
        let replyCode = response[1]
        guard version == 0x05 else {
            throw SessionError.connectionFailed("invalid SOCKS5 version in response")
        }
        guard replyCode == 0x00 else {
            throw SessionError.connectionFailed("UDP ASSOCIATE failed with reply code \(replyCode)")
        }

        // Parse relay address
        let atyp = response[3]
        var offset = 4

        switch atyp {
        case 0x01:  // IPv4
            guard offset + 4 <= response.count else {
                throw SessionError.connectionFailed("truncated IPv4 in response")
            }
            socks5UDPRelayAddress = "\(response[offset]).\(response[offset + 1]).\(response[offset + 2]).\(response[offset + 3])"
            offset += 4

        case 0x04:  // IPv6
            guard offset + 16 <= response.count else {
                throw SessionError.connectionFailed("truncated IPv6 in response")
            }
            var ipv6Parts: [String] = []
            for i in 0..<8 {
                let part = String(format: "%02x%02x", response[offset + i * 2], response[offset + i * 2 + 1])
                ipv6Parts.append(part)
            }
            socks5UDPRelayAddress = ipv6Parts.joined(separator: ":")
            offset += 16

        case 0x03:  // Domain
            let domainLength = Int(response[offset])
            offset += 1
            guard offset + domainLength <= response.count else {
                throw SessionError.connectionFailed("truncated domain in response")
            }
            socks5UDPRelayAddress = String(data: response.subdata(in: offset..<offset + domainLength), encoding: .utf8)
            offset += domainLength

        default:
            throw SessionError.connectionFailed("invalid ATYP in response")
        }

        guard offset + 2 <= response.count else {
            throw SessionError.connectionFailed("truncated port in response")
        }
        socks5UDPRelayPort = UInt16(response[offset]) << 8 | UInt16(response[offset + 1])

        // Establish a separate UDP connection to the relay endpoint
        try await establishUDPRelayConnection()
    }

    /// Establish a UDP connection to the SOCKS5 relay endpoint.
    private func establishUDPRelayConnection() async throws {
        guard let relayHost = socks5UDPRelayAddress,
              let relayPort = socks5UDPRelayPort,
              let port = NWEndpoint.Port(rawValue: relayPort) else {
            throw SessionError.connectionFailed("invalid relay endpoint")
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(relayHost), port: port)
        let connection = NWConnection(to: endpoint, using: .udp)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: SessionError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: SessionError.sessionClosed)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }

        udpRelayConnection = connection
    }

    /// Forward data via SOCKS5 UDP relay using the separate UDP connection.
    private func forwardViaSocks5UDP(_ data: Data) async throws -> Data {
        guard let relayConn = udpRelayConnection,
              relayConn.state == .ready else {
            throw SessionError.connectionFailed("UDP relay connection not ready")
        }

        guard let relayAddr = socks5UDPRelayAddress,
              let relayPort = socks5UDPRelayPort else {
            throw SessionError.connectionFailed("UDP relay endpoint not established")
        }

        // Build the SOCKS5 UDP datagram
        var udpDatagram = Data()
        udpDatagram.append(contentsOf: [0x00, 0x00])  // RSV
        udpDatagram.append(0x00)  // FRAG = 0

        // Destination address (the real target)
        let destIP = sessionID.dstIP
        let destPort = sessionID.dstPort

        if let _ = IPv4AddressParser.parse(destIP) {
            udpDatagram.append(0x01)  // ATYP = IPv4
            let ipBytes = destIP.split(separator: ".").compactMap { UInt8($0, radix: 10) ?? 0 }
            udpDatagram.append(contentsOf: ipBytes)
        } else {
            udpDatagram.append(0x01)
            udpDatagram.append(contentsOf: [0, 0, 0, 0])
        }
        udpDatagram.append(UInt8(destPort >> 8))
        udpDatagram.append(UInt8(destPort & 0xFF))

        // Payload
        udpDatagram.append(data)

        // Send via the UDP relay connection (not the TCP control connection)
        return try await withCheckedThrowingContinuation { continuation in
            relayConn.send(content: udpDatagram, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: SessionError.sendFailed(error.localizedDescription))
                    return
                }
                // Receive response
                relayConn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, recvError in
                    if let recvError {
                        continuation.resume(throwing: SessionError.receiveFailed(recvError.localizedDescription))
                        return
                    }
                    if let content {
                        let payload = self.parseSocks5UDPDatagram(content)
                        continuation.resume(returning: payload)
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            })
        }
    }

    /// Parse a SOCKS5 UDP datagram response.
    private func parseSocks5UDPDatagram(_ data: Data) -> Data {
        guard data.count >= 7 else { return data }

        var offset = 3  // Skip RSV + FRAG
        let atyp = data[offset]
        offset += 1

        switch atyp {
        case 0x01:  // IPv4
            offset += 4
        case 0x04:  // IPv6
            offset += 16
        case 0x03:  // Domain
            if offset < data.count {
                offset += 1 + Int(data[offset])
            }
        default:
            break
        }

        offset += 2  // Skip port

        guard offset < data.count else { return data }
        return data.subdata(in: offset..<data.count)
    }
}
