import Foundation
import os.lock

@testable import Riptide

final class MockTransportSession: @unchecked Sendable, TransportSession {
    private var sentFramesLock = _UnfairLock()
    private var _sentFrames: [Data] = []
    private var _isClosed: Bool = false
    private var receiveQueueLock = _UnfairLock()
    private var _queuedResponses: [Data]

    var sentFrames: [Data] {
        sentFramesLock.withLock { _sentFrames }
    }

    var isClosed: Bool {
        sentFramesLock.withLock { _isClosed }
    }

    init(receiveQueue: [Data]) {
        self._queuedResponses = receiveQueue
    }

    func send(_ data: Data) async throws {
        sentFramesLock.withLock { _sentFrames.append(data) }
    }

    func receive() async throws -> Data {
        receiveQueueLock.withLock {
            if _queuedResponses.isEmpty {
                return Data()
            }
            return _queuedResponses.removeFirst()
        }
    }

    func close() async {
        sentFramesLock.withLock { _isClosed = true }
    }

    func getSentFrames() -> [Data] {
        sentFrames
    }

    func getIsClosed() -> Bool {
        isClosed
    }
}

final class MockTransportDialer: @unchecked Sendable, TransportDialer {
    private var openCountLock = _UnfairLock()
    private var _openCount: Int = 0
    private var sessionsLock = _UnfairLock()
    private var _sessions: [MockTransportSession]

    var openCount: Int {
        openCountLock.withLock { _openCount }
    }

    init(_ sessions: [MockTransportSession]) {
        self._sessions = sessions
    }

    func openSession(to node: ProxyNode) async throws -> any TransportSession {
        _ = node
        openCountLock.withLock { _openCount += 1 }

        var session: (any TransportSession)?
        var sessionError: Error?
        sessionsLock.withLock {
            if _sessions.isEmpty {
                sessionError = TransportError.noSessionAvailable
            } else {
                session = _sessions.removeFirst()
            }
        }
        if let err = sessionError {
            throw err
        }
        return session!
    }

    func getOpenCount() -> Int {
        openCount
    }
}

private struct _UnfairLock: @unchecked Sendable {
    private var _lock = os_unfair_lock()

    @inline(__always)
    mutating func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return body()
    }
}
