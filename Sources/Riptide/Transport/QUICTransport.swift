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
        try await connect(timeout: .seconds(15))
    }

    public func connect(timeout: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let gate = QUICVoidGate(continuation: continuation)
            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                connection.stateUpdateHandler = nil
                connection.cancel()
                gate.fail(QUICTransportError.connectionFailed("connection timeout"))
            }

            connection.stateUpdateHandler = { [weak self, timeoutTask] state in
                guard let self else { return }
                switch state {
                case .ready:
                    timeoutTask.cancel()
                    self.connection.stateUpdateHandler = nil
                    gate.succeed()
                case .failed(let error):
                    timeoutTask.cancel()
                    self.connection.stateUpdateHandler = nil
                    gate.fail(QUICTransportError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    timeoutTask.cancel()
                    self.connection.stateUpdateHandler = nil
                    gate.fail(QUICTransportError.streamClosed)
                case .waiting(let error):
                    timeoutTask.cancel()
                    self.connection.stateUpdateHandler = nil
                    self.connection.cancel()
                    gate.fail(QUICTransportError.connectionFailed("connection waiting: \(error)"))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    // MARK: - TransportSession

    public func send(_ data: Data) async throws {
        try await send(data, timeout: .seconds(15))
    }

    public func send(_ data: Data, timeout: Duration) async throws {
        guard connection.state == .ready else {
            throw QUICTransportError.connectionFailed("connection not ready: \(connection.state)")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = QUICVoidGate(continuation: continuation)
            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                connection.cancel()
                gate.fail(QUICTransportError.sendFailed("send timeout"))
            }

            connection.send(content: data, completion: .contentProcessed { error in
                timeoutTask.cancel()
                if let error {
                    gate.fail(QUICTransportError.sendFailed(error.localizedDescription))
                } else {
                    gate.succeed()
                }
            })
        }
    }

    public func receive() async throws -> Data {
        try await receive(timeout: .seconds(15))
    }

    public func receive(timeout: Duration) async throws -> Data {
        guard connection.state == .ready else {
            throw QUICTransportError.connectionFailed("connection not ready: \(connection.state)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let gate = QUICDataGate(continuation: continuation)
            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                connection.cancel()
                gate.fail(QUICTransportError.receiveFailed("receive timeout"))
            }

            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                timeoutTask.cancel()
                if let error {
                    gate.fail(QUICTransportError.receiveFailed(error.localizedDescription))
                    return
                }
                if let content {
                    gate.succeed(content)
                } else if isComplete {
                    gate.fail(QUICTransportError.streamClosed)
                } else {
                    gate.fail(QUICTransportError.receiveFailed("empty content"))
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

private final class QUICVoidGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func succeed() {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume()
    }

    func fail(_ error: Error) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(throwing: error)
    }
}

private final class QUICDataGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func succeed(_ data: Data) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: data)
    }

    func fail(_ error: Error) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(throwing: error)
    }
}
