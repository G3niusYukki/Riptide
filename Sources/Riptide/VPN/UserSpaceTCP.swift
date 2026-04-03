import Foundation
import Network

// ============================================================
// MARK: - TCP Connection ID
// ============================================================

/// Uniquely identifies a TCP connection by its 4-tuple.
public struct TCPConnectionID: Hashable, Sendable {
    public let srcIP: String
    public let srcPort: UInt16
    public let dstIP: String
    public let dstPort: UInt16

    public init(srcIP: String, srcPort: UInt16, dstIP: String, dstPort: UInt16) {
        self.srcIP = srcIP
        self.srcPort = srcPort
        self.dstIP = dstIP
        self.dstPort = dstPort
    }

    /// The reversed tuple (for response packets).
    public var reversed: TCPConnectionID {
        TCPConnectionID(srcIP: dstIP, srcPort: dstPort, dstIP: srcIP, dstPort: srcPort)
    }
}

// ============================================================
// MARK: - TCP State Machine Types
// ============================================================

/// The state of a TCP connection in the userspace TCP state machine.
public enum TCPState: Sendable, Equatable {
    /// Waiting for a SYN from the client.
    case listen
    /// SYN received, SYN-ACK sent, waiting for ACK.
    case synReceived
    /// Three-way handshake complete, data transfer can begin.
    case established
    /// Local FIN sent, waiting for remote FIN.
    case finWait1
    /// Received FIN from remote, waiting for our FIN to be ACKed.
    case finWait2
    /// Close wait — received FIN, waiting for local application to close.
    case closeWait
    /// Local FIN sent, received remote FIN too (simultaneous close).
    case closing
    /// Final acknowledgment sent, connection closing.
    case lastAck
    /// Connection closed.
    case closed
}

/// A single TCP connection's state in the userspace TCP stack.
public struct ManagedTCPConnection: Sendable {
    public let id: TCPConnectionID
    public var state: TCPState

    /// Our initial sequence number (ISN) for packets we send.
    public var localSeq: UInt32
    /// The next sequence number we expect from the remote.
    public var remoteSeq: UInt32

    /// Last acknowledged sequence number from remote.
    public var remoteAck: UInt32
    /// Last acknowledged sequence number from us.
    public var localAck: UInt32

    /// Remote window size.
    public var remoteWindow: UInt16
    /// Local window size.
    public var localWindow: UInt16

    /// Buffered data received from the remote side (ready for app to read).
    public var receiveBuffer: Data
    /// Buffered data to send to the remote side.
    public var sendBuffer: Data

    /// The sequence number of the SYN we received.
    public var receivedSynSeq: UInt32
    /// The acknowledgment number we sent in SYN-ACK.
    public var synAckSeq: UInt32

    /// When this connection was last active (for timeout).
    public var lastActivity: ContinuousClock.Instant

    public init(id: TCPConnectionID) {
        self.id = id
        self.state = .listen
        self.localSeq = UInt32.random(in: 0...UInt32.max)
        self.remoteSeq = 0
        self.remoteAck = 0
        self.localAck = 0
        self.remoteWindow = 65535
        self.localWindow = 65535
        self.receiveBuffer = Data()
        self.sendBuffer = Data()
        self.receivedSynSeq = 0
        self.synAckSeq = 0
        self.lastActivity = ContinuousClock.now
    }

    public mutating func updateActivity() {
        lastActivity = ContinuousClock.now
    }
}

// ============================================================
// MARK: - Actor-based TCP Connection Manager
// ============================================================

/// Errors from the userspace TCP state machine.
public enum TCPStateMachineError: Error, Equatable, Sendable {
    case connectionNotFound(TCPConnectionID)
    case invalidStateTransition(TCPState, String)
    case connectionAlreadyExists(TCPConnectionID)
    case connectionLimitReached
    case connectionTimeout
}

