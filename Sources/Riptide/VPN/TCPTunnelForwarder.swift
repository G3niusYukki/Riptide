import Foundation

/// Manages the forwarding of a single TCP connection through a proxy.
///
/// Each `TCPTunnelForwarder` represents one TCP flow:
///   TUN (local app) → TCPStateMachine → TCPTunnelForwarder → ProxyConnector → Remote server
///
/// The forwarder is created on first data for a connection and lives until
/// the connection is closed (FIN/RST) or times out.
public actor TCPTunnelForwarder {

    // MARK: - Types

    public enum ForwarderError: Error, Equatable, Sendable {
        case connectionNotFound
        case proxyConnectionFailed(String)
        case sendFailed(String)
        case connectionClosed
        case timeout
    }

    // MARK: - State

    private let connectionID: TCPConnectionID
    private let target: ConnectionTarget
    private let proxyNode: ProxyNode
    private var proxyContext: ConnectedProxyContext?
    private var isClosed: Bool
    private let idleTimeout: Duration
    private var lastActivity: ContinuousClock.Instant

    // MARK: - Init

    public init(
        connectionID: TCPConnectionID,
        target: ConnectionTarget,
        proxyNode: ProxyNode,
        idleTimeout: Duration = .seconds(300)
    ) {
        self.connectionID = connectionID
        self.target = target
        self.proxyNode = proxyNode
        self.isClosed = false
        self.idleTimeout = idleTimeout
        self.lastActivity = ContinuousClock.now
    }

    // MARK: - Proxy Connection

    /// Establish the proxy connection for this forwarder.
    /// Must be called before `sendData`.
    public func connect(proxyConnector: ProxyConnector) async throws {
        guard !isClosed else {
            throw ForwarderError.connectionClosed
        }

        do {
            let context = try await proxyConnector.connect(via: proxyNode, to: target)
            proxyContext = context
        } catch {
            throw ForwarderError.proxyConnectionFailed(error.localizedDescription)
        }
    }

    // MARK: - Data Forwarding

    /// Send data through the proxy connection.
    public func sendData(_ data: Data) async throws {
        guard !isClosed else {
            throw ForwarderError.connectionClosed
        }

        guard let context = proxyContext else {
            throw ForwarderError.connectionNotFound
        }

        lastActivity = ContinuousClock.now

        // Send data through the proxy session
        do {
            try await context.connection.session.send(data)
        } catch {
            throw ForwarderError.sendFailed(error.localizedDescription)
        }
    }

    /// Close the forwarder and release resources.
    public func close() async {
        guard !isClosed else { return }
        isClosed = true

        if let context = proxyContext {
            await context.connection.session.close()
            proxyContext = nil
        }
    }

    // MARK: - State

    /// Whether this forwarder is still active.
    public var isActive: Bool {
        !isClosed
    }

    /// Time since last activity.
    public var idleDuration: Duration {
        ContinuousClock.now - lastActivity
    }

    /// Check if this forwarder has been idle too long.
    public var isIdleTimedOut: Bool {
        idleDuration >= idleTimeout
    }
}
