import Foundation
import Security
import X509
import SwiftASN1
import Crypto

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
    private var privateKey: Certificate.PrivateKey?
    private var certificateData: Data?

    /// Keychain label for storing the CA private key.
    private let keyLabel: String

    public init(commonName: String = "Riptide MITM CA", organization: String = "Riptide") {
        self.commonName = commonName
        self.organization = organization
        self.keyLabel = "com.riptide.mitm.ca"
    }

    // MARK: - Key Management

    /// Generates a new P-384 CA private key.
    /// Keys are kept in memory only (not stored in keychain) for safety.
    public func generateKey() throws {
        let privateKey = Certificate.PrivateKey(P384.Signing.PrivateKey())
        self.privateKey = privateKey
    }

    /// DER representation of a Certificate.PublicKey using ASN.1 serialization
    private func derBytes(for publicKey: Certificate.PublicKey) throws -> [UInt8] {
        var serializer = DER.Serializer()
        try publicKey.serialize(into: &serializer)
        return serializer.serializedBytes
    }

    // MARK: - Certificate Management

    /// Generates a self-signed CA certificate using swift-certificates.
    public func generateCertificate() throws {
        // 1. Generate P384 key pair
        let privateKey = Certificate.PrivateKey(P384.Signing.PrivateKey())
        self.privateKey = privateKey

        // 2. Build DN
        let name = try DistinguishedName {
            CountryName("US")
            OrganizationName(self.organization)
            CommonName(self.commonName)
        }

        // 3. Compute SKI from public key bytes
        let publicKeyBytes = try derBytes(for: privateKey.publicKey)
        let ski = ArraySlice(Insecure.SHA1.hash(data: Data(publicKeyBytes)))

        // 4. Build extensions
        let extensions = try Certificate.Extensions {
            Critical(
                BasicConstraints.isCertificateAuthority(maxPathLength: nil)
            )
            KeyUsage(digitalSignature: true, keyCertSign: true, cRLSign: true)
            SubjectKeyIdentifier(keyIdentifier: ski)
        }

        // 5. Generate self-signed certificate
        let certificate = try Certificate(
            version: .v3,
            serialNumber: .init(bytes: ArraySlice<UInt8>(Array(repeating: 0, count: 16).map { _ in UInt8.random(in: 0...255) })),
            publicKey: privateKey.publicKey,
            notValidBefore: Date(),
            notValidAfter: Date() + 3650 * 24 * 3600, // 10 years
            issuer: name,
            subject: name,
            extensions: extensions,
            issuerPrivateKey: privateKey
        )

        // 6. DER encode and store
        var serializer = DER.Serializer()
        try certificate.serialize(into: &serializer)
        self.certificateData = Data(serializer.serializedBytes)
    }

    /// Generates a domain certificate signed by the CA.
    /// - Parameter domain: The domain name (e.g., "example.com")
    /// - Returns: DER-encoded certificate data
    public func generateCertificate(for domain: String) throws -> Data {
        guard let caPrivateKey = privateKey else {
            throw MITMError.certificateGenerationFailed
        }

        // Build CA name for issuer
        let caName = try DistinguishedName {
            CountryName("US")
            OrganizationName(self.organization)
            CommonName(self.commonName)
        }

        // Build domain name
        let domainName = try DistinguishedName {
            CommonName(domain)
        }

        // Generate domain key pair
        let domainPrivateKey = Certificate.PrivateKey(P384.Signing.PrivateKey())
        let domainPublicKey = domainPrivateKey.publicKey

        // Compute public key bytes for SKI
        let domainPublicKeyBytes = try derBytes(for: domainPublicKey)
        let ski = ArraySlice(Insecure.SHA1.hash(data: Data(domainPublicKeyBytes)))

        // Build extensions for domain certificate
        let extensions = try Certificate.Extensions {
            Critical(
                BasicConstraints.isCertificateAuthority(maxPathLength: nil)
            )
            KeyUsage(digitalSignature: true)
            SubjectKeyIdentifier(keyIdentifier: ski)
        }

        // Generate domain certificate signed by CA
        let domainCertificate = try Certificate(
            version: .v3,
            serialNumber: .init(bytes: ArraySlice<UInt8>(Array(repeating: 0, count: 16).map { _ in UInt8.random(in: 0...255) })),
            publicKey: domainPublicKey,
            notValidBefore: Date(),
            notValidAfter: Date() + 365 * 24 * 3600, // 1 year
            issuer: caName,
            subject: domainName,
            extensions: extensions,
            issuerPrivateKey: caPrivateKey
        )

        // DER encode
        var serializer = DER.Serializer()
        try domainCertificate.serialize(into: &serializer)
        return Data(serializer.serializedBytes)
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
