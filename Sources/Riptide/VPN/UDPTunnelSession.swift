import Foundation

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
    public func establish(proxyConnector: ProxyConnector) async throws {
        guard !isClosed else {
            throw SessionError.sessionClosed
        }

        switch relayMode {
        case .direct:
            // Direct UDP — no encapsulation needed
            // In a full TUN implementation, this would create a NWConnection to the target
            break

        case .socks5UDP:
            // SOCKS5 UDP Associate handshake
            // 1. Connect to the SOCKS5 proxy
            // 2. Send UDP ASSOCIATE request
            // 3. Receive relay address/port
            // 4. Create a separate UDP relay connection to the relay endpoint

            try await performSocks5UDPAssociate(proxyConnector: proxyConnector)
        }
    }

    /// Forward a UDP datagram through the relay.
    /// - Parameter data: The raw UDP payload (after IP/UDP headers).
    /// - Returns: The response UDP payload.
    public func forward(_ data: Data) async throws -> Data {
        guard !isClosed else {
            throw SessionError.sessionClosed
        }

        lastActivity = ContinuousClock.now

        switch relayMode {
        case .direct:
            // Direct forwarding — in a real implementation this would use NWConnection
            // For now, this is a placeholder
            return Data()

        case .socks5UDP:
            // Encapsulate in SOCKS5 UDP datagram and send to relay endpoint
            return try await forwardViaSocks5UDP(data)
        }
    }

    /// Close the session and release resources.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        relayConnection = nil
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

    // MARK: - SOCKS5 UDP Associate

    /// Perform SOCKS5 UDP Associate handshake.
    /// This establishes a UDP relay endpoint on the proxy server.
    private func performSocks5UDPAssociate(proxyConnector: ProxyConnector) async throws {
        // Step 1: Connect to the SOCKS5 proxy
        // The proxy connector handles the TCP connection to the proxy
        let proxyNode = ProxyNode(
            name: "UDP_RELAY",
            kind: .socks5,
            server: sessionID.dstIP,
            port: Int(sessionID.dstPort)
        )

        let context = try await proxyConnector.connect(via: proxyNode, to: target)
        relayConnection = context.connection.session

        // Step 2: Send UDP ASSOCIATE command
        // SOCKS5 UDP ASSOCIATE:
        //   VER (1) | CMD (1) | RSV (1) | ATYP (1) | DST.ADDR (var) | DST.PORT (2)
        //   VER = 0x05 (SOCKS5)
        //   CMD = 0x03 (UDP ASSOCIATE)
        //   RSV = 0x00
        //   ATYP = 0x01 (IPv4) / 0x03 (domain) / 0x04 (IPv6)
        // The DST.ADDR/DST.PORT is the address the client expects UDP datagrams from

        var associateRequest = Data()
        associateRequest.append(0x05)  // VER
        associateRequest.append(0x03)  // CMD = UDP ASSOCIATE
        associateRequest.append(0x00)  // RSV

        // Use the client's IP:port as the association target
        // For TUN, this is the TUN client's address
        let clientIP = sessionID.srcIP
        let clientPort = sessionID.srcPort

        if let _ = IPv4AddressParser.parse(clientIP) {
            associateRequest.append(0x01)  // ATYP = IPv4
            let ipBytes = clientIP.split(separator: ".").compactMap { UInt8($0) }
            associateRequest.append(contentsOf: ipBytes)
        } else {
            associateRequest.append(0x01)  // Default to IPv4
            associateRequest.append(contentsOf: [0, 0, 0, 0])  // 0.0.0.0
        }
        associateRequest.append(UInt8(clientPort >> 8))
        associateRequest.append(UInt8(clientPort & 0xFF))

        // Send the request
        try await relayConnection?.send(associateRequest)

        // Step 3: Receive the response
        let response = try await relayConnection?.receive() ?? Data()
        guard response.count >= 10 else {
            throw SessionError.connectionFailed("invalid UDP ASSOCIATE response")
        }

        // Parse response
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
            // Simplified IPv6 handling
            socks5UDPRelayAddress = "::1"
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

        // Parse relay port
        guard offset + 2 <= response.count else {
            throw SessionError.connectionFailed("truncated port in response")
        }
        socks5UDPRelayPort = UInt16(response[offset]) << 8 | UInt16(response[offset + 1])

        // Note: In a full implementation, we would now establish a separate
        // UDP connection to the relay address/port for actual datagram forwarding.
        // For now, the TCP connection serves as the control channel.
    }

    /// Forward data via SOCKS5 UDP relay.
    private func forwardViaSocks5UDP(_ data: Data) async throws -> Data {
        // SOCKS5 UDP datagram format:
        //   RSV (2) | FRAG (1) | ATYP (1) | DST.ADDR (var) | DST.PORT (2) | DATA
        // The encapsulated datagram is sent to the relay endpoint obtained during UDP ASSOCIATE

        guard socks5UDPRelayAddress != nil,
              socks5UDPRelayPort != nil else {
            throw SessionError.connectionFailed("UDP relay endpoint not established")
        }

        // Build the SOCKS5 UDP datagram
        var udpDatagram = Data()
        udpDatagram.append(contentsOf: [0x00, 0x00])  // RSV
        udpDatagram.append(0x00)  // FRAG = 0 (no fragmentation)

        // Destination address (the real target of this UDP packet)
        let destIP = sessionID.dstIP
        let destPort = sessionID.dstPort

        if let _ = IPv4AddressParser.parse(destIP) {
            udpDatagram.append(0x01)  // ATYP = IPv4
            let ipBytes = destIP.split(separator: ".").compactMap { UInt8($0) }
            udpDatagram.append(contentsOf: ipBytes)
        } else {
            udpDatagram.append(0x01)
            udpDatagram.append(contentsOf: [0, 0, 0, 0])
        }
        udpDatagram.append(UInt8(destPort >> 8))
        udpDatagram.append(UInt8(destPort & 0xFF))

        // Payload
        udpDatagram.append(data)

        // Send to relay endpoint
        try await relayConnection?.send(udpDatagram)

        // Receive response (if any)
        if let responseData = try await relayConnection?.receive() {
            return parseSocks5UDPDatagram(responseData)
        }

        return Data()
    }

    /// Parse a SOCKS5 UDP datagram response.
    private func parseSocks5UDPDatagram(_ data: Data) -> Data {
        // Skip the header: RSV(2) + FRAG(1) + ATYP(1) + ADDR(var) + PORT(2)
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
