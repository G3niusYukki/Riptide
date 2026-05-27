import Foundation
import Security
import Testing
import X509
@testable import Riptide

@Suite("CertificateAuthority")
struct CertificateAuthorityTests {
    var ca: CertificateAuthority!
    
    init() {
        ca = CertificateAuthority()
    }

    @Test("generateCertificate creates valid CA")
    func testGenerateCertificateCreatesValidCA() async throws {
        try await ca.generateCertificate()

        let certData = await ca.caCertificateData()
        #expect(certData != nil)

        // Verify DER is parseable
        let cert = try Certificate(derEncoded: Array(certData!))
        #expect(cert.issuer.description.contains("Riptide MITM CA"))
        #expect(cert.issuer.description.contains("Riptide"))
        #expect(cert.issuer.description.contains("US"))

        // Verify is CA certificate
        let basicConstraints = try cert.extensions.basicConstraints
        if case .isCertificateAuthority = basicConstraints {} else {
            Issue.record("Certificate should be a CA")
        }
    }
    
    @Test("generateCertificate for domain")
    func testGenerateCertificateForDomain() async throws {
        try await ca.generateCertificate()
        let domainCertDER = try await ca.generateCertificate(for: "example.com")
        
        let domainCert = try Certificate(derEncoded: Array(domainCertDER))
        #expect(domainCert.subject.description.contains("example.com"))

        #expect(try domainCert.extensions.basicConstraints == .notCertificateAuthority)
        #expect(try domainCert.extensions.extendedKeyUsage == ExtendedKeyUsage([.serverAuth]))
        #expect(String(describing: try domainCert.extensions.subjectAlternativeNames).contains("example.com"))
    }

    @Test("generateIdentity creates matching SecIdentity for domain")
    func testGenerateIdentityForDomain() async throws {
        try await ca.generateCertificate()

        let serverIdentity = try await ca.generateIdentity(for: "example.com")
        var certificate: SecCertificate?
        let certificateStatus = SecIdentityCopyCertificate(serverIdentity.identity, &certificate)
        var privateKey: SecKey?
        let privateKeyStatus = SecIdentityCopyPrivateKey(serverIdentity.identity, &privateKey)

        #expect(serverIdentity.domain == "example.com")
        #expect(certificateStatus == errSecSuccess)
        #expect(certificate != nil)
        #expect(privateKeyStatus == errSecSuccess)
        #expect(privateKey != nil)

        guard let certificate else {
            Issue.record("SecIdentity should expose a certificate")
            return
        }
        #expect(serverIdentity.certificateData == SecCertificateCopyData(certificate) as Data)
    }
    
    @Test("hasKey returns true after generation")
    func testHasKeyAfterGeneration() async throws {
        #expect(await ca.hasKey() == false)
        try await ca.generateCertificate()
        #expect(await ca.hasKey() == true)
    }
    
    @Test("caCertificateData returns nil before generation")
    func testCaCertificateDataNilBeforeGeneration() async throws {
        #expect(await ca.caCertificateData() == nil)
    }
}
