import Foundation
import Riptide

public actor CLITestMockDialer: TransportDialer {
    private var sessions: [MockCLISession]

    public init(sessions: [MockCLISession]) {
        self.sessions = sessions
    }

    public func openSession(to node: ProxyNode) async throws -> any TransportSession {
        _ = node
        if sessions.isEmpty {
            throw TransportError.noSessionAvailable
        }
        return sessions.removeFirst()
    }
}

public actor MockCLISession: TransportSession {
    private var queue: [Data]

    public init(receiveQueue: [Data]) {
        self.queue = receiveQueue
    }

    public func send(_ data: Data) async throws {
        _ = data
    }

    public func receive() async throws -> Data {
        if queue.isEmpty {
            return Data()
        }
        return queue.removeFirst()
    }

    public func close() async {}
}
