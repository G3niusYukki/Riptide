import Foundation
import Security

/// Manages MITM (Man-in-the-Middle) HTTPS interception.
/// Controls which hosts are intercepted and provides hooks for inspection/modification.
public actor MITMManager {
    private var config: MITMConfig
    private let ca: CertificateAuthority

    /// Callback invoked when an intercepted connection's headers are parsed.
    /// Can be used for logging, filtering, or modifying requests.
    public var onRequestIntercepted: ((String, String) -> Void)?

    public init(config: MITMConfig = MITMConfig(), ca: CertificateAuthority = CertificateAuthority()) {
        self.config = config
        self.ca = ca
    }

    // MARK: - Configuration

    /// Enables MITM interception with the given host patterns.
    public func enable(hosts: [String] = [], excludeHosts: [String] = []) {
        config.enabled = true
        config.hosts = hosts
        config.excludeHosts = excludeHosts
    }

    /// Disables MITM interception.
    public func disable() {
        config.enabled = false
    }

    /// Returns whether MITM is currently enabled.
    public var isEnabled: Bool { config.enabled }

    /// Returns the current config.
    public func getConfig() -> MITMConfig { config }

    /// Updates the config.
    public func setConfig(_ config: MITMConfig) {
        self.config = config
    }

    /// Sets the callback for intercepted request logging.
    public func setOnRequestIntercepted(_ handler: @escaping @Sendable (String, String) -> Void) {
        onRequestIntercepted = handler
    }

    // MARK: - Interception Decision

    /// Returns whether a given host should be intercepted based on current config.
    public func shouldIntercept(_ host: String) -> Bool {
        config.shouldIntercept(host)
    }

    // MARK: - Certificate Management

    /// Returns the CA certificate for installation in the system keychain.
    public func caCertificate() -> SecCertificate? {
        // In production, this would return the actual CA cert
        // For now, the CertificateAuthority needs to generate one first
        return nil
    }

    /// Checks if the CA certificate is trusted in the system keychain.
    public func isCATrusted() -> Bool {
        // Use the same label that CertificateAuthority uses
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: "com.riptide.mitm.ca",
            kSecReturnRef as String: true,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Interception Hooks

    /// Called when an HTTPS connection is about to be intercepted.
    /// Returns true if the connection should proceed with MITM.
    public func willIntercept(host: String, port: Int) -> Bool {
        guard config.shouldIntercept(host) else { return false }

        // Log interception event
        onRequestIntercepted?("INTERCEPT", "\(host):\(port)")
        return true
    }

    /// Records an intercepted request for logging/analysis.
    public func recordInterception(host: String, method: String, path: String) {
        onRequestIntercepted?("\(method) \(path)", host)
    }
}
