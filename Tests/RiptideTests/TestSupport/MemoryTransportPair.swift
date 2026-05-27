import Foundation
@testable import Riptide

final class MemoryTransportPair {
    let client: MemoryTransportSession
    let server: MemoryTransportSession

    init() {
        let clientInbox = MemoryTransportInbox()
        let serverInbox = MemoryTransportInbox()
        self.client = MemoryTransportSession(inbox: clientInbox, peerInbox: serverInbox)
        self.server = MemoryTransportSession(inbox: serverInbox, peerInbox: clientInbox)
    }
}

private actor MemoryTransportInbox {
    private var queue: [Data] = []
    private var waiters: [CheckedContinuation<Data, Error>] = []
    private var closed = false

    func send(_ data: Data) {
        guard closed == false else { return }
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: data)
            return
        }
        queue.append(data)
    }

    func receive() async throws -> Data {
        if queue.isEmpty == false {
            return queue.removeFirst()
        }
        if closed {
            return Data()
        }

        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func close() {
        closed = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: Data())
        }
    }
}

struct MemoryTransportSession: TransportSession {
    private let inbox: MemoryTransportInbox
    private let peerInbox: MemoryTransportInbox

    fileprivate init(inbox: MemoryTransportInbox, peerInbox: MemoryTransportInbox) {
        self.inbox = inbox
        self.peerInbox = peerInbox
    }

    func send(_ data: Data) async throws {
        await peerInbox.send(data)
    }

    func receive() async throws -> Data {
        try await inbox.receive()
    }

    func close() async {
        await inbox.close()
        await peerInbox.close()
    }
}
