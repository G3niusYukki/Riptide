import Foundation
import Network
import Testing

@testable import Riptide

@Suite("Local HTTP CONNECT proxy")
struct HTTPConnectProxyTests {
    @Test("parser extracts target and buffered payload")
    func parserExtractsTargetAndBufferedPayload() throws {
        let requestData = Data(
            "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\nPING".utf8
        )

        let parsed = try HTTPConnectRequestParser.parse(requestData)

        #expect(parsed.target == ConnectionTarget(host: "example.com", port: 443))
        #expect(parsed.remainingData == Data("PING".utf8))
    }

    @Test("proxy relays traffic end to end in direct mode")
    func proxyRelaysTrafficEndToEnd() async throws {
        let echoServer = try await LoopbackEchoServer.start()
        defer { echoServer.stop() }

        let runtime = LiveTunnelRuntime(
            proxyDialer: TCPTransportDialer(),
            directDialer: TCPTransportDialer()
        )
        try await runtime.start(
            profile: TunnelProfile(
                name: "direct",
                config: RiptideConfig(mode: .direct, proxies: [], rules: [])
            )
        )

        let proxyServer = LocalHTTPConnectProxyServer(runtime: runtime)
        let endpoint = try await proxyServer.start(host: "127.0.0.1", port: 0)
        defer {
            Task {
                await proxyServer.stop()
                try? await runtime.stop()
            }
        }

        let client = try await TCPTransportDialer().openSession(
            to: ProxyNode(
                name: "local-proxy",
                kind: .http,
                server: endpoint.host,
                port: Int(endpoint.port)
            )
        )
        defer {
            Task {
                await client.close()
            }
        }

        let connectRequest = Data(
            "CONNECT 127.0.0.1:\(echoServer.port) HTTP/1.1\r\nHost: 127.0.0.1:\(echoServer.port)\r\n\r\n".utf8
        )
        try await client.send(connectRequest)

        let response = try await client.receive()
        let responseText = String(data: response, encoding: .utf8)
        #expect(responseText?.contains("200 Connection Established") == true)

        let payload = Data("hello-through-riptide".utf8)
        try await client.send(payload)
        let echoed = try await client.receive()
        #expect(echoed == payload)

        await client.close()

        try await Task.sleep(for: .milliseconds(100))
        let status = await runtime.status()
        #expect(status.bytesUp >= UInt64(payload.count))
        #expect(status.bytesDown >= UInt64(payload.count))
        #expect(status.activeConnections == 0)
    }
}

private final class LoopbackEchoServer: @unchecked Sendable {
    let listener: NWListener
    let port: UInt16

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    static func start() async throws -> LoopbackEchoServer {
        let listener = try NWListener(using: .tcp, on: .any)
        let gate = ResumeGate()

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard gate.tryResume() else { return }
                    continuation.resume(
                        returning: LoopbackEchoServer(
                            listener: listener,
                            port: listener.port?.rawValue ?? 0
                        )
                    )
                case .failed(let error):
                    guard gate.tryResume() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: .global())
                receiveAndEcho(on: connection)
            }

            listener.start(queue: .global())
        }
    }

    func stop() {
        listener.cancel()
    }
}

private final class ResumeGate: @unchecked Sendable {
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

private func receiveAndEcho(on connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
        if let error {
            _ = error
            connection.cancel()
            return
        }

        guard let data, !data.isEmpty else {
            connection.cancel()
            return
        }

        connection.send(content: data, completion: .contentProcessed { sendError in
            if sendError != nil || isComplete {
                connection.cancel()
            } else {
                receiveAndEcho(on: connection)
            }
        })
    }
}
