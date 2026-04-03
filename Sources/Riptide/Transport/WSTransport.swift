import Foundation

public actor WSTransportSession: TransportSession {
    private var connected: Bool = false

    public init() {}

    public func send(_ data: Data) async throws {
        throw TransportError.unsupportedSessionOperation("WebSocket transport requires URLSessionWebSocketTask integration")
    }

    public func receive() async throws -> Data {
        throw TransportError.unsupportedSessionOperation("WebSocket transport requires URLSessionWebSocketTask integration")
    }

    public func close() async {
        connected = false
    }
}

public struct WSTransportDialer: TransportDialer {
    public let path: String
    public let host: String

    public init(path: String = "/", host: String = "") {
        self.path = path
        self.host = host
    }

    public func openSession(to node: ProxyNode) async throws -> any TransportSession {
        WSTransportSession()
    }
}