/// An actor that manages all TCP connections in the TUN routing engine.
/// This implements a proper TCP state machine (RFC 793) with support for
/// the TCP congestion control events needed for userspace TCP handling.
public actor TCPStateMachine {
    private var connections: [TCPConnectionID: ManagedTCPConnection] = [:]
    private var pendingConnections: [TCPConnectionID: ManagedTCPConnection] = [:]
    private let maxConnections: Int
    private let connectionTimeout: Duration
    private var cleanupTask: Task<Void, Never>?

    public init(maxConnections: Int = 10000, connectionTimeout: Duration = .seconds(300)) {
        self.maxConnections = maxConnections
        self.connectionTimeout = connectionTimeout
        self.cleanupTask = Task { await self.runCleanupLoop() }
    }

    deinit {
        cleanupTask?.cancel()
    }

    /// Get or create a connection by ID.
    public func getConnection(id: TCPConnectionID) -> ManagedTCPConnection? {
        connections[id]
    }

    /// Get the current state of a connection.
    public func getState(id: TCPConnectionID) -> TCPState? {
        connections[id]?.state
    }

    /// Handle an inbound SYN on a new connection (server-side).
    /// Creates a connection in SYN_RECEIVED state and returns the SYN-ACK packet.
    public func acceptConnection(id: TCPConnectionID) throws -> (state: ManagedTCPConnection, synAckPacket: Data) {
        if connections[id] != nil || pendingConnections[id] != nil {
            throw TCPStateMachineError.connectionAlreadyExists(id)
        }

        if connections.count + pendingConnections.count >= maxConnections {
            throw TCPStateMachineError.connectionLimitReached
        }

        var conn = ManagedTCPConnection(id: id)
        conn.state = .synReceived

        // SYN-ACK: ack the SYN we received (seq = ISN, ack = received.SYN + 1)
        let synAck = PacketHandler.buildSYNACK(
            srcIP: id.dstIP, srcPort: id.dstPort,
            dstIP: id.srcIP, dstPort: id.srcPort,
            seq: conn.localSeq
        )

        conn.synAckSeq = conn.localSeq
        conn.localSeq = conn.localSeq &+ 1  // SYN consumes one seq number
        conn.updateActivity()

        pendingConnections[id] = conn
        return (conn, synAck)
    }

    /// Handle an inbound ACK on a pending connection (completes 3-way handshake).
    /// Returns the connection state if the handshake completed, or nil if waiting.
    public func handleHandshakeACK(id: TCPConnectionID, ackNumber: UInt32) throws -> ManagedTCPConnection? {
        guard var conn = pendingConnections[id] else {
            throw TCPStateMachineError.connectionNotFound(id)
        }

        // ACK must acknowledge our SYN (our SYN seq + 1)
        let expectedAck = conn.synAckSeq &+ 1

        if ackNumber >= expectedAck {
            // Handshake complete
            conn.state = .established
            conn.remoteAck = ackNumber
            conn.localAck = conn.synAckSeq
            conn.updateActivity()
            pendingConnections.removeValue(forKey: id)
            connections[id] = conn
            return conn
        }

        // Not yet — update remote ack and keep waiting
        conn.remoteAck = ackNumber
        conn.updateActivity()
        pendingConnections[id] = conn
        return nil
    }

    /// Handle a SYN for an outbound connection (client-side).
    public func initiateConnection(id: TCPConnectionID) throws -> (state: ManagedTCPConnection, synPacket: Data) {
        if connections[id] != nil {
            throw TCPStateMachineError.connectionAlreadyExists(id)
        }

        if connections.count + pendingConnections.count >= maxConnections {
            throw TCPStateMachineError.connectionLimitReached
        }

        var conn = ManagedTCPConnection(id: id)
        conn.state = .synReceived

        let synPacket = PacketHandler.buildTCPPacket(
            srcIP: id.srcIP, srcPort: id.srcPort,
            dstIP: id.dstIP, dstPort: id.dstPort,
            seq: conn.localSeq, ack: 0,
            flags: 0x02,  // SYN
            windowSize: conn.localWindow,
            payload: Data()
        )

        conn.updateActivity()
        pendingConnections[id] = conn
        return (conn, synPacket)
    }

    /// Handle SYN-ACK response for an outbound connection.
    public func handleSynAck(
        id: TCPConnectionID,
        ackNumber: UInt32,
        seqNumber: UInt32
    ) throws -> ManagedTCPConnection? {
        guard var conn = pendingConnections[id] else {
            throw TCPStateMachineError.connectionNotFound(id)
        }

        // ACK must be our SYN + 1
        let expectedAck = (conn.localSeq &+ 1)
        if ackNumber >= expectedAck {
            conn.state = .established
            conn.remoteSeq = seqNumber
            conn.localAck = conn.localSeq &+ 1
            conn.updateActivity()
            pendingConnections.removeValue(forKey: id)
            connections[id] = conn
            return conn
        }

        conn.remoteAck = ackNumber
        conn.updateActivity()
        pendingConnections[id] = conn
        return nil
    }

    /// Handle incoming data on an established connection.
    /// Returns the data received and any response packets needed.
    public func handleData(
        id: TCPConnectionID,
        seqNumber: UInt32,
        ackNumber: UInt32,
        data: Data
    ) throws -> (state: ManagedTCPConnection, receivedData: Data, responsePackets: [Data]) {
        guard var conn = connections[id] else {
            throw TCPStateMachineError.connectionNotFound(id)
        }

        var responses: [Data] = []

        switch conn.state {
        case .established, .finWait1, .finWait2:
            // Check if this is in-window data
            if seqMatchesWindow(conn: conn, seq: seqNumber, dataLength: UInt32(data.count)) {
                conn.receiveBuffer.append(data)
                conn.remoteSeq = seqNumber &+ UInt32(data.count)

                // Send ACK
                let ack = PacketHandler.buildACK(
                    srcIP: id.dstIP, srcPort: id.dstPort,
                    dstIP: id.srcIP, dstPort: id.srcPort,
                    seq: conn.localSeq,
                    ack: conn.remoteSeq
                )
                responses.append(ack)
            }

        case .closeWait:
            // Connection is closing — ignore new data
            break

        default:
            break
        }

        conn.remoteAck = ackNumber
        conn.updateActivity()
        connections[id] = conn
        return (conn, data, responses)
    }

    /// Handle FIN from remote.
    public func handleRemoteFin(id: TCPConnectionID, seqNumber: UInt32, ackNumber: UInt32) throws -> (state: ManagedTCPConnection, responsePackets: [Data]) {
        guard var conn = connections[id] else {
            throw TCPStateMachineError.connectionNotFound(id)
        }

        var responses: [Data] = []

        switch conn.state {
        case .established:
            conn.state = .closeWait
            conn.remoteSeq = seqNumber &+ 1
            conn.remoteAck = ackNumber

            let ack = PacketHandler.buildACK(
                srcIP: id.dstIP, srcPort: id.dstPort,
                dstIP: id.srcIP, dstPort: id.srcPort,
                seq: conn.localSeq,
                ack: conn.remoteSeq
            )
            responses.append(ack)

        case .finWait1:
            conn.state = .closing
            conn.remoteSeq = seqNumber &+ 1

            let ack = PacketHandler.buildACK(
                srcIP: id.dstIP, srcPort: id.dstPort,
                dstIP: id.srcIP, dstPort: id.srcPort,
                seq: conn.localSeq,
                ack: conn.remoteSeq
            )
            responses.append(ack)

        case .finWait2:
            conn.state = .closed
            conn.remoteSeq = seqNumber &+ 1

            let ack = PacketHandler.buildACK(
                srcIP: id.dstIP, srcPort: id.dstPort,
                dstIP: id.srcIP, dstPort: id.srcPort,
                seq: conn.localSeq,
                ack: conn.remoteSeq
            )
            responses.append(ack)
            connections.removeValue(forKey: id)

        default:
            break
        }

        conn.updateActivity()
        if conn.state != .closed {
            connections[id] = conn
        }
        return (conn, responses)
    }

    /// Initiate a local close (send FIN).
    public func initiateClose(id: TCPConnectionID) throws -> (state: ManagedTCPConnection, finPacket: Data?) {
        guard var conn = connections[id] else {
            throw TCPStateMachineError.connectionNotFound(id)
        }

        switch conn.state {
        case .established:
            conn.state = .finWait1
            conn.localSeq = conn.localSeq &+ 1  // FIN consumes a seq number

            let fin = PacketHandler.buildFINACK(
                srcIP: id.srcIP, srcPort: id.srcPort,
                dstIP: id.dstIP, dstPort: id.dstPort,
                seq: conn.localSeq,
                ack: conn.remoteSeq
            )
            conn.updateActivity()
            connections[id] = conn
            return (conn, fin)

        case .closeWait:
            conn.state = .lastAck
            conn.localSeq = conn.localSeq &+ 1

            let fin = PacketHandler.buildFINACK(
                srcIP: id.srcIP, srcPort: id.srcPort,
                dstIP: id.dstIP, dstPort: id.dstPort,
                seq: conn.localSeq,
                ack: conn.remoteSeq
            )
            conn.updateActivity()
            connections[id] = conn
            return (conn, fin)

        default:
            throw TCPStateMachineError.invalidStateTransition(conn.state, "close")
        }
    }

    /// Handle ACK that acknowledges our data.
    public func handleDataAck(id: TCPConnectionID, ackNumber: UInt32) throws -> ManagedTCPConnection {
        guard var conn = connections[id] else {
            throw TCPStateMachineError.connectionNotFound(id)
        }

        if ackNumber > conn.localAck {
            conn.localAck = ackNumber
        }

        conn.updateActivity()
        connections[id] = conn
        return conn
    }

    /// Handle ACK that acknowledges our FIN (from remote side).
    public func handleFinAck(id: TCPConnectionID, ackNumber: UInt32) throws -> ManagedTCPConnection? {
        guard var conn = connections[id] else {
            throw TCPStateMachineError.connectionNotFound(id)
        }

        switch conn.state {
        case .finWait1:
            conn.state = .finWait2
            conn.localAck = ackNumber
            conn.updateActivity()
            connections[id] = conn
            return conn

        case .closing:
            conn.state = .closed
            conn.localAck = ackNumber
            conn.updateActivity()
            connections.removeValue(forKey: id)
            return conn

        case .lastAck:
            conn.state = .closed
            conn.updateActivity()
            connections.removeValue(forKey: id)
            return conn

        default:
            conn.updateActivity()
            connections[id] = conn
            return nil
        }
    }

    /// Check if a RST was received and close the connection.
    public func handleRST(id: TCPConnectionID) {
        connections.removeValue(forKey: id)
        pendingConnections.removeValue(forKey: id)
    }

    /// Close a connection immediately.
    public func closeConnection(id: TCPConnectionID) {
        connections.removeValue(forKey: id)
        pendingConnections.removeValue(forKey: id)
    }

    /// Send buffered data for a connection.
    public func sendData(id: TCPConnectionID, data: Data) throws -> (state: ManagedTCPConnection, packets: [Data]) {
        guard var conn = connections[id] else {
            throw TCPStateMachineError.connectionNotFound(id)
        }

        guard conn.state == .established || conn.state == .finWait1 || conn.state == .finWait2 else {
            throw TCPStateMachineError.invalidStateTransition(conn.state, "send data")
        }

        // Buffer the data
        conn.sendBuffer.append(data)

        // Build packet
        let packet = PacketHandler.buildTCPPacket(
            srcIP: id.srcIP, srcPort: id.srcPort,
            dstIP: id.dstIP, dstPort: id.dstPort,
            seq: conn.localSeq,
            ack: conn.remoteSeq,
            flags: 0x18,  // PSH + ACK
            windowSize: conn.localWindow,
            payload: data
        )

        conn.localSeq = conn.localSeq &+ UInt32(data.count)
        conn.updateActivity()
        connections[id] = conn

        return (conn, [packet])
    }

    /// Read received data from a connection's buffer.
    public func readData(id: TCPConnectionID, maxBytes: Int = 65536) throws -> (state: ManagedTCPConnection, data: Data) {
        guard var conn = connections[id] else {
            throw TCPStateMachineError.connectionNotFound(id)
        }

        let bytesToRead = min(maxBytes, conn.receiveBuffer.count)
        let data = conn.receiveBuffer.prefix(bytesToRead)
        conn.receiveBuffer.removeFirst(bytesToRead)
        conn.updateActivity()
        connections[id] = conn

        return (conn, Data(data))
    }

    /// Get all active connection IDs.
    public func activeConnectionIDs() -> [TCPConnectionID] {
        Array(connections.keys)
    }

    /// Get the count of active connections.
    public var connectionCount: Int {
        connections.count
    }

    // MARK: - Private

    private func seqMatchesWindow(conn: ManagedTCPConnection, seq: UInt32, dataLength: UInt32) -> Bool {
        let windowStart = conn.localAck
        let windowEnd = conn.localAck &+ UInt32(conn.localWindow)
        let dataEnd = seq &+ dataLength

        if dataEnd <= windowStart && dataLength > 0 {
            return false  // Data is too old
        }
        if seq > windowEnd &+ 1000 {
            return false  // Data is too far in the future
        }
        return true
    }

    private func runCleanupLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            await cleanupTimedOutConnections()
        }
    }

    private func cleanupTimedOutConnections() {
        let now = ContinuousClock.now
        for (id, conn) in connections {
            if now - conn.lastActivity >= connectionTimeout {
                connections.removeValue(forKey: id)
            }
        }
        for (id, conn) in pendingConnections {
            if now - conn.lastActivity >= connectionTimeout {
                pendingConnections.removeValue(forKey: id)
            }
        }
    }
}

