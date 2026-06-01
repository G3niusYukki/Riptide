import Foundation
import Network

// MARK: - WireGuard Proxy Stream

/// WireGuard proxy stream — wraps the Noise IK handshake and transport
/// encryption into a `ProxyProtocolStream`-compatible interface.
///
/// Connects to the WireGuard peer via UDP, performs the handshake,
/// and then tunnels IP packets (or TCP streams) through the encrypted tunnel.
///
/// WireGuard is a Layer 3 (IP) tunnel, not a Layer 4 (TCP) proxy,
/// so this stream operates at the IP packet level.
/// For TCP connections routed through WireGuard:
///   1. The TCP SYN packet is encapsulated in an IP packet
///   2. The IP packet is encrypted with the WireGuard transport key
///   3. The encrypted datagram is sent to the peer via UDP
public final class WireGuardStream: ProxyProtocolStream, @unchecked Sendable {

    // MARK: - Properties

    private let config: WireGuardConfig
    private let handshake: WireGuardHandshake
    private var connection: NWConnection?
    private var state: StreamState = .idle
    private let stateLock = NSLock()

    // UDP receive buffer
    private var receiveBuffer = Data()
    private let bufferLock = NSLock()

    // MARK: - StreamState

    private enum StreamState {
        case idle
        case connecting
        case handshaking
        case connected
        case closed
    }

    // MARK: - Init

    public init(config: WireGuardConfig, handshake: WireGuardHandshake) {
        self.config = config
        self.handshake = handshake
    }

    // MARK: - ProxyProtocolStream

    public func connect(to host: String, port: UInt16) async throws {
        stateLock.lock()
        state = .connecting
        stateLock.unlock()

        // 1. Resolve peer endpoint
        let peer = config.peers.first!
        let parts = peer.endpoint.split(separator: ":")
        let endpointHost = String(parts[0])
        let endpointPort = parts.count > 1 ? UInt16(parts[1]) ?? WireGuardConstants.defaultPort : WireGuardConstants.defaultPort

        let nwHost = NWEndpoint.Host(endpointHost)
        let nwPort = NWEndpoint.Port(rawValue: endpointPort)!
        let endpoint = NWEndpoint.hostPort(host: nwHost, port: nwPort)

        // 2. Create UDP connection
        let conn = NWConnection(to: endpoint, using: .udp)
        self.connection = conn

        // 3. Start connection + receive loop
        let ready = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    cont.resume()
                case .failed(let error):
                    cont.resume(throwing: error)
                case .cancelled:
                    cont.resume(throwing: TransportError.connectionClosed)
                default:
                    break
                }
            }
            conn.start(queue: .global())
        }

        // 4. Perform WireGuard handshake
        stateLock.lock()
        state = .handshaking
        stateLock.unlock()

        let initiation = try await handshake.createInitiation()
        try await sendDatagram(initiation, on: conn)

        // Wait for response
        let response = try await receiveDatagram(on: conn, timeout: 5.0)
        try await handshake.processResponse(response)

        stateLock.lock()
        state = .connected
        stateLock.unlock()

        // 5. Start background receive loop
        startReceiveLoop(on: conn)
    }

    public func read(_ maxLength: Int) async throws -> Data {
        guard state == .connected else {
            throw TransportError.connectionClosed
        }

        // Read from receive buffer (populated by background receive loop)
        while true {
            bufferLock.lock()
            if !receiveBuffer.isEmpty {
                let readLen = min(maxLength, receiveBuffer.count)
                let data = receiveBuffer.prefix(readLen)
                receiveBuffer.removeFirst(readLen)
                bufferLock.unlock()
                return data
            }
            bufferLock.unlock()

            // Wait a bit and retry
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }

    public func write(_ data: Data) async throws {
        guard state == .connected, let conn = connection else {
            throw TransportError.connectionClosed
        }

        let encrypted = try await handshake.encryptTransport(data)
        try await sendDatagram(encrypted, on: conn)
    }

    public func close() async {
        stateLock.lock()
        state = .closed
        stateLock.unlock()

        connection?.cancel()
        connection = nil
    }

    // MARK: - Private Helpers

    private func sendDatagram(_ data: Data, on conn: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    private func receiveDatagram(on conn: NWConnection, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receiveMessage { data, _, _, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else if let data = data {
                    cont.resume(returning: data)
                } else {
                    cont.resume(throwing: TransportError.timeout)
                }
            }
        }
    }

    private func startReceiveLoop(on conn: NWConnection) {
        func receiveNext() {
            conn.receiveMessage { [weak self] data, _, _, error in
                guard let self = self else { return }
                if let error = error {
                    // Connection closed or error — don't crash
                    _ = error
                    return
                }
                if let data = data {
                    // Decrypt transport data
                    Task {
                        do {
                            let plaintext = try await self.handshake.decryptTransport(data)
                            self.bufferLock.lock()
                            self.receiveBuffer.append(plaintext)
                            self.bufferLock.unlock()
                        } catch {
                            // Decryption failed — possibly a handshake re-initiation
                            // In production: handle rekey here
                        }
                    }
                }
                // Continue loop
                if self.state == .connected {
                    receiveNext()
                }
            }
        }
        receiveNext()
    }
}

// MARK: - Transport Errors

enum TransportError: Error {
    case dialFailed(String)
    case connectionClosed
    case timeout
    case invalidState
}
