import Security
import Testing
@testable import Riptide

@Suite("MITMManager")
struct MITMManagerTests {
    @Test("ensureCACertificate creates installable certificate")
    func ensureCACertificateCreatesInstallableCertificate() async throws {
        let manager = MITMManager()

        let data = try await manager.ensureCACertificate()
        let certificateData = await manager.caCertificateData()
        let certificate = certificateData.flatMap { SecCertificateCreateWithData(nil, $0 as CFData) }

        #expect(!data.isEmpty)
        #expect(certificateData == data)
        #expect(certificate != nil)
    }

    @Test("caCertificate returns nil before generation")
    func caCertificateNilBeforeGeneration() async {
        let manager = MITMManager()

        let certificateData = await manager.caCertificateData()

        #expect(certificateData == nil)
    }
}
