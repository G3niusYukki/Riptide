import Foundation

@testable import Riptide

actor MockTransportSession: TransportSession {
    private var queuedResponses: [Data]
    nonisolated(unsafe) private(set) var sentFrames: [Data]
    nonisolated(unsafe) private(set) var isClosed: Bool

    init(receiveQueue: [Data]) {
        self.queuedResponses = receiveQueue
        self.sentFrames = []
        self.isClosed = false
    }

    func send(_ data: Data) async throws {
        sentFrames.append(data)
    }

    func receive() async throws -> Data {
        if queuedResponses.isEmpty {
            return Data()
        }
        return queuedResponses.removeFirst()
    }

    func close() async {
        isClosed = true
    }

    func getSentFrames() -> [Data] {
        sentFrames
    }

    func getIsClosed() -> Bool {
        isClosed
    }
}

actor MockTransportDialer: TransportDialer {
    private var sessions: [MockTransportSession]
    nonisolated(unsafe) private(set) var openCount: Int

    init(_ sessions: [MockTransportSession]) {
        self.sessions = sessions
        self.openCount = 0
    }

    func openSession(to node: ProxyNode) async throws -> any TransportSession {
        _ = node
        openCount += 1
        if sessions.isEmpty {
            throw TransportError.noSessionAvailable
        }
        return sessions.removeFirst()
    }

    func getOpenCount() -> Int {
        openCount
    }
}
