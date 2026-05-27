import Security
import Testing
@testable import Riptide

@Suite("MITMManager")
struct MITMManagerTests {
    @Test("ensureCACertificate creates installable certificate")
    func ensureCACertificateCreatesInstallableCertificate() async throws {
        let manager = MITMManager()

        let data = try await manager.ensureCACertificate()
        let certificate = await manager.caCertificate()

        #expect(!data.isEmpty)
        #expect(certificate != nil)
    }

    @Test("caCertificate returns nil before generation")
    func caCertificateNilBeforeGeneration() async {
        let manager = MITMManager()

        let certificate = await manager.caCertificate()

        #expect(certificate == nil)
    }
}
