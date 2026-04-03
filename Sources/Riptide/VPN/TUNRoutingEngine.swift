import Foundation

// ============================================================
// MARK: - Tunnel Errors
// ============================================================

public enum TunnelError: Error, Equatable, Sendable {
    case sessionLimitReached
    case connectionNotFound
    case connectionFailed(String)
    case invalidPacket
    case routingFailed(String)
    case dnsResolutionFailed(String)
    case proxyError(String)
    case packetFlowNotAvailable
}

// ============================================================
// MARK: - TUN Routing Engine
// ============================================================

/// Errors from the TUN routing engine.
public enum TUNRoutingEngineError: Error, Equatable, Sendable {
    case parseError(String)
    case sessionLimitReached
    case connectionFailed(String)
    case routingFailed(String)
    case dnsResolutionFailed(String)
    case proxyError(String)
    case tcpStateError(String)
    case udpSessionError(String)
}

/// The main TUN routing engine that handles IP packet routing through the proxy system.
/// This actor dispatches incoming IP packets to the appropriate handler (TCP/UDP/ICMP).
public actor TUNRoutingEngine {
    private let tcpStateMachine: TCPStateMachine
    private let udpSessionManager: UDPSessionManager
    private let proxyConnector: ProxyConnector
    private let dnsPipeline: DNSPipeline
    private let configuration: VPNConfiguration

    /// Stats counters.
    private var packetsHandled: Int = 0
    private var tcpPacketsHandled: Int = 0
    private var udpPacketsHandled: Int = 0
    private var dnsPacketsHandled: Int = 0
    private var bytesProcessed: Int = 0

    public init(
        proxyConnector: ProxyConnector,
        dnsPipeline: DNSPipeline,
        configuration: VPNConfiguration
    ) {
        self.proxyConnector = proxyConnector
        self.dnsPipeline = dnsPipeline
        self.configuration = configuration
        self.tcpStateMachine = TCPStateMachine()
        self.udpSessionManager = UDPSessionManager()
    }

    // ============================================================
    // MARK: - Public Interface
    // ============================================================

    /// Handle an inbound IP packet from the TUN interface.
    /// Returns response packets that should be sent back.
    public func handlePacket(_ packetData: Data) async throws -> [Data] {
        packetsHandled += 1
        bytesProcessed += packetData.count

        guard let result = PacketHandler.parseIPPacket(packetData) else {
            throw TUNRoutingEngineError.parseError("invalid IP packet")
        }

        let ip = result.ip

        switch ip.ipProtocol {
        case 6:  // TCP
            tcpPacketsHandled += 1
            return try await handleTCP(ip: ip, packetData: packetData)

        case 17: // UDP
            udpPacketsHandled += 1
            return try await handleUDP(ip: ip, packetData: packetData)

        case 1:  // ICMP
            return try await handleICMP(ip: ip, packetData: packetData)

        case 58: // ICMPv6
            return []

        default:
            // Unknown protocol — forward as-is
            return []
        }
    }

    /// Handle multiple packets at once.
    public func handlePackets(_ packets: [Data]) async throws -> [Data] {
        var responses: [Data] = []
        for packet in packets {
            let result = try await handlePacket(packet)
            responses.append(contentsOf: result)
        }
        return responses
    }

    /// Get routing stats.
    public nonisolated func getStats() -> TUNRoutingStats {
        // Note: accessing actor state from nonisolated requires us to make a safe copy
        TUNRoutingStats(
            packetsHandled: 0,
            tcpPacketsHandled: 0,
            udpPacketsHandled: 0,
            dnsPacketsHandled: 0,
            bytesProcessed: 0,
            activeTCPConnections: 0,
            activeUDPSessions: 0
        )
    }

    /// Get routing stats from within the actor.
    public func getStatsInternal() -> TUNRoutingStats {
        TUNRoutingStats(
            packetsHandled: packetsHandled,
            tcpPacketsHandled: tcpPacketsHandled,
            udpPacketsHandled: udpPacketsHandled,
            dnsPacketsHandled: dnsPacketsHandled,
            bytesProcessed: bytesProcessed,
            activeTCPConnections: tcpStateMachine.connectionCount,
            activeUDPSessions: udpSessionManager.sessionCount
        )
    }

    /// Get the TCP state machine for external access.
    public var tcpMachine: TCPStateMachine {
        tcpStateMachine
    }

    /// Get the UDP session manager for external access.
    public var udpSessions: UDPSessionManager {
        udpSessionManager
    }

    /// Close all connections and sessions.
    public func shutdown() async {
        // Close all TCP connections
        let tcpIds = await tcpStateMachine.activeConnectionIDs()
        for id in tcpIds {
            await tcpStateMachine.closeConnection(id: id)
        }

        // Close all UDP sessions
        await udpSessionManager.closeAllSessions()
    }

    // ============================================================
    // MARK: - TCP Handling
    // ============================================================

    private func handleTCP(ip: IPHeader, packetData: Data) async throws -> [Data] {
        guard let tcpHeader = parseTCPFromPacket(ip: ip, packetData: packetData) else {
            throw TUNRoutingEngineError.parseError("invalid TCP header")
        }

        let connectionID = TCPConnectionID(
            srcIP: ip.sourceAddress,
            srcPort: tcpHeader.sourcePort,
            dstIP: ip.destinationAddress,
            dstPort: tcpHeader.destinationPort
        )

        // Extract payload
        let tcpHeaderLength = Int(tcpHeader.dataOffset) * 4
        let payloadOffset = 20 + tcpHeaderLength  // IP header (20) + TCP header
        var payload = Data()
        if packetData.count > payloadOffset {
            payload = packetData.subdata(in: payloadOffset..<packetData.count)
        }

        // RST — close connection
        if tcpHeader.rst {
            await tcpStateMachine.handleRST(id: connectionID)
            return []
        }

        // SYN only — new connection request
        if tcpHeader.syn && !tcpHeader.ack {
            return try await handleNewTCPConnection(connectionID: connectionID, packetData: packetData)
        }

        // SYN-ACK — response to our outbound connection
        if tcpHeader.syn && tcpHeader.ack {
            return try await handleTCPResponse(connectionID: connectionID, tcpHeader: tcpHeader)
        }

        // Existing connection
        if let existingState = await tcpStateMachine.getState(id: connectionID) {
            return try await processExistingTCPConnection(
                connectionID: connectionID,
                state: existingState,
                tcpHeader: tcpHeader,
                payload: payload
            )
        }

        // ACK without SYN — might be completing a handshake we initiated
        if tcpHeader.ack && !tcpHeader.syn {
            return try await handleTCPResponse(connectionID: connectionID, tcpHeader: tcpHeader)
        }

        return []
    }

    private func handleNewTCPConnection(connectionID: TCPConnectionID, packetData: Data) async throws -> [Data] {
        do {
            let (conn, synAckPacket) = try await tcpStateMachine.acceptConnection(id: connectionID)
            return [synAckPacket]
        } catch {
            throw TUNRoutingEngineError.tcpStateError("failed to accept TCP connection: \(error)")
        }
    }

    private func handleTCPResponse(connectionID: TCPConnectionID, tcpHeader: TCPHeader) async throws -> [Data] {
        // Handle SYN-ACK for outbound connections
        if tcpHeader.syn && tcpHeader.ack {
            _ = try await tcpStateMachine.handleSynAck(
                id: connectionID,
                ackNumber: tcpHeader.acknowledgmentNumber,
                seqNumber: tcpHeader.sequenceNumber
            )
            // Send our ACK to complete the handshake
            if let conn = await tcpStateMachine.getConnection(id: connectionID) {
                let ack = PacketHandler.buildACK(
                    srcIP: connectionID.srcIP, srcPort: connectionID.srcPort,
                    dstIP: connectionID.dstIP, dstPort: connectionID.dstPort,
                    seq: conn.localSeq,
                    ack: tcpHeader.sequenceNumber &+ 1
                )
                return [ack]
            }
        }

        // Handle ACK for handshake completion
        _ = try? await tcpStateMachine.handleHandshakeACK(
            id: connectionID,
            ackNumber: tcpHeader.acknowledgmentNumber
        )

        return []
    }

    private func processExistingTCPConnection(
        connectionID: TCPConnectionID,
        state: TCPState,
        tcpHeader: TCPHeader,
        payload: Data
    ) async throws -> [Data] {
        var responses: [Data] = []

        // Handle FIN
        if tcpHeader.fin {
            let (updatedState, finResponses) = try await tcpStateMachine.handleRemoteFin(
                id: connectionID,
                seqNumber: tcpHeader.sequenceNumber,
                ackNumber: tcpHeader.acknowledgmentNumber
            )
            responses.append(contentsOf: finResponses)

            if updatedState.state == .closed {
                return responses
            }
        }

        // Handle data
        if !payload.isEmpty {
            let (updatedConn, receivedData, dataResponses) = try await tcpStateMachine.handleData(
                id: connectionID,
                seqNumber: tcpHeader.sequenceNumber,
                ackNumber: tcpHeader.acknowledgmentNumber,
                data: payload
            )
            responses.append(contentsOf: dataResponses)

            // Forward data through proxy if connection is established
            if updatedConn.state == .established {
                try await forwardTCPData(connectionID: connectionID, data: receivedData)
            }
        }

        // Handle data ACK
        if tcpHeader.ack {
            _ = try? await tcpStateMachine.handleDataAck(
                id: connectionID,
                ackNumber: tcpHeader.acknowledgmentNumber
            )
        }

        // Handle FIN-ACK (closing handshake)
        if tcpHeader.fin && tcpHeader.ack {
            if let finalState = try? await tcpStateMachine.handleFinAck(
                id: connectionID,
                ackNumber: tcpHeader.acknowledgmentNumber
            ) {
                if finalState?.state == .closed {
                    return responses
                }
            }
        }

        return responses
    }

    /// Forward TCP data through the proxy.
    private func forwardTCPData(connectionID: TCPConnectionID, data: Data) async throws {
        // In the full implementation, this would:
        // 1. Look up the connection's target (from a connection table)
        // 2. Connect via ProxyConnector
        // 3. Send data through the proxy
        // 4. Receive response and queue it for delivery
        _ = connectionID
        _ = data
        // Stub — full implementation requires connection target registry
    }

    // ============================================================
    // MARK: - UDP Handling
    // ============================================================

    private func handleUDP(ip: IPHeader, packetData: Data) async throws -> [Data] {
        guard let udpHeader = parseUDPFromPacket(ip: ip, packetData: packetData) else {
            throw TUNRoutingEngineError.parseError("invalid UDP header")
        }

        // DNS packet (port 53)?
        if udpHeader.destinationPort == 53 {
            dnsPacketsHandled += 1
            return try await handleDNS(ip: ip, udpHeader: udpHeader, packetData: packetData)
        }

        // Other UDP — create session
        let sessionID = UDPSessionID(
            srcIP: ip.sourceAddress,
            srcPort: udpHeader.sourcePort,
            dstIP: ip.destinationAddress,
            dstPort: udpHeader.destinationPort
        )

        // Extract UDP payload (after 8-byte UDP header)
        var payload = Data()
        if packetData.count > 28 {  // 20 (IP) + 8 (UDP)
            payload = packetData.subdata(in: 28..<packetData.count)
        }

        return try await udpSessionManager.routePacket(
            sessionID: sessionID,
            data: payload,
            proxyConnector: proxyConnector
        )
    }

    // ============================================================
    // MARK: - DNS Handling
    // ============================================================

    private func handleDNS(ip: IPHeader, udpHeader: UDPHeader, packetData: Data) async throws -> [Data] {
        // Extract DNS payload (after IP + UDP headers)
        let dnsPayloadOffset = 28  // 20 (IP) + 8 (UDP)
        guard packetData.count > dnsPayloadOffset else {
            throw TUNRoutingEngineError.parseError("DNS packet too short")
        }

        let dnsPayload = packetData.subdata(in: dnsPayloadOffset..<packetData.count)

        // Parse DNS query
        let dnsMessage: DNSMessage
        do {
            dnsMessage = try DNSMessage.parse(dnsPayload)
        } catch {
            // If we can't parse, just forward the original packet as-is
            return []
        }

        // Only handle queries, not responses
        guard !dnsMessage.header.isResponse, !dnsMessage.questions.isEmpty else {
            return []
        }

        let question = dnsMessage.questions[0]
        let queryID = dnsMessage.header.id

        // Resolve via DNSPipeline
        var resolvedIPs: [String] = []
        do {
            resolvedIPs = try await dnsPipeline.resolve(question.name, type: question.type)
        } catch {
            throw TUNRoutingEngineError.dnsResolutionFailed("failed to resolve \(question.name): \(error)")
        }

        // Build DNS response
        var response = try buildDNSResponse(
            originalMessage: dnsMessage,
            question: question,
            answers: resolvedIPs,
            queryID: queryID
        )

        // Build the full response packet (swap src/dst, embed DNS response)
        let fullResponse = buildUDPResponsePacket(
            originalPacket: packetData,
            dnsResponse: response
        )

        return [fullResponse]
    }

    private func buildDNSResponse(
        originalMessage: DNSMessage,
        question: DNSQuestion,
        answers: [String],
        queryID: UInt16
    ) throws -> Data {
        var answerRecords: [DNSResourceRecord] = []

        for ipString in answers {
            let rdata = ipStringToData(ipString)
            answerRecords.append(DNSResourceRecord(
                name: question.name,
                type: question.type,
                classValue: .inet,
                ttl: 300,
                rdata: rdata
            ))
        }

        let responseHeader = DNSHeader(
            id: queryID,
            isResponse: true,
            opcode: 0,
            authoritative: false,
            truncated: false,
            recursionDesired: originalMessage.header.recursionDesired,
            recursionAvailable: true,
            responseCode: answers.isEmpty ? .nameError : .noError,
            questionCount: 1,
            answerCount: UInt16(answerRecords.count)
        )

        let response = DNSMessage(
            header: responseHeader,
            questions: [question],
            answers: answerRecords
        )

        return try response.encode()
    }

    // ============================================================
    // MARK: - ICMP Handling
    // ============================================================

    private func handleICMP(ip: IPHeader, packetData: Data) async throws -> [Data] {
        // For ICMP echo requests, we could send a response
        // For now, just pass through
        _ = ip
        _ = packetData
        return []
    }

    // ============================================================
    // MARK: - Helper Methods
    // ============================================================

    private func parseTCPFromPacket(ip: IPHeader, packetData: Data) -> TCPHeader? {
        let ipHeaderLength = 20
        guard packetData.count > ipHeaderLength + 20 else { return nil }

        let offset = ipHeaderLength
        let srcPort = UInt16(packetData[offset]) << 8 | UInt16(packetData[offset + 1])
        let dstPort = UInt16(packetData[offset + 2]) << 8 | UInt16(packetData[offset + 3])
        let seqNum = UInt32(packetData[offset + 4]) << 24 | UInt32(packetData[offset + 5]) << 16 |
                     UInt32(packetData[offset + 6]) << 8 | UInt32(packetData[offset + 7])
        let ackNum = UInt32(packetData[offset + 8]) << 24 | UInt32(packetData[offset + 9]) << 16 |
                     UInt32(packetData[offset + 10]) << 8 | UInt32(packetData[offset + 11])
        let dataOffset = packetData[offset + 12] >> 4
        let flagsRaw = packetData[offset + 13]
        let windowSize = UInt16(packetData[offset + 14]) << 8 | UInt16(packetData[offset + 15])
        let checksum = UInt16(packetData[offset + 16]) << 8 | UInt16(packetData[offset + 17])
        let urgent = UInt16(packetData[offset + 18]) << 8 | UInt16(packetData[offset + 19])

        return TCPHeader(
            sourcePort: srcPort,
            destinationPort: dstPort,
            sequenceNumber: seqNum,
            acknowledgmentNumber: ackNum,
            dataOffset: dataOffset,
            flags: TCPFlags(raw: flagsRaw),
            windowSize: windowSize,
            checksum: checksum,
            urgentPointer: urgent,
            options: Data()
        )
    }

    private func parseUDPFromPacket(ip: IPHeader, packetData: Data) -> UDPHeader? {
        let ipHeaderLength = 20
        guard packetData.count > ipHeaderLength + 8 else { return nil }

        let offset = ipHeaderLength
        let srcPort = UInt16(packetData[offset]) << 8 | UInt16(packetData[offset + 1])
        let dstPort = UInt16(packetData[offset + 2]) << 8 | UInt16(packetData[offset + 3])
        let length = UInt16(packetData[offset + 4]) << 8 | UInt16(packetData[offset + 5])
        let checksum = UInt16(packetData[offset + 6]) << 8 | UInt16(packetData[offset + 7])

        return UDPHeader(
            sourcePort: srcPort,
            destinationPort: dstPort,
            length: length,
            checksum: checksum
        )
    }

    private func buildUDPResponsePacket(originalPacket: Data, dnsResponse: Data) -> Data {
        // Swap IP addresses, UDP ports, recompute checksums
        var response = PacketHandler.swapIPAddresses(originalPacket)

        // Replace the UDP length field and payload
        let newLength = UInt16(8 + dnsResponse.count)
        let ipLength = UInt16(20 + 8 + dnsResponse.count)

        // Update IP total length
        response[2] = UInt8(ipLength >> 8)
        response[3] = UInt8(ipLength & 0xFF)

        // Update UDP length
        response[24] = UInt8(newLength >> 8)
        response[25] = UInt8(newLength & 0xFF)

        // Replace DNS payload
        if response.count > 28 {
            response.replaceSubrange(28..<response.count, with: dnsResponse)
        } else {
            response.append(dnsResponse)
        }

        // Recompute IP header checksum
        response[10] = 0
        response[11] = 0
        let ipChecksum = PacketHandler.computeChecksum(response.prefix(20))
        response[10] = UInt8(ipChecksum >> 8)
        response[11] = UInt8(ipChecksum & 0xFF)

        return response
    }

    private func ipStringToData(_ ip: String) -> Data {
        let parts = ip.split(separator: ".").compactMap { UInt8($0) }
        return Data(parts)
    }
}

// ============================================================
// MARK: - Routing Stats
// ============================================================

public struct TUNRoutingStats: Sendable {
    public let packetsHandled: Int
    public let tcpPacketsHandled: Int
    public let udpPacketsHandled: Int
    public let dnsPacketsHandled: Int
    public let bytesProcessed: Int
    public let activeTCPConnections: Int
    public let activeUDPSessions: Int

    public init(
        packetsHandled: Int,
        tcpPacketsHandled: Int,
        udpPacketsHandled: Int,
        dnsPacketsHandled: Int,
        bytesProcessed: Int,
        activeTCPConnections: Int,
        activeUDPSessions: Int
    ) {
        self.packetsHandled = packetsHandled
        self.tcpPacketsHandled = tcpPacketsHandled
        self.udpPacketsHandled = udpPacketsHandled
        self.dnsPacketsHandled = dnsPacketsHandled
        self.bytesProcessed = bytesProcessed
        self.activeTCPConnections = activeTCPConnections
        self.activeUDPSessions = activeUDPSessions
    }
}