// ============================================================
// MARK: - Legacy UserSpaceTCP (backward compatibility)
// ============================================================

public struct LegacyTCPConnectionState: Sendable {
    public let localIP: String
    public let localPort: UInt16
    public let remoteIP: String
    public let remotePort: UInt16
    public var state: LegacyTCPState

    public enum LegacyTCPState: String, Sendable {
        case synSent
        case established
        case closing
        case closed
    }
}

/// Build a SYN-ACK response packet (IP + TCP headers).
/// TCP checksum uses proper pseudo-header per RFC 793.
private func buildLegacySYNACK(srcIP: String, srcPort: UInt16, dstIP: String, dstPort: UInt16) -> Data {
    let srcParts = srcIP.split(separator: ".").compactMap { UInt8($0) }
    let dstParts = dstIP.split(separator: ".").compactMap { UInt8($0) }

    // --- TCP header (20 bytes) ---
    var tcp = Data(count: 20)
    tcp[0] = UInt8(srcPort >> 8)
    tcp[1] = UInt8(srcPort & 0xFF)
    tcp[2] = UInt8(dstPort >> 8)
    tcp[3] = UInt8(dstPort & 0xFF)
    let seq = UInt32.random(in: 0...UInt32.max)
    tcp[4] = UInt8((seq >> 24) & 0xFF)
    tcp[5] = UInt8((seq >> 16) & 0xFF)
    tcp[6] = UInt8((seq >> 8) & 0xFF)
    tcp[7] = UInt8(seq & 0xFF)
    tcp[12] = 0x50 // data offset = 5 (20 bytes)
    tcp[13] = 0x12 // SYN + ACK
    tcp[14] = UInt8(65535 >> 8)  // window size
    tcp[15] = UInt8(65535 & 0xFF)

    // --- IPv4 header (20 bytes) ---
    let totalLength = UInt16(20 + 20)
    var ip = Data(count: 20)
    ip[0] = 0x45  // version=4, IHL=5
    ip[2] = UInt8(totalLength >> 8)
    ip[3] = UInt8(totalLength & 0xFF)
    ip[8] = 64    // TTL
    ip[9] = 6     // Protocol = TCP
    ip[12] = srcParts.count >= 4 ? srcParts[0] : 0
    ip[13] = srcParts.count >= 4 ? srcParts[1] : 0
    ip[14] = srcParts.count >= 4 ? srcParts[2] : 0
    ip[15] = srcParts.count >= 4 ? srcParts[3] : 0
    ip[16] = dstParts.count >= 4 ? dstParts[0] : 0
    ip[17] = dstParts.count >= 4 ? dstParts[1] : 0
    ip[18] = dstParts.count >= 4 ? dstParts[2] : 0
    ip[19] = dstParts.count >= 4 ? dstParts[3] : 0

    // IP header checksum
    let ipChecksum = PacketHandler.computeChecksum(ip)
    ip[10] = UInt8(ipChecksum >> 8)
    ip[11] = UInt8(ipChecksum & 0xFF)

    // TCP checksum with pseudo-header (RFC 793)
    var pseudoHeader = Data()
    pseudoHeader.append(contentsOf: ip[12...15])  // src IP
    pseudoHeader.append(contentsOf: ip[16...19])  // dst IP
    pseudoHeader.append(0)        // reserved
    pseudoHeader.append(6)        // protocol = TCP
    let tcpLength = UInt16(tcp.count)
    pseudoHeader.append(UInt8(tcpLength >> 8))
    pseudoHeader.append(UInt8(tcpLength & 0xFF))
    let tcpChecksum = PacketHandler.computeChecksum(pseudoHeader + tcp)
    tcp[16] = UInt8(tcpChecksum >> 8)
    tcp[17] = UInt8(tcpChecksum & 0xFF)

    return ip + tcp
}

