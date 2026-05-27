import Foundation
import Testing
@testable import Riptide

@Suite("MITMHTTPSInterceptor")
struct MITMHTTPSInterceptorTests {
    @Test("intercepted connection terminates client TLS and re-establishes upstream TLS")
    func interceptedConnectionTerminatesClientTLSAndReestablishesUpstreamTLS() async throws {
        let clientSide = MemoryTransportPair()
        let upstreamSide = MemoryTransportPair()

        let originCA = CertificateAuthority(commonName: "Origin Test CA", organization: "Riptide Tests")
        try await originCA.generateCertificate()
        let originIdentity = try await originCA.generateIdentity(for: "example.com")
        let originTLS = try MITMTLSSession.server(over: upstreamSide.server, identity: originIdentity)

        let manager = MITMManager(config: MITMConfig(enabled: true, hosts: ["example.com"]))
        let interceptor = MITMHTTPSInterceptor(
            mitmManager: manager,
            verifyUpstreamCertificates: false
        )
        let runtime = LiveTunnelRuntime(
            proxyDialer: TCPTransportDialer(),
            directDialer: TCPTransportDialer(),
            dnsPipeline: DNSPipeline()
        )

        let relayTask = Task {
            try await interceptor.handleConnection(
                clientSession: clientSide.server,
                target: ConnectionTarget(host: "example.com", port: 443),
                upstreamSession: upstreamSide.client,
                connectionID: UUID(),
                runtime: runtime
            )
        }

        let clientTLS = try MITMTLSSession.client(
            over: clientSide.client,
            serverName: "example.com",
            verifyServerCertificate: false
        )

        let request = Data("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n".utf8)
        async let originRead = originTLS.receive()
        try await clientTLS.send(request)
        #expect(try await originRead == request)

        let response = Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK".utf8)
        async let clientRead = clientTLS.receive()
        try await originTLS.send(response)
        #expect(try await clientRead == response)

        let records = await manager.recentHTTPFlowRecords()
        #expect(records.count == 1)
        #expect(records[0].host == "example.com")
        #expect(records[0].request.method == "GET")
        #expect(records[0].request.path == "/")
        #expect(records[0].response?.statusCode == 200)

        await clientTLS.close()
        await originTLS.close()
        try await relayTask.value
    }
}
