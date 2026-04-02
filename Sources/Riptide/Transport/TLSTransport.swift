import Foundation
import Network

public actor TLSTransportSession: TransportSession {
    private let innerSession: any TransportSession
    private let hostname: String

    public init(innerSession: any TransportSession, hostname: String) {
        self.innerSession = innerSession
        self.hostname = hostname
    }

    public func send(_ data: Data) async throws {
        try await innerSession.send(data)
    }

    public func receive() async throws -> Data {
        try await innerSession.receive()
    }

    public func close() async {
        await innerSession.close()
    }
}

public struct TLSTransportDialer: TransportDialer {
    public let hostname: String
    public let skipCertVerify: Bool

    public init(hostname: String = "", skipCertVerify: Bool = false) {
        self.hostname = hostname
        self.skipCertVerify = skipCertVerify
    }

    public func openSession(to node: ProxyNode) async throws -> any TransportSession {
        let host = NWEndpoint.Host(node.server)
        guard let port = NWEndpoint.Port(rawValue: UInt16(node.port)) else {
            throw TransportError.dialFailed("invalid port")
        }

        let tls = NWParameters.tls
        if !hostname.isEmpty {
            tls.defaultTLS?.peerName = hostname
        }
        let connection = NWConnection(host: host, port: port, using: tls)
        connection.start(queue: .global())

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<any TransportSession, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    cont.resume(returning: TLSTransportSession(
                        innerSession: NWTransportSession(connection: connection),
                        hostname: self.hostname.isEmpty ? node.server : self.hostname
                    ))
                case .failed(let error):
                    cont.resume(throwing: TransportError.dialFailed(String(describing: error)))
                default:
                    break
                }
            }
        }
    }
}
