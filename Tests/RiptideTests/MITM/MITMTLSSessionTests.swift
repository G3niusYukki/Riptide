import Foundation
import Testing
@testable import Riptide

@Suite("MITMTLSSession")
struct MITMTLSSessionTests {
    @Test("server and client sessions perform TLS round trip")
    func serverAndClientSessionsPerformTLSRoundTrip() async throws {
        let pair = MemoryTransportPair()
        let ca = CertificateAuthority()
        try await ca.generateCertificate()
        let identity = try await ca.generateIdentity(for: "example.com")

        let serverTLS = try MITMTLSSession.server(
            over: pair.server,
            identity: identity
        )
        let clientTLS = try MITMTLSSession.client(
            over: pair.client,
            serverName: "example.com",
            verifyServerCertificate: false
        )

        async let serverRead = serverTLS.receive()
        try await clientTLS.send(Data("ping".utf8))
        #expect(try await serverRead == Data("ping".utf8))

        async let clientRead = clientTLS.receive()
        try await serverTLS.send(Data("pong".utf8))
        #expect(try await clientRead == Data("pong".utf8))

        await clientTLS.close()
        await serverTLS.close()
    }
}
