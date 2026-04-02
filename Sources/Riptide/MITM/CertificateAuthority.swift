import Foundation
import Security

public enum MITMError: Error, Equatable, Sendable {
    case certificateGenerationFailed
    case caNotTrusted
    case signFailed(String)
}

public actor CertificateAuthority {
    private let commonName: String
    private var privateKey: SecKey?
    private var certificate: SecCertificate?

    public init(commonName: String = "Riptide CA") {
        self.commonName = commonName
    }

    public func generateCA() throws {
        let privateKeyAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecAttrIsPermanent as String: true,
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(privateKeyAttrs as CFDictionary, &error) else {
            throw MITMError.certificateGenerationFailed
        }
        self.privateKey = privateKey

        let subject = [
            kSecAttrCommonName as String: commonName,
            kSecAttrOrganization as String: "Riptide",
        ] as CFDictionary

        let certData = SecCertificateCreateWithData(nil, Data()) // placeholder
        _ = certData

        self.certificate = nil
    }

    public func generateCertificate(for domain: String) throws -> SecCertificate {
        guard let _ = privateKey else {
            throw MITMError.certificateGenerationFailed
        }
        throw MITMError.certificateGenerationFailed
    }

    public func isCAInstalled() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: "Riptide CA",
            kSecReturnRef as String: true,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    public func installCA() throws {
        try generateCA()
    }

    public var caCertificate: SecCertificate? {
        certificate
    }
}
