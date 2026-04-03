import Foundation
import Network

// MARK: - TLSTransportSession

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

// MARK: - TLSTransportDialer

public struct TLSTransportDialer: TransportDialer {
    public init() {}

    public func openSession(to node: ProxyNode) async throws -> any TransportSession {
        let host = NWEndpoint.Host(node.server)
        guard let port = NWEndpoint.Port(rawValue: UInt16(node.port)) else {
            throw TransportError.dialFailed("invalid port")
        }

        // Build TLS options with proper SNI and cert verification
        let tlsOptions = NWProtocolTLS.Options()
        let sniHost = node.sni ?? node.server
        sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, sniHost)
        if node.skipCertVerify == true {
            sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, _, done in
                done(true)
            }, .main)
        }

        // Build TCP parameters
        let tcpParams = NWProtocolTCP.Options()
        tcpParams.enableKeepalive = true
        let params = NWParameters(tls: tlsOptions, tcp: tcpParams)

        let connection = NWConnection(host: host, port: port, using: params)
        connection.start(queue: .global())

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<any TransportSession, Error>) in
            let gate = TLSTransportReadyGate(continuation: cont, sniHost: sniHost, connection: connection)

            // Start timeout task
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                connection.cancel()
                gate.fail(TransportError.connectionFailed("TLS connection timeout after 15s"))
            }

            connection.stateUpdateHandler = { [timeoutTask] state in
                switch state {
                case .ready:
                    timeoutTask.cancel()
                    gate.succeed(TLSTransportSession(
                        innerSession: NWTransportSession(connection: connection),
                        hostname: sniHost
                    ))
                case .failed(let error):
                    timeoutTask.cancel()
                    gate.fail(TransportError.connectionFailed(String(describing: error)))
                case .cancelled:
                    gate.fail(TransportError.cancelled)
                case .waiting(let error):
                    // Connection waiting (e.g. network unreachable) — fail fast
                    timeoutTask.cancel()
                    gate.fail(TransportError.connectionFailed("connection waiting: \(error)"))
                default:
                    break
                }
            }
        }
    }
}

/// Lock-protected gate for TLSTransportDialer — allows a single resume of a CheckedContinuation
/// from a @Sendable context (the NWConnection state handler).
private final class TLSTransportReadyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<any TransportSession, Error>?
    private let sniHost: String
    private let connection: NWConnection

    init(continuation: CheckedContinuation<any TransportSession, Error>, sniHost: String, connection: NWConnection) {
        self.continuation = continuation
        self.sniHost = sniHost
        self.connection = connection
    }

    func succeed(_ session: TLSTransportSession) {
        lock.lock()
        guard let cont = continuation else { lock.unlock(); return }
        continuation = nil
        lock.unlock()
        cont.resume(returning: session)
    }

    func fail(_ error: Error) {
        lock.lock()
        guard let cont = continuation else { lock.unlock(); return }
        continuation = nil
        lock.unlock()
        cont.resume(throwing: error)
    }
}
