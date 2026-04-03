import Foundation
import Network

final class NWConnectionReadyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var _continuation: CheckedContinuation<Void, Error>?
    private var resolved = false

    func wait() async throws {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            guard !resolved else {
                lock.unlock()
                cont.resume(returning: ())
                return
            }
            _continuation = cont
            lock.unlock()
        }
    }

    func fulfill(_ result: Result<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !resolved else { return }
        resolved = true
        _continuation?.resume(with: result)
        _continuation = nil
    }
}

public final class NWTransportSession: TransportSession, @unchecked Sendable {
    private let connection: NWConnection

    public init(connection: NWConnection) {
        self.connection = connection
    }

    public func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: TransportError.sendFailed(String(describing: error)))
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    public func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: TransportError.receiveFailed(String(describing: error)))
                    return
                }
                continuation.resume(returning: data ?? Data())
            }
        }
    }

    public func close() async {
        connection.cancel()
    }
}

public struct TCPTransportDialer: TransportDialer {
    public init() {}

    public func openSession(to node: ProxyNode) async throws -> any TransportSession {
        let host = NWEndpoint.Host(node.server)
        guard let port = NWEndpoint.Port(rawValue: UInt16(node.port)) else {
            throw TransportError.dialFailed("invalid port \(node.port)")
        }

        let connection = NWConnection(host: host, port: port, using: .tcp)
        let gate = NWConnectionReadyGate()

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                gate.fulfill(.success(()))
            case .failed(let error):
                gate.fulfill(.failure(TransportError.dialFailed(String(describing: error))))
            case .cancelled:
                gate.fulfill(.failure(TransportError.dialFailed("connection cancelled")))
            default:
                break
            }
        }

        connection.start(queue: .global())
        try await gate.wait()
        return NWTransportSession(connection: connection)
    }
}

public struct DirectTransportDialer: TransportDialer {
    public init() {}

    public func openSession(to node: ProxyNode) async throws -> any TransportSession {
        let host = NWEndpoint.Host(node.server)
        guard let port = NWEndpoint.Port(rawValue: UInt16(node.port)) else {
            throw TransportError.dialFailed("invalid target port \(node.port)")
        }

        let connection = NWConnection(host: host, port: port, using: .tcp)
        let gate = NWConnectionReadyGate()

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                gate.fulfill(.success(()))
            case .failed(let error):
                gate.fulfill(.failure(TransportError.dialFailed(String(describing: error))))
            case .cancelled:
                gate.fulfill(.failure(TransportError.dialFailed("connection cancelled")))
            default:
                break
            }
        }

        connection.start(queue: .global())
        try await gate.wait()
        return NWTransportSession(connection: connection)
    }
}
