import Foundation
import Network

// MARK: - QUIC Transport

/// QUIC transport using `NWProtocolQUIC` (macOS 14+).
/// Used by DoQ (RFC 9250) and Hysteria2.

// MARK: - QUIC Session

/// A QUIC session wrapping an `NWConnection` configured for QUIC.
public final class QUICTransportSession: TransportSession, @unchecked Sendable {

    // MARK: - Errors

    public enum QUICTransportError: Error, Equatable, Sendable {
        case connectionFailed(String)
        case sendFailed(String)
        case receiveFailed(String)
        case streamClosed
        case quicNotAvailable

        public var localizedDescription: String {
            switch self {
            case .connectionFailed(let msg): return "QUIC connection failed: \(msg)"
            case .sendFailed(let msg): return "QUIC send failed: \(msg)"
            case .receiveFailed(let msg): return "QUIC receive failed: \(msg)"
            case .streamClosed: return "QUIC stream closed"
            case .quicNotAvailable: return "QUIC is not available on this platform (requires macOS 14+)"
            }
        }
    }

    // MARK: - State

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.riptide.quic")

    public let id: UUID

    // MARK: - Init

    public init(host: String, port: UInt16, alpn: [String], skipVerify: Bool = false) {
        self.id = UUID()

        // Create QUIC parameters with ALPN
        let quicOptions = NWProtocolQUIC.Options(alpn: alpn)

        // Create connection using QUIC parameters
        let parameters = NWParameters(quic: quicOptions)

        let nwPort = NWEndpoint.Port(rawValue: port)!
        let nwHost = NWEndpoint.Host(host)
        self.connection = NWConnection(host: nwHost, port: nwPort, using: parameters)
    }

    // MARK: - Connection

    public func connect() async throws {
        try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    self.connection.stateUpdateHandler = nil
                    continuation.resume(throwing: QUICTransportError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    self.connection.stateUpdateHandler = nil
                    continuation.resume(throwing: QUICTransportError.streamClosed)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    // MARK: - TransportSession

    public func send(_ data: Data) async throws {
        guard connection.state == .ready else {
            throw QUICTransportError.connectionFailed("connection not ready: \(connection.state)")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: QUICTransportError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func receive() async throws -> Data {
        guard connection.state == .ready else {
            throw QUICTransportError.connectionFailed("connection not ready: \(connection.state)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: QUICTransportError.receiveFailed(error.localizedDescription))
                    return
                }
                if let content {
                    continuation.resume(returning: content)
                } else if isComplete {
                    continuation.resume(throwing: QUICTransportError.streamClosed)
                } else {
                    continuation.resume(throwing: QUICTransportError.receiveFailed("empty content"))
                }
            }
        }
    }

    public func close() async {
        connection.cancel()
    }

    // MARK: - Factory

    /// Create a new QUIC connection session.
    public static func makeSession(
        host: String,
        port: UInt16,
        alpn: [String],
        skipVerify: Bool = false
    ) -> QUICTransportSession {
        QUICTransportSession(host: host, port: port, alpn: alpn, skipVerify: skipVerify)
    }
}