public final class UserSpaceTCP: @unchecked Sendable {
    private var connections: [String: LegacyTCPConnectionState]
    private let lock = NSLock()

    public init() {
        self.connections = [:]
    }

    public func connectionKey(localIP: String, localPort: UInt16, remoteIP: String, remotePort: UInt16) -> String {
        "\(localIP):\(localPort)-\(remoteIP):\(remotePort)"
    }

    public func onSYN(localIP: String, localPort: UInt16, remoteIP: String, remotePort: UInt16) -> Data {
        let key = connectionKey(localIP: localIP, localPort: localPort, remoteIP: remoteIP, remotePort: remotePort)

        lock.lock()
        defer { lock.unlock() }

        connections[key] = LegacyTCPConnectionState(
            localIP: localIP, localPort: localPort,
            remoteIP: remoteIP, remotePort: remotePort,
            state: .synSent
        )

        return buildLegacySYNACK(
            srcIP: remoteIP, srcPort: remotePort,
            dstIP: localIP, dstPort: localPort
        )
    }

    public func onACK(localIP: String, localPort: UInt16, remoteIP: String, remotePort: UInt16) -> Bool {
        let key = connectionKey(localIP: localIP, localPort: localPort, remoteIP: remoteIP, remotePort: remotePort)

        lock.lock()
        defer { lock.unlock() }

        guard var conn = connections[key], conn.state == .synSent else { return false }
        conn.state = .established
        connections[key] = conn
        return true
    }

    public func isEstablished(localIP: String, localPort: UInt16, remoteIP: String, remotePort: UInt16) -> Bool {
        let key = connectionKey(localIP: localIP, localPort: localPort, remoteIP: remoteIP, remotePort: remotePort)
        lock.lock()
        defer { lock.unlock() }
        return connections[key]?.state == .established
    }

    public func closeConnection(localIP: String, localPort: UInt16, remoteIP: String, remotePort: UInt16) {
        let key = connectionKey(localIP: localIP, localPort: localPort, remoteIP: remoteIP, remotePort: remotePort)
        lock.lock()
        defer { lock.unlock() }
        connections.removeValue(forKey: key)
    }
}
