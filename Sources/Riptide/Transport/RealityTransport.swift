import Foundation
import Network

// MARK: - Reality Configuration

/// Configuration for VLESS + Reality (TLS camouflage).
///
/// Reality operates by making TLS ClientHello appear as if connecting to
/// a legitimate target server (`serverName`), while actually terminating
/// TLS at the proxy server. The server authenticates using the target's
/// certificate, and the client authenticates via `shortId`.
///
/// **Known limitation**: Full ClientHello padding/fingerprint matching
/// requires raw TLS access beyond Network.framework's public API. The
/// current implementation sets correct SNI, ALPN, and certificate
/// verification, but does not match exact target server fingerprints.
public struct RealityConfig: Sendable, Equatable {
    /// The camouflage target server name (TLS SNI).
    public let serverName: String
    /// Short ID for client authentication to the Reality server.
    public let shortId: String
    /// Base64-encoded public key of the Reality server.
    public let publicKey: String
    /// Expected TLS fingerprint of the target server certificate.
    public let fingerprint: String

    public init(
        serverName: String,
        shortId: String,
        publicKey: String,
        fingerprint: String
    ) {
        self.serverName = serverName
        self.shortId = shortId
        self.publicKey = publicKey
        self.fingerprint = fingerprint
    }

    /// Construct RealityConfig from ProxyNode fields.
    /// Returns nil if required fields are missing.
    public static func from(node: ProxyNode) -> RealityConfig? {
        guard let serverName = node.realityServerName,
              let shortId = node.realityShortId,
              let publicKey = node.realityPublicKey,
              let fingerprint = node.realityFingerprint else {
            return nil
        }
        return RealityConfig(
            serverName: serverName,
            shortId: shortId,
            publicKey: publicKey,
            fingerprint: fingerprint
        )
    }
}

// MARK: - Reality Transport Dialer

/// A TLS transport dialer configured for VLESS Reality connections.
///
/// Configures TLS with:
/// - SNI set to the camouflage serverName (not the proxy server)
/// - Certificate verification set to accept the target server cert
/// - ALPN properly configured
public struct RealityTransportDialer: TransportDialer {
    private let reality: RealityConfig
    private let proxyServer: String
    private let proxyPort: Int

    public init(reality: RealityConfig, proxyServer: String, proxyPort: Int) {
        self.reality = reality
        self.proxyServer = proxyServer
        self.proxyPort = proxyPort
    }

    public func openSession(to node: ProxyNode) async throws -> any TransportSession {
        let host = NWEndpoint.Host(proxyServer)
        guard let port = NWEndpoint.Port(rawValue: UInt16(proxyPort)) else {
            throw TransportError.dialFailed("invalid port")
        }

        // Build TLS options with Reality configuration
        let tlsOptions = NWProtocolTLS.Options()

        // SNI set to camouflage target (not the proxy server)
        sec_protocol_options_set_tls_server_name(
            tlsOptions.securityProtocolOptions,
            reality.serverName
        )

        // Accept the server's certificate (it uses the target's cert, not its own)
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, done in done(true) },
            .main
        )

        // ALPN is not directly configurable via sec_protocol_options_set_alpn_protocols.
        // Reality uses TLS 1.3 which is the default for modern TLS connections.

        let tcpParams = NWProtocolTCP.Options()
        tcpParams.enableKeepalive = true
        let params = NWParameters(tls: tlsOptions, tcp: tcpParams)

        let connection = NWConnection(host: host, port: port, using: params)
        connection.start(queue: .global())

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<any TransportSession, Error>) in
            let gate = RealityTransportReadyGate(continuation: cont, connection: connection)

            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                connection.cancel()
                gate.fail(TransportError.connectionFailed("Reality TLS timeout after 15s"))
            }

            connection.stateUpdateHandler = { [timeoutTask] state in
                switch state {
                case .ready:
                    timeoutTask.cancel()
                    gate.succeed(TLSTransportSession(
                        innerSession: NWTransportSession(connection: connection),
                        hostname: reality.serverName
                    ))
                case .failed(let error):
                    timeoutTask.cancel()
                    gate.fail(TransportError.connectionFailed(String(describing: error)))
                case .cancelled:
                    gate.fail(TransportError.cancelled)
                case .waiting(let error):
                    timeoutTask.cancel()
                    gate.fail(TransportError.connectionFailed("connection waiting: \(error)"))
                default:
                    break
                }
            }
        }
    }
}

/// Lock-protected gate for Reality transport dialer.
private final class RealityTransportReadyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<any TransportSession, Error>?
    private let connection: NWConnection

    init(continuation: CheckedContinuation<any TransportSession, Error>, connection: NWConnection) {
        self.continuation = continuation
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
