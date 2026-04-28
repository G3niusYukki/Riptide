import Foundation
import Network

public enum SOCKS5ProxyError: Error, Equatable, Sendable {
    case incompleteHandshake
    case invalidVersion(UInt8)
    case unsupportedCommand(UInt8)
    case noAcceptableAuth
    case invalidAddress
    case clientClosed
}

public actor LocalSOCKS5ProxyServer {
    private let runtime: LiveTunnelRuntime
    private var listener: NWListener?
    private var endpoint: LocalProxyEndpoint?

    public init(runtime: LiveTunnelRuntime) {
        self.runtime = runtime
    }

    public func start(host: String = "127.0.0.1", port: UInt16 = 0) async throws -> LocalProxyEndpoint {
        if let endpoint {
            return endpoint
        }

        let requestedPort = port == 0 ? NWEndpoint.Port.any : try validatedPort(port)
        let listener = try NWListener(using: .tcp, on: requestedPort)
        let gate = ListenerStartGate()

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard gate.tryResume() else { return }
                    let boundPort = listener.port?.rawValue ?? port
                    let endpoint = LocalProxyEndpoint(host: host, port: boundPort)
                    Task {
                        await self?.didStart(listener: listener, endpoint: endpoint)
                    }
                    continuation.resume(returning: endpoint)
                case .failed(let error):
                    guard gate.tryResume() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task {
                    await self?.handleAcceptedConnection(connection)
                }
            }

            listener.start(queue: .global())
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        endpoint = nil
    }

    private func didStart(listener: NWListener, endpoint: LocalProxyEndpoint) {
        self.listener = listener
        self.endpoint = endpoint
    }

    private func handleAcceptedConnection(_ connection: NWConnection) async {
        connection.start(queue: .global())
        let inboundSession = NWTransportSession(connection: connection)

        do {
            let target = try await performHandshake(with: inboundSession)
            let context = try await runtime.openConnection(target: target)

            do {
                try await ConnectionRelay.relay(
                    clientSession: inboundSession,
                    remoteSession: context.connection.session,
                    connectionID: context.connection.id,
                    runtime: runtime,
                    encryptedStream: context.encryptedStream
                )
            } catch {
                await runtime.closeConnection(id: context.connection.id)
                await inboundSession.close()
            }
        } catch {
            await inboundSession.close()
        }
    }

    // MARK: - SOCKS5 Server-Side Handshake

    private func performHandshake(with session: any TransportSession) async throws -> ConnectionTarget {
        // Step 1: Read greeting
        let greeting = try await readExactBytes(2, from: session)
        guard greeting[0] == 0x05 else {
            throw SOCKS5ProxyError.invalidVersion(greeting[0])
        }
        let nmethods = Int(greeting[1])
        guard nmethods > 0 else {
            throw SOCKS5ProxyError.noAcceptableAuth
        }
        let methods = try await readExactBytes(nmethods, from: session)

        // Accept no-auth (0x00) if offered
        guard methods.contains(0x00) else {
            // Tell client no acceptable auth
            try await session.send(Data([0x05, 0xFF]))
            throw SOCKS5ProxyError.noAcceptableAuth
        }

        // Step 2: Send method selection (no auth)
        try await session.send(Data([0x05, 0x00]))

        // Step 3: Read connect request (first 4 bytes to get header)
        let header = try await readExactBytes(4, from: session)
        guard header[0] == 0x05 else {
            throw SOCKS5ProxyError.invalidVersion(header[0])
        }
        guard header[1] == 0x01 else {
            // Send unsupported command error
            try await sendReply(rep: 0x07, bndHost: "0.0.0.0", bndPort: 0, to: session)
            throw SOCKS5ProxyError.unsupportedCommand(header[1])
        }

        let atyp = header[3]
        let (host, remainingAfterHost) = try await readAddress(atyp: atyp, from: session)
        let portBytes: Data
        if let remaining = remainingAfterHost {
            portBytes = try await readWithBuffer(2, buffer: remaining, from: session)
        } else {
            portBytes = try await readExactBytes(2, from: session)
        }
        let port = Int(UInt16(portBytes[0]) << 8 | UInt16(portBytes[1]))

        // Step 4: Send success reply
        try await sendReply(rep: 0x00, bndHost: "0.0.0.0", bndPort: 0, to: session)

        return ConnectionTarget(host: host, port: port)
    }

    private func readAddress(atyp: UInt8, from session: any TransportSession) async throws -> (host: String, remainingBuffer: Data?) {
        switch atyp {
        case 0x01:  // IPv4
            let bytes = try await readExactBytes(4, from: session)
            let host = "\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])"
            return (host, nil)

        case 0x04:  // IPv6
            let bytes = try await readExactBytes(16, from: session)
            var parts: [String] = []
            for i in 0..<8 {
                let hi = bytes[i * 2]
                let lo = bytes[i * 2 + 1]
                parts.append(String(format: "%02x%02x", hi, lo))
            }
            return (parts.joined(separator: ":"), nil)

        case 0x03:  // Domain
            let lenByte = try await readExactBytes(1, from: session)
            let domainLength = Int(lenByte[0])
            let domainBytes = try await readExactBytes(domainLength, from: session)
            guard let host = String(data: domainBytes, encoding: .utf8) else {
                throw SOCKS5ProxyError.invalidAddress
            }
            return (host, nil)

        default:
            throw SOCKS5ProxyError.invalidAddress
        }
    }

    private func sendReply(rep: UInt8, bndHost: String, bndPort: UInt16, to session: any TransportSession) async throws {
        var reply = Data([0x05, rep, 0x00])
        // Use IPv4 bound address
        reply.append(0x01)  // ATYP = IPv4
        let parts = bndHost.split(separator: ".").compactMap { UInt8($0) }
        if parts.count == 4 {
            reply.append(contentsOf: parts)
        } else {
            reply.append(contentsOf: [0, 0, 0, 0])
        }
        reply.append(UInt8(bndPort >> 8))
        reply.append(UInt8(bndPort & 0xFF))
        try await session.send(reply)
    }

    // MARK: - I/O Helpers

    private func readExactBytes(_ count: Int, from session: any TransportSession) async throws -> Data {
        var buffer = Data()
        while buffer.count < count {
            let chunk = try await session.receive()
            if chunk.isEmpty { throw SOCKS5ProxyError.clientClosed }
            buffer.append(chunk)
        }
        return buffer.prefix(count)
    }

    private func readWithBuffer(_ count: Int, buffer: Data, from session: any TransportSession) async throws -> Data {
        if buffer.count >= count {
            return buffer.prefix(count)
        }
        var result = buffer
        while result.count < count {
            let chunk = try await session.receive()
            if chunk.isEmpty { throw SOCKS5ProxyError.clientClosed }
            result.append(chunk)
        }
        return result.prefix(count)
    }

    private func validatedPort(_ value: UInt16) throws -> NWEndpoint.Port {
        guard let port = NWEndpoint.Port(rawValue: value) else {
            throw SOCKS5ProxyError.invalidAddress
        }
        return port
    }
}

private final class ListenerStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard resumed == false else { return false }
        resumed = true
        return true
    }
}
