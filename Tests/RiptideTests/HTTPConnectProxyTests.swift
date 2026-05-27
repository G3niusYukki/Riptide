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
            directDialer: TCPTransportDialer(),
            dnsPipeline: DNSPipeline()
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

    @Test("proxy MITM terminates TLS for intercepted CONNECT")
    func proxyMITMTerminatesTLSForInterceptedConnect() async throws {
        let originCA = CertificateAuthority(commonName: "Origin Test CA", organization: "Riptide Tests")
        try await originCA.generateCertificate()
        let originIdentity = try await originCA.generateIdentity(for: "example.com")
        let originResponse = Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK".utf8)
        let originServer = try await LoopbackTLSServer.start(identity: originIdentity, response: originResponse)
        defer { originServer.stop() }

        let runtime = LiveTunnelRuntime(
            proxyDialer: TCPTransportDialer(),
            directDialer: TCPTransportDialer(),
            dnsPipeline: DNSPipeline()
        )
        try await runtime.start(
            profile: TunnelProfile(
                name: "direct",
                config: RiptideConfig(mode: .direct, proxies: [], rules: [])
            )
        )

        let mitmManager = MITMManager(config: MITMConfig(enabled: true, hosts: ["example.com"]))
        let mitmInterceptor = MITMHTTPSInterceptor(
            mitmManager: mitmManager,
            verifyUpstreamCertificates: false
        )
        let proxyServer = LocalHTTPConnectProxyServer(runtime: runtime, mitmInterceptor: mitmInterceptor)
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

        let connectRequest = Data(
            "CONNECT 127.0.0.1:\(originServer.port) HTTP/1.1\r\nHost: example.com:443\r\n\r\n".utf8
        )
        try await client.send(connectRequest)

        let response = try await client.receive()
        #expect(String(data: response, encoding: .utf8)?.contains("200 Connection Established") == true)

        let tlsClient = try MITMTLSSession.client(
            over: client,
            serverName: "example.com",
            verifyServerCertificate: false
        )
        let request = Data("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n".utf8)

        async let capturedRequest = originServer.nextRequest()
        try await tlsClient.send(request)
        #expect(await capturedRequest == request)

        let tlsResponse = try await tlsClient.receive()
        #expect(tlsResponse == originResponse)

        let records = await mitmManager.recentHTTPFlowRecords()
        #expect(records.count == 1)
        #expect(records[0].host == "example.com")
        #expect(records[0].request.method == "GET")
        #expect(records[0].response?.statusCode == 200)

        await tlsClient.close()

        try await Task.sleep(for: .milliseconds(100))
        let status = await runtime.status()
        #expect(status.bytesUp >= UInt64(request.count))
        #expect(status.bytesDown >= UInt64(originResponse.count))
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

private final class LoopbackTLSServer: @unchecked Sendable {
    let listener: NWListener
    let port: UInt16

    private let identity: MITMServerIdentity
    private let response: Data
    private let recorder: TLSRequestRecorder

    private init(
        listener: NWListener,
        port: UInt16,
        identity: MITMServerIdentity,
        response: Data,
        recorder: TLSRequestRecorder
    ) {
        self.listener = listener
        self.port = port
        self.identity = identity
        self.response = response
        self.recorder = recorder
    }

    static func start(identity: MITMServerIdentity, response: Data) async throws -> LoopbackTLSServer {
        let listener = try NWListener(using: .tcp, on: .any)
        let gate = ResumeGate()
        let recorder = TLSRequestRecorder()

        listener.newConnectionHandler = { connection in
            handleTLSLoopbackConnection(
                connection,
                identity: identity,
                response: response,
                recorder: recorder
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard gate.tryResume() else { return }
                    let server = LoopbackTLSServer(
                        listener: listener,
                        port: listener.port?.rawValue ?? 0,
                        identity: identity,
                        response: response,
                        recorder: recorder
                    )
                    continuation.resume(returning: server)
                case .failed(let error):
                    guard gate.tryResume() else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            listener.start(queue: .global())
        }
    }

    func nextRequest() async -> Data {
        await recorder.nextRequest()
    }

    func stop() {
        listener.cancel()
    }
}

private func handleTLSLoopbackConnection(
    _ connection: NWConnection,
    identity: MITMServerIdentity,
    response: Data,
    recorder: TLSRequestRecorder
) {
    connection.start(queue: .global())
    Task {
        do {
            let rawSession = NWTransportSession(connection: connection)
            let tlsSession = try MITMTLSSession.server(over: rawSession, identity: identity)
            let request = try await tlsSession.receive()
            await recorder.record(request)
            try await tlsSession.send(response)
            await tlsSession.close()
        } catch {
            connection.cancel()
        }
    }
}

private actor TLSRequestRecorder {
    private var requests: [Data] = []
    private var waiters: [CheckedContinuation<Data, Never>] = []

    func record(_ request: Data) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: request)
            return
        }
        requests.append(request)
    }

    func nextRequest() async -> Data {
        if requests.isEmpty == false {
            return requests.removeFirst()
        }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
