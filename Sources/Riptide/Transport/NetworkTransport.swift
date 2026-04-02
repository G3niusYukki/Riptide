import Foundation
import Network

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
        connection.start(queue: .global())
        return NWTransportSession(connection: connection)
    }
}

public struct DirectTransportDialer: Sendable {
    public init() {}

    public func openSession(to target: ConnectionTarget) async throws -> any TransportSession {
        let host = NWEndpoint.Host(target.host)
        guard let port = NWEndpoint.Port(rawValue: UInt16(target.port)) else {
            throw TransportError.dialFailed("invalid target port \(target.port)")
        }

        let connection = NWConnection(host: host, port: port, using: .tcp)
        connection.start(queue: .global())
        return NWTransportSession(connection: connection)
    }
}
