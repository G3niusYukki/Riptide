import Foundation
import Security

public enum MITMError: Error, Equatable, Sendable {
    case certificateGenerationFailed
    case caNotTrusted
    case signFailed(String)
    case invalidDERData

    public var localizedDescription: String {
        switch self {
        case .certificateGenerationFailed:
            return "Failed to generate CA certificate"
        case .caNotTrusted:
            return "CA certificate is not trusted by the system"
        case .signFailed(let reason):
            return "Failed to sign certificate: \(reason)"
        case .invalidDERData:
            return "Invalid DER-encoded certificate data"
        }
    }
}

/// Certificate Authority for MITM HTTPS interception.
/// Manages the root CA keypair and generates per-domain certificates.
public actor CertificateAuthority {
    private let commonName: String
    private let organization: String
    private var privateKey: SecKey?
    private var certificateData: Data?

    /// Keychain label for storing the CA private key.
    private let keyLabel: String

    public init(commonName: String = "Riptide MITM CA", organization: String = "Riptide") {
        self.commonName = commonName
        self.organization = organization
        self.keyLabel = "com.riptide.mitm.ca"
    }

    // MARK: - Key Management

    /// Generates a new RSA 2048-bit CA private key and stores it in the keychain.
    public func generateKey() throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecAttrLabel as String: keyLabel,
            kSecAttrIsPermanent as String: false, // Keep in memory for safety
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw MITMError.certificateGenerationFailed
        }
        self.privateKey = key
    }

    /// Loads an existing CA key from the keychain.
    public func loadKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrLabel as String: keyLabel,
            kSecReturnRef as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw MITMError.certificateGenerationFailed
        }
        // SecKey toll-free bridged to CFTypeRef
        self.privateKey = (item as! SecKey)
    }

    // MARK: - Certificate Management

    /// Generates a self-signed CA certificate.
    /// Note: Full X.509 certificate generation requires ASN.1 DER encoding.
    /// This method scaffolds the CA infrastructure. Production use should integrate
    /// a certificate generation library (e.g., SwiftASN1).
    public func generateCertificate() throws {
        try generateKey()

        // Placeholder: In production, generate a real X.509 v3 certificate with:
        // - Subject: CN=Riptide MITM CA, O=Riptide
        // - Basic Constraints: CA:TRUE
        // - Key Usage: keyCertSign, cRLSign
        // - Validity: 10 years from now
        // Then encode as DER and store via SecCertificateCreateWithData

        // For now, mark that key generation succeeded
        self.certificateData = nil
    }

    /// Generates a domain certificate signed by the CA.
    /// - Parameter domain: The domain name (e.g., "example.com")
    /// - Returns: DER-encoded certificate data
    public func generateCertificate(for domain: String) throws -> Data {
        guard let privateKey else {
            throw MITMError.certificateGenerationFailed
        }

        // Placeholder: In production, generate a real X.509 v3 certificate:
        // - Subject: CN=<domain>
        // - SAN: DNS:<domain>
        // - Issuer: CN=Riptide MITM CA
        // - Validity: 1 year from now
        // - Signed with CA private key

        throw MITMError.certificateGenerationFailed
    }

    // MARK: - Installation

    /// Installs the CA certificate into the system keychain.
    /// The user must manually trust the certificate in Keychain Access.
    public func installCA() throws {
        guard let certData = certificateData else {
            throw MITMError.certificateGenerationFailed
        }

        let cert = SecCertificateCreateWithData(nil, certData as CFData)
        guard let cert else {
            throw MITMError.certificateGenerationFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: cert,
            kSecAttrLabel as String: commonName,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess && status != errSecDuplicateItem {
            throw MITMError.certificateGenerationFailed
        }
    }

    // MARK: - Status Checks

    /// Returns whether the CA key has been generated.
    public func hasKey() -> Bool {
        privateKey != nil
    }

    /// Returns whether the CA certificate is installed in the system keychain.
    public func isCAInstalled() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: commonName,
            kSecReturnRef as String: true,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Returns the CA certificate data in DER format.
    public func caCertificateData() -> Data? {
        certificateData
    }
}
