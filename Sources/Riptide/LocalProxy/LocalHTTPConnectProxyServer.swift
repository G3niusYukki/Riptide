import Foundation
import Network

public struct LocalProxyEndpoint: Equatable, Sendable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

public struct ParsedHTTPConnectRequest: Equatable, Sendable {
    public let target: ConnectionTarget
    public let remainingData: Data

    public init(target: ConnectionTarget, remainingData: Data) {
        self.target = target
        self.remainingData = remainingData
    }
}

public enum HTTPConnectProxyError: Error, Equatable, Sendable {
    case incompleteRequest
    case invalidRequest(String)
    case unsupportedMethod(String)
}

public enum HTTPConnectRequestParser {
    public static func parse(_ data: Data) throws -> ParsedHTTPConnectRequest {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else {
            throw HTTPConnectProxyError.incompleteRequest
        }

        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw HTTPConnectProxyError.invalidRequest("request header is not valid utf-8")
        }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            throw HTTPConnectProxyError.invalidRequest("missing request line")
        }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3 else {
            throw HTTPConnectProxyError.invalidRequest("malformed request line")
        }

        let method = String(parts[0]).uppercased()
        guard method == "CONNECT" else {
            throw HTTPConnectProxyError.unsupportedMethod(method)
        }

        let target = try parseAuthority(String(parts[1]))
        let remaining = Data(data[headerRange.upperBound...])
        return ParsedHTTPConnectRequest(target: target, remainingData: remaining)
    }

    private static func parseAuthority(_ authority: String) throws -> ConnectionTarget {
        let trimmed = authority.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HTTPConnectProxyError.invalidRequest("empty CONNECT authority")
        }

        if trimmed.hasPrefix("[") {
            guard
                let closingBracket = trimmed.lastIndex(of: "]"),
                let separator = trimmed[closingBracket...].firstIndex(of: ":")
            else {
                throw HTTPConnectProxyError.invalidRequest("invalid IPv6 CONNECT authority")
            }

            let hostStart = trimmed.index(after: trimmed.startIndex)
            let host = String(trimmed[hostStart..<closingBracket])
            let port = String(trimmed[trimmed.index(after: separator)...])
            return try makeTarget(host: host, port: port)
        }

        guard let separator = trimmed.lastIndex(of: ":") else {
            throw HTTPConnectProxyError.invalidRequest("CONNECT authority is missing a port")
        }

        let host = String(trimmed[..<separator])
        let port = String(trimmed[trimmed.index(after: separator)...])
        return try makeTarget(host: host, port: port)
    }

    private static func makeTarget(host: String, port: String) throws -> ConnectionTarget {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            throw HTTPConnectProxyError.invalidRequest("CONNECT host is empty")
        }
        guard let portValue = Int(port), (1...65_535).contains(portValue) else {
            throw HTTPConnectProxyError.invalidRequest("CONNECT port is invalid")
        }
        return ConnectionTarget(host: normalizedHost, port: portValue)
    }
}

public actor LocalHTTPConnectProxyServer {
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
            let request = try await readConnectRequest(from: inboundSession)
            let context = try await runtime.openConnection(target: request.target)

            do {
                try await inboundSession.send(successResponse())
                if !request.remainingData.isEmpty {
                    try await context.connection.session.send(request.remainingData)
                    await runtime.recordTransfer(
                        connectionID: context.connection.id,
                        bytesUp: UInt64(request.remainingData.count)
                    )
                }

                try await ConnectionRelay.relay(
                    clientSession: inboundSession,
                    remoteSession: context.connection.session,
                    connectionID: context.connection.id,
                    runtime: runtime
                )
            } catch {
                await runtime.closeConnection(id: context.connection.id)
                await inboundSession.close()
            }
        } catch let error as HTTPConnectProxyError {
            try? await inboundSession.send(errorResponse(for: error))
            await inboundSession.close()
        } catch {
            try? await inboundSession.send(badGatewayResponse())
            await inboundSession.close()
        }
    }

    private func readConnectRequest(from session: any TransportSession) async throws -> ParsedHTTPConnectRequest {
        var buffer = Data()

        while buffer.count < 64 * 1024 {
            do {
                return try HTTPConnectRequestParser.parse(buffer)
            } catch HTTPConnectProxyError.incompleteRequest {
                let chunk = try await session.receive()
                guard !chunk.isEmpty else {
                    throw HTTPConnectProxyError.invalidRequest("client closed before request completed")
                }
                buffer.append(chunk)
            }
        }

        throw HTTPConnectProxyError.invalidRequest("request headers exceeded 65536 bytes")
    }

    private func validatedPort(_ value: UInt16) throws -> NWEndpoint.Port {
        guard let port = NWEndpoint.Port(rawValue: value) else {
            throw HTTPConnectProxyError.invalidRequest("listen port is invalid")
        }
        return port
    }

    private func successResponse() -> Data {
        Data("HTTP/1.1 200 Connection Established\r\nProxy-Agent: Riptide\r\n\r\n".utf8)
    }

    private func errorResponse(for error: HTTPConnectProxyError) -> Data {
        switch error {
        case .unsupportedMethod:
            return Data("HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n".utf8)
        case .incompleteRequest, .invalidRequest:
            return Data("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n".utf8)
        }
    }

    private func badGatewayResponse() -> Data {
        Data("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n".utf8)
    }
}

private final class ListenerStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard resumed == false else {
            return false
        }
        resumed = true
        return true
    }
}

enum ConnectionRelay {
    static func relay(
        clientSession: any TransportSession,
        remoteSession: any TransportSession,
        connectionID: UUID,
        runtime: LiveTunnelRuntime
    ) async throws {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await pump(
                        source: clientSession,
                        sink: remoteSession,
                        connectionID: connectionID,
                        runtime: runtime,
                        direction: .clientToRemote
                    )
                }
                group.addTask {
                    try await pump(
                        source: remoteSession,
                        sink: clientSession,
                        connectionID: connectionID,
                        runtime: runtime,
                        direction: .remoteToClient
                    )
                }

                _ = try await group.next()
                await clientSession.close()
                await remoteSession.close()
                group.cancelAll()

                while let _ = try await group.next() {}
            }
        } catch {
            await clientSession.close()
            await remoteSession.close()
            throw error
        }

        await runtime.closeConnection(id: connectionID)
    }

    private enum RelayDirection {
        case clientToRemote
        case remoteToClient
    }

    private static func pump(
        source: any TransportSession,
        sink: any TransportSession,
        connectionID: UUID,
        runtime: LiveTunnelRuntime,
        direction: RelayDirection
    ) async throws {
        while Task.isCancelled == false {
            let data = try await source.receive()
            if data.isEmpty {
                return
            }

            try await sink.send(data)

            switch direction {
            case .clientToRemote:
                await runtime.recordTransfer(connectionID: connectionID, bytesUp: UInt64(data.count))
            case .remoteToClient:
                await runtime.recordTransfer(connectionID: connectionID, bytesDown: UInt64(data.count))
            }
        }
    }
}
