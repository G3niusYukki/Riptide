import Foundation

// MARK: - Error Types

/// Errors that can occur during mihomo runtime operations.
public enum RuntimeError: Error, Equatable, Sendable {
    /// The helper tool is not installed.
    case helperNotInstalled
    /// Failed to generate the mihomo configuration.
    case configGenerationFailed(String)
    /// Failed to launch mihomo via helper.
    case launchFailed(String)
    /// The mihomo API is not available.
    case apiNotAvailable
    /// The runtime is already running.
    case alreadyRunning
    /// The runtime is not running.
    case notRunning
}

// MARK: - Protocol Definition

/// Protocol defining the interface for mihomo runtime management.
/// This allows for mocking in tests.
public protocol MihomoRuntimeManaging: Actor {
    /// Whether the runtime is currently running.
    var isRunning: Bool { get }
    /// Current runtime mode (system proxy or TUN).
    var currentMode: RuntimeMode? { get }
    /// Current active profile.
    var currentProfile: TunnelProfile? { get }
    /// XPC connection to the privileged helper tool.
    var helperConnection: HelperToolConnection { get }

    /// Sets up the runtime by creating necessary directories.
    func setup() async throws

    /// Starts the mihomo runtime with the specified mode and profile.
    func start(mode: RuntimeMode, profile: TunnelProfile) async throws

    /// Stops the mihomo runtime.
    func stop() async throws

    /// Switches the active proxy in the GLOBAL proxy group.
    func switchProxy(to proxyName: String) async throws

    /// Gets the list of available proxies.
    func getProxyStatus() async throws -> [ProxyInfo]

    /// Gets the list of active connections.
    func getConnections() async throws -> [ConnectionInfo]

    /// Gets current traffic statistics.
    func getTraffic() async throws -> (up: Int, down: Int)
}

// MARK: - Sendable Wrapper for API Client

/// Wrapper for MihomoAPIClient that provides @unchecked Sendable conformance.
/// The API client is thread-safe as it's an actor itself.
private final class SendableAPIClient: @unchecked Sendable {
    let client: MihomoAPIClient

    init(_ client: MihomoAPIClient) {
        self.client = client
    }
}

// MARK: - MihomoRuntimeManager

