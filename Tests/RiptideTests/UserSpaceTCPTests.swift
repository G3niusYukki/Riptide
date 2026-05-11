import XCTest
@testable import Riptide

/// Tests for userspace TCP types: connection IDs, state machine, and managed connections.
final class UserSpaceTCPTests: XCTestCase {

    // MARK: - TCPConnectionID

    func testTCPConnectionIDEquality() {
        let a = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "192.168.1.1", dstPort: 443)
        let b = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "192.168.1.1", dstPort: 443)
        let c = TCPConnectionID(srcIP: "10.0.0.2", srcPort: 12345, dstIP: "192.168.1.1", dstPort: 443)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testTCPConnectionIDHashing() {
        let a = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "192.168.1.1", dstPort: 443)
        let b = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "192.168.1.1", dstPort: 443)

        var set = Set<TCPConnectionID>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1, "Equal IDs should hash to same bucket")
    }

    func testTCPConnectionIDReversed() {
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "192.168.1.1", dstPort: 443)
        let reversed = id.reversed

        XCTAssertEqual(reversed.srcIP, "192.168.1.1")
        XCTAssertEqual(reversed.srcPort, 443)
        XCTAssertEqual(reversed.dstIP, "10.0.0.1")
        XCTAssertEqual(reversed.dstPort, 12345)
    }

    func testTCPConnectionIDReversedReversedIsOriginal() {
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "192.168.1.1", dstPort: 443)
        XCTAssertEqual(id.reversed.reversed, id)
    }

    // MARK: - TCPState

    func testTCPStateEquality() {
        XCTAssertEqual(TCPState.listen, TCPState.listen)
        XCTAssertEqual(TCPState.established, TCPState.established)
        XCTAssertEqual(TCPState.closed, TCPState.closed)
        XCTAssertNotEqual(TCPState.listen, TCPState.established)
        XCTAssertNotEqual(TCPState.synReceived, TCPState.established)
    }

    // MARK: - TCPStateMachine — Server-side (acceptConnection)

    func testAcceptConnectionCreatesPendingConnection() async throws {
        let sm = TCPStateMachine()
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "10.0.0.2", dstPort: 80)

        let (conn, synAckPacket) = try await sm.acceptConnection(id: id)

        XCTAssertEqual(conn.id, id)
        XCTAssertEqual(conn.state, .synReceived)
        XCTAssertFalse(synAckPacket.isEmpty, "SYN-ACK packet should not be empty")

        // Connection is in pendingConnections, not yet in connections
        let count = await sm.connectionCount
        XCTAssertEqual(count, 0, "Pending connection should not count toward connectionCount")
    }

    func testAcceptDuplicateConnectionThrows() async throws {
        let sm = TCPStateMachine()
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "10.0.0.2", dstPort: 80)

        _ = try await sm.acceptConnection(id: id)

        do {
            _ = try await sm.acceptConnection(id: id)
            XCTFail("Expected error for duplicate connection")
        } catch let error as TCPStateMachineError {
            if case .connectionAlreadyExists = error {
                // expected
            } else {
                XCTFail("Unexpected TCPStateMachineError: \(error)")
            }
        }
    }

    func testHandshakeCompletes() async throws {
        let sm = TCPStateMachine()
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "10.0.0.2", dstPort: 80)

        let (conn1, _) = try await sm.acceptConnection(id: id)
        XCTAssertEqual(conn1.state, .synReceived)

        // Complete 3-way handshake
        let conn2 = try await sm.handleHandshakeACK(id: id, ackNumber: conn1.localSeq + 1)
        XCTAssertNotNil(conn2)
        XCTAssertEqual(conn2?.state, .established)

        // Now the connection should be in `connections`
        let count = await sm.connectionCount
        XCTAssertEqual(count, 1)
    }

    func testGetStateAfterHandshake() async throws {
        let sm = TCPStateMachine()
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "10.0.0.2", dstPort: 80)

        // Before any connection
        let state0 = await sm.getState(id: id)
        XCTAssertNil(state0)

        // After accept (pending)
        let (conn, _) = try await sm.acceptConnection(id: id)
        let state1 = await sm.getState(id: id)
        XCTAssertNil(state1, "Pending connection should not appear in getState")

        // After handshake (established)
        _ = try await sm.handleHandshakeACK(id: id, ackNumber: conn.localSeq + 1)
        let state2 = await sm.getState(id: id)
        XCTAssertEqual(state2, .established)
    }

    func testCloseConnection() async throws {
        let sm = TCPStateMachine()
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "10.0.0.2", dstPort: 80)

        let (conn, _) = try await sm.acceptConnection(id: id)
        _ = try await sm.handleHandshakeACK(id: id, ackNumber: conn.localSeq + 1)

        let count1 = await sm.connectionCount
        XCTAssertEqual(count1, 1)

        await sm.closeConnection(id: id)

        let count2 = await sm.connectionCount
        XCTAssertEqual(count2, 0)

        let state = await sm.getState(id: id)
        XCTAssertNil(state)
    }

    func testHandleRST() async throws {
        let sm = TCPStateMachine()
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "10.0.0.2", dstPort: 80)

        _ = try await sm.acceptConnection(id: id)
        await sm.handleRST(id: id)

        // RST removes from pendingConnections too
        let count = await sm.connectionCount
        XCTAssertEqual(count, 0)
    }

    func testActiveConnectionIDsAfterHandshake() async throws {
        let sm = TCPStateMachine()

        let empty = await sm.activeConnectionIDs()
        XCTAssertTrue(empty.isEmpty)

        let id1 = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 1001, dstIP: "10.0.0.2", dstPort: 80)
        let id2 = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 1002, dstIP: "10.0.0.2", dstPort: 80)

        let (c1, _) = try await sm.acceptConnection(id: id1)
        _ = try await sm.handleHandshakeACK(id: id1, ackNumber: c1.localSeq + 1)

        let (c2, _) = try await sm.acceptConnection(id: id2)
        _ = try await sm.handleHandshakeACK(id: id2, ackNumber: c2.localSeq + 1)

        let ids = await sm.activeConnectionIDs()
        XCTAssertEqual(ids.count, 2)
        XCTAssertTrue(ids.contains(id1))
        XCTAssertTrue(ids.contains(id2))
    }

    // MARK: - TCPStateMachine — Client-side (initiateConnection)

    func testInitiateConnection() async throws {
        let sm = TCPStateMachine()
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "10.0.0.2", dstPort: 80)

        let (conn, synPacket) = try await sm.initiateConnection(id: id)

        XCTAssertEqual(conn.id, id)
        XCTAssertEqual(conn.state, .synReceived)
        XCTAssertFalse(synPacket.isEmpty, "SYN packet should not be empty")

        // Connection is pending, not yet established
        let count = await sm.connectionCount
        XCTAssertEqual(count, 0)
    }

    func testInitiateConnectionThenEstablish() async throws {
        let sm = TCPStateMachine()
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "10.0.0.2", dstPort: 80)

        let (conn, _) = try await sm.initiateConnection(id: id)

        // Simulate receiving SYN-ACK from server
        let established = try await sm.handleSynAck(
            id: id,
            ackNumber: conn.localSeq + 1,
            seqNumber: 1000
        )
        XCTAssertNotNil(established)
        XCTAssertEqual(established?.state, .established)

        let count = await sm.connectionCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - TCPStateMachine — Error Handling

    func testHandleHandshakeACKForNonexistentConnection() async {
        let sm = TCPStateMachine()
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "10.0.0.2", dstPort: 80)

        do {
            _ = try await sm.handleHandshakeACK(id: id, ackNumber: 0)
            XCTFail("Expected error for nonexistent connection")
        } catch let error as TCPStateMachineError {
            if case .connectionNotFound = error {
                // expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testHandleSynAckForNonexistentConnection() async {
        let sm = TCPStateMachine()
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "10.0.0.2", dstPort: 80)

        do {
            _ = try await sm.handleSynAck(id: id, ackNumber: 1, seqNumber: 1)
            XCTFail("Expected error")
        } catch {
            // expected
        }
    }

    // MARK: - ManagedTCPConnection

    func testManagedTCPConnectionInit() {
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "10.0.0.2", dstPort: 80)
        let conn = ManagedTCPConnection(id: id)

        XCTAssertEqual(conn.id, id)
        XCTAssertEqual(conn.state, .listen)
        XCTAssertEqual(conn.localWindow, 65535)
        XCTAssertEqual(conn.remoteWindow, 65535)
        XCTAssertTrue(conn.receiveBuffer.isEmpty)
        XCTAssertTrue(conn.sendBuffer.isEmpty)
    }

    func testManagedTCPConnectionUpdateActivity() {
        let id = TCPConnectionID(srcIP: "10.0.0.1", srcPort: 12345, dstIP: "10.0.0.2", dstPort: 80)
        var conn = ManagedTCPConnection(id: id)

        let initialActivity = conn.lastActivity
        conn.updateActivity()
        XCTAssertGreaterThanOrEqual(conn.lastActivity, initialActivity)
    }
}
