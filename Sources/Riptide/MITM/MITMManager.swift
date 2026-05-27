import Foundation
import Security

/// Manages MITM (Man-in-the-Middle) HTTPS interception.
/// Controls which hosts are intercepted and provides hooks for inspection/modification.
public actor MITMManager {
    private var config: MITMConfig
    private let certificateAuthority: CertificateAuthority
    private var httpFlowRecords: [MITMHTTPFlowRecord] = []

    /// Callback invoked when an intercepted connection's headers are parsed.
    /// Can be used for logging, filtering, or modifying requests.
    public var onRequestIntercepted: ((String, String) -> Void)?
    public var onHTTPFlowUpdated: ((MITMHTTPFlowRecord) -> Void)?

    public init(config: MITMConfig = MITMConfig(), certificateAuthority: CertificateAuthority = CertificateAuthority()) {
        self.config = config
        self.certificateAuthority = certificateAuthority
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

    public func setOnHTTPFlowUpdated(_ handler: @escaping @Sendable (MITMHTTPFlowRecord) -> Void) {
        onHTTPFlowUpdated = handler
    }

    // MARK: - Interception Decision

    /// Returns whether a given host should be intercepted based on current config.
    public func shouldIntercept(_ host: String) -> Bool {
        config.shouldIntercept(host)
    }

    // MARK: - Certificate Management

    /// Ensures the in-memory CA certificate exists and returns DER-encoded data.
    @discardableResult
    public func ensureCACertificate() async throws -> Data {
        if let data = await certificateAuthority.caCertificateData() {
            return data
        }

        try await certificateAuthority.generateCertificate()
        guard let data = await certificateAuthority.caCertificateData() else {
            throw MITMError.certificateGenerationFailed
        }
        return data
    }

    /// Returns the generated CA certificate for installation in the system keychain.
    public func caCertificateData() async -> Data? {
        await certificateAuthority.caCertificateData()
    }

    /// Returns the generated CA certificate for installation in the system keychain.
    public func caCertificate() async -> SecCertificate? {
        guard let data = await certificateAuthority.caCertificateData() else { return nil }
        return SecCertificateCreateWithData(nil, data as CFData)
    }

    /// Generates a per-host server identity signed by Riptide's in-memory CA.
    public func serverIdentity(for host: String) async throws -> MITMServerIdentity {
        try await ensureCACertificate()
        return try await certificateAuthority.generateIdentity(for: host)
    }

    /// Checks if the CA certificate is installed in the keychain.
    public func isCAInstalled() async -> Bool {
        await certificateAuthority.isCAInstalled()
    }

    /// Compatibility alias for older app code. This only confirms installation;
    /// trust settings still need to be verified in Keychain Access.
    public func isCATrusted() async -> Bool {
        await isCAInstalled()
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

    @discardableResult
    public func recordHTTPRequest(host: String, port: Int, request: MITMHTTPRequest) -> UUID {
        let record = MITMHTTPFlowRecord(host: host, port: port, request: request)
        httpFlowRecords.append(record)
        trimHTTPFlowRecords()
        onHTTPFlowUpdated?(record)
        return record.id
    }

    public func recordHTTPResponse(flowID: UUID, response: MITMHTTPResponse) {
        guard let index = httpFlowRecords.firstIndex(where: { $0.id == flowID }) else {
            return
        }

        let updated = httpFlowRecords[index].attaching(response: response)
        httpFlowRecords[index] = updated
        onHTTPFlowUpdated?(updated)
    }

    public func recentHTTPFlowRecords(limit: Int = 200) -> [MITMHTTPFlowRecord] {
        Array(httpFlowRecords.suffix(limit))
    }

    public func clearHTTPFlowRecords() {
        httpFlowRecords.removeAll()
    }

    private func trimHTTPFlowRecords(maxRecords: Int = 500) {
        guard httpFlowRecords.count > maxRecords else { return }
        httpFlowRecords.removeFirst(httpFlowRecords.count - maxRecords)
    }
}