/// Main orchestrator that coordinates config generation, XPC helper connection, and API control.
/// Manages the complete lifecycle of the mihomo core process.
public actor MihomoRuntimeManager: MihomoRuntimeManaging {

    // MARK: - Properties

    /// Paths for mihomo file system layout.
    public let paths: MihomoPaths

    /// XPC connection to the privileged helper tool.
    public let helperConnection: HelperToolConnection

    /// API client for communicating with the running mihomo process.
    private var apiClientWrapper: SendableAPIClient?

    /// Whether the runtime is currently running.
    private(set) public var isRunning: Bool = false

    /// Current runtime mode (system proxy or TUN).
    private(set) public var currentMode: RuntimeMode?

    /// Current active profile.
    private(set) public var currentProfile: TunnelProfile?

    /// Default API port used by mihomo.
    private let defaultAPIPort = 9090

    /// Default mixed proxy port.
    private let defaultMixedPort = 6152

    /// Health check retry configuration.
    private let healthCheckRetries = 10
    private let healthCheckRetryInterval: UInt64 = 500_000_000  // 500ms in nanoseconds

    // MARK: - Initialization

    /// Creates a new MihomoRuntimeManager with the specified dependencies.
    /// - Parameters:
    ///   - paths: The paths instance for file system operations.
    ///   - helperConnection: The XPC connection to the helper tool.
    public init(
        paths: MihomoPaths = MihomoPaths(),
        helperConnection: HelperToolConnection = HelperToolConnection()
    ) {
        self.paths = paths
        self.helperConnection = helperConnection
    }

    // MARK: - Setup

    /// Sets up the runtime by creating necessary directories.
    /// - Throws: FileManager errors if directory creation fails.
    public func setup() async throws {
        try paths.createDirectories()
    }

    /// Gets the XPC proxy to the helper tool wrapped in a Sendable container.
    /// - Returns: Sendable wrapper containing the HelperToolProtocol proxy.
    /// - Throws: RuntimeError if helper is not installed.
    public func getHelperProxy() async throws -> SendableHelperProxy {
        let helperInstalled = await helperConnection.isHelperInstalled()
        guard helperInstalled else {
            throw RuntimeError.helperNotInstalled
        }
        return try await helperConnection.getHelperProxy()
    }

    /// Gets the current mihomo status from the helper tool.
    /// - Returns: The decoded MihomoStatus if available.
    /// - Throws: RuntimeError if helper is not installed or status cannot be decoded.
    public func getMihomoStatus() async throws -> MihomoStatus {
        let helperInstalled = await helperConnection.isHelperInstalled()
        guard helperInstalled else {
            throw RuntimeError.helperNotInstalled
        }

        let (data, error) = await helperConnection.getMihomoStatus()

        if let error {
            throw RuntimeError.launchFailed(error.localizedDescription)
        }

        guard let data else {
            throw RuntimeError.notRunning
        }

        do {
            let status = try JSONDecoder().decode(MihomoStatus.self, from: data)
            return status
        } catch {
            throw RuntimeError.apiNotAvailable
        }
    }

    // MARK: - Lifecycle Control

    /// Starts the mihomo runtime with the specified mode and profile.
    /// - Parameters:
    ///   - mode: The runtime mode (system proxy or TUN).
    ///   - profile: The tunnel profile containing configuration.
    /// - Throws: RuntimeError if startup fails at any step.
    public func start(mode: RuntimeMode, profile: TunnelProfile) async throws {
        // 1. Verify not already running
        guard !isRunning else {
            throw RuntimeError.alreadyRunning
        }

        // 2. Check helper installed
        let helperInstalled = await helperConnection.isHelperInstalled()
        guard helperInstalled else {
            throw RuntimeError.helperNotInstalled
        }

        // 3. Setup directories
        do {
            try await setup()
        } catch {
            throw RuntimeError.configGenerationFailed("Failed to create directories: \(error.localizedDescription)")
        }

        // 4. Generate config YAML
        let generationOptions = MihomoConfigGenerator.GenerationOptions(
            mode: mode,
            mixedPort: defaultMixedPort,
            apiPort: defaultAPIPort,
            logLevel: "info",
            allowLAN: false,
            ipv6: true
        )

        let configYAML = MihomoConfigGenerator.generate(
            config: profile.config,
            options: generationOptions
        )

        // 5. Write config to file (with backup)
        do {
            try writeConfigWithBackup(yaml: configYAML)
        } catch {
            throw RuntimeError.configGenerationFailed("Failed to write config: \(error.localizedDescription)")
        }

        // 6. Launch via XPC helper and wait for result
        let configPath = paths.configFileURL.path
        let modeString = mode == .systemProxy ? "systemProxy" : "tun"

        let launchError = await helperConnection.launchMihomo(
            configPath: configPath,
            mode: modeString
        )

        if let error = launchError {
            throw RuntimeError.launchFailed(error.localizedDescription)
        }

        // 7. Initialize API client
        let apiURL = URL(string: "http://127.0.0.1:\(defaultAPIPort)")!
        let client = MihomoAPIClient(baseURL: apiURL)
        apiClientWrapper = SendableAPIClient(client)

        // 8. Wait for API ready (health check with retries)
        guard let wrapper = apiClientWrapper else {
            throw RuntimeError.apiNotAvailable
        }

        var apiReady = false
        for attempt in 1...healthCheckRetries {
            apiReady = await wrapper.client.healthCheck()
            if apiReady {
                break
            }
            if attempt < healthCheckRetries {
                try? await Task.sleep(nanoseconds: healthCheckRetryInterval)
            }
        }

        guard apiReady else {
            // Attempt cleanup on failure
            _ = await helperConnection.terminateMihomo()
            throw RuntimeError.apiNotAvailable
        }

        // 9. Set isRunning = true
        isRunning = true
        currentMode = mode
        currentProfile = profile
    }

    /// Stops the mihomo runtime.
    /// - Throws: RuntimeError if shutdown fails or runtime is not running.
    public func stop() async throws {
        // 1. Verify running
        guard isRunning else {
            throw RuntimeError.notRunning
        }

        // 2. Terminate via XPC helper
        let terminationError = await helperConnection.terminateMihomo()

        // 3. Wait for termination
        if terminationError == nil {
            await waitForTermination()
        }

        // 4. Disconnect XPC
        await helperConnection.disconnect()

        // 5. Cleanup API client
        apiClientWrapper = nil

        // 6. Set isRunning = false
        isRunning = false
        currentMode = nil
        // Keep currentProfile for reference
    }

    // MARK: - API Operations

    /// Switches the active proxy in the GLOBAL proxy group.
    /// - Parameter proxyName: The name of the proxy to switch to.
    /// - Throws: RuntimeError if not running or API operation fails.
    public func switchProxy(to proxyName: String) async throws {
        guard let wrapper = apiClientWrapper, isRunning else {
            throw RuntimeError.notRunning
        }

        do {
            try await wrapper.client.switchProxy(to: proxyName, inGroup: "GLOBAL")
        } catch is MihomoAPIError {
            throw RuntimeError.apiNotAvailable
        } catch {
            throw RuntimeError.apiNotAvailable
        }
    }

    /// Gets the list of available proxies.
    /// - Returns: Array of ProxyInfo objects.
    /// - Throws: RuntimeError if not running or API operation fails.
    public func getProxyStatus() async throws -> [ProxyInfo] {
        guard let wrapper = apiClientWrapper, isRunning else {
            throw RuntimeError.notRunning
        }

        do {
            return try await wrapper.client.getProxies()
        } catch is MihomoAPIError {
            throw RuntimeError.apiNotAvailable
        } catch {
            throw RuntimeError.apiNotAvailable
        }
    }

    /// Gets the list of active connections.
    /// - Returns: Array of ConnectionInfo objects.
    /// - Throws: RuntimeError if not running or API operation fails.
    public func getConnections() async throws -> [ConnectionInfo] {
        guard let wrapper = apiClientWrapper, isRunning else {
            throw RuntimeError.notRunning
        }

        do {
            return try await wrapper.client.getConnections()
        } catch is MihomoAPIError {
            throw RuntimeError.apiNotAvailable
        } catch {
            throw RuntimeError.apiNotAvailable
        }
    }

    /// Gets current traffic statistics.
    /// - Returns: Tuple of (upload, download) in bytes.
    /// - Throws: RuntimeError if not running or API operation fails.
    public func getTraffic() async throws -> (up: Int, down: Int) {
        guard let wrapper = apiClientWrapper, isRunning else {
            throw RuntimeError.notRunning
        }

        do {
            return try await wrapper.client.getTraffic()
        } catch is MihomoAPIError {
            throw RuntimeError.apiNotAvailable
        } catch {
            throw RuntimeError.apiNotAvailable
        }
    }

    // MARK: - Private Methods

    /// Writes the config YAML to file with backup of existing config.
    /// - Parameter yaml: The YAML configuration string.
    /// - Throws: FileManager errors if write fails.
    private func writeConfigWithBackup(yaml: String) throws {
        let fm = FileManager.default
        let configPath = paths.configFileURL.path
        let backupPath = paths.configBackupURL.path

        // Backup existing config if present
        if fm.fileExists(atPath: configPath) {
            // Remove old backup if exists
            if fm.fileExists(atPath: backupPath) {
                try fm.removeItem(atPath: backupPath)
            }
            // Move current to backup
            try fm.moveItem(atPath: configPath, toPath: backupPath)
        }

        // Write new config
        try yaml.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    /// Waits for the mihomo process to terminate.
    private func waitForTermination() async {
        // Poll the API client to confirm termination
        guard let wrapper = apiClientWrapper else { return }

        var terminated = false
        var attempts = 0
        let maxAttempts = 10

        while !terminated && attempts < maxAttempts {
            let isHealthy = await wrapper.client.healthCheck()
            terminated = !isHealthy
            if !terminated {
                attempts += 1
                try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms
            }
        }
    }
}
