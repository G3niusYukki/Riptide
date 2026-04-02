import Foundation

public protocol TransportSession: Sendable {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close() async
}

public protocol TransportDialer: Sendable {
    func openSession(to node: ProxyNode) async throws -> any TransportSession
}

public struct PooledTransportConnection: Sendable {
    public let id: UUID
    public let node: ProxyNode
    public let session: any TransportSession

    init(id: UUID = UUID(), node: ProxyNode, session: any TransportSession) {
        self.id = id
        self.node = node
        self.session = session
    }
}

public enum TransportError: Error, Equatable, Sendable {
    case noSessionAvailable
    case unsupportedSessionOperation(String)
    case dialFailed(String)
    case sendFailed(String)
    case receiveFailed(String)
}
