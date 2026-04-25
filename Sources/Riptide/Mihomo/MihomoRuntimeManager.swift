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
    /// TUN mode is intentionally hidden until real mihomo TUN integration is verified.
    case tunUnavailable(String)
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

    /// Closes a specific connection by ID.
    func closeConnection(id: String) async throws

    /// Closes all active connections.
    func closeAllConnections() async throws

    /// Gets current traffic statistics.
    func getTraffic() async throws -> (up: Int, down: Int)

    /// Tests the delay/latency of a proxy.
    /// - Parameters:
    ///   - name: The name of the proxy to test
    ///   - url: Optional test URL (defaults to https://www.google.com)
    ///   - timeout: Timeout in milliseconds (defaults to 5000)
    /// - Returns: The measured delay in milliseconds
    func testProxyDelay(name: String, url: String?, timeout: Int) async throws -> Int

    /// Gets recent log entries from the mihomo API.
    func getLogs(level: String, lines: Int) async throws -> [String]
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

    /// Sudo-based fallback launcher (used when helper is not installed).
    private let sudoLauncher = SudoMihomoLauncher()

    /// Whether the current session was launched via sudo (vs XPC helper).
    private var launchedViaSudo: Bool = false

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

        // 2. Check if helper is installed — if not, fall back to sudo
        let helperInstalled = await helperConnection.isHelperInstalled()

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

        let configPath = paths.configFileURL.path

        // 6. Launch mihomo — XPC helper or sudo fallback
        if helperInstalled {
            // --- XPC Helper path ---
            let modeString = mode == .systemProxy ? "systemProxy" : "tun"
            let launchError = await helperConnection.launchMihomo(
                configPath: configPath,
                mode: modeString
            )
            if let error = launchError {
                throw RuntimeError.launchFailed(error.localizedDescription)
            }
            launchedViaSudo = false
        } else {
            // --- Sudo fallback path ---
            // Try system-wide binary first, then user-space
            let systemBinary = "/Library/Application Support/Riptide/mihomo"
            let userBinary = paths.executable
            let binaryPath: String
            if FileManager.default.isExecutableFile(atPath: systemBinary) {
                binaryPath = systemBinary
            } else if FileManager.default.isExecutableFile(atPath: userBinary) {
                binaryPath = userBinary
            } else {
                throw RuntimeError.launchFailed("mihomo binary not found at \(systemBinary) or \(userBinary)")
            }

            do {
                try await sudoLauncher.launch(binaryPath: binaryPath, configPath: configPath)
            } catch {
                throw RuntimeError.launchFailed("sudo launch failed: \(error.localizedDescription)")
            }
            launchedViaSudo = true
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
            if helperInstalled {
                _ = await helperConnection.terminateMihomo()
            } else {
                try? await sudoLauncher.terminate()
            }
            throw RuntimeError.apiNotAvailable
        }

        // 9. Set system proxy if in systemProxy mode
        if mode == .systemProxy {
            if helperInstalled {
                let service = await detectPrimaryService()
                if let proxyError = await helperConnection.enableSystemProxy(
                    service: service,
                    httpPort: defaultMixedPort,
                    socksPort: 0
                ) {
                    print("[MihomoRuntimeManager] Warning: failed to set system proxy: \(proxyError.localizedDescription)")
                }
            } else {
                try? await sudoEnableSystemProxy()
            }
        }

        // 10. Set isRunning = true
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

        // 2. Clear system proxy first (before killing mihomo)
        if currentMode == .systemProxy {
            if !launchedViaSudo {
                let service = await detectPrimaryService()
                _ = await helperConnection.disableSystemProxy(service: service)
            } else {
                try? await sudoDisableSystemProxy()
            }
        }

        // 3. Terminate mihomo
        if launchedViaSudo {
            try? await sudoLauncher.terminate()
        } else {
            let terminationError = await helperConnection.terminateMihomo()
            if terminationError == nil {
                await waitForTermination()
            }
            await helperConnection.disconnect()
        }

        // 4. Cleanup
        apiClientWrapper = nil
        isRunning = false
        currentMode = nil
        launchedViaSudo = false
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

    /// Closes a specific connection by ID.
    public func closeConnection(id: String) async throws {
        guard let wrapper = apiClientWrapper, isRunning else {
            throw RuntimeError.notRunning
        }
        do {
            try await wrapper.client.closeConnection(id: id)
        } catch is MihomoAPIError {
            throw RuntimeError.apiNotAvailable
        } catch {
            throw RuntimeError.apiNotAvailable
        }
    }

    /// Closes all active connections.
    public func closeAllConnections() async throws {
        guard let wrapper = apiClientWrapper, isRunning else {
            throw RuntimeError.notRunning
        }
        do {
            try await wrapper.client.closeAllConnections()
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

    /// Tests the delay/latency of a proxy.
    /// - Parameters:
    ///   - name: The name of the proxy to test
    ///   - url: Optional test URL (defaults to https://www.google.com)
    ///   - timeout: Timeout in milliseconds (defaults to 5000)
    /// - Returns: The measured delay in milliseconds
    /// - Throws: RuntimeError if not running or API operation fails.
    public func testProxyDelay(name: String, url: String? = nil, timeout: Int = 5000) async throws -> Int {
        guard let wrapper = apiClientWrapper, isRunning else {
            throw RuntimeError.notRunning
        }

        let testURL = url ?? "https://www.google.com"

        do {
            return try await wrapper.client.testProxyDelay(name: name, url: testURL, timeout: timeout)
        } catch is MihomoAPIError {
            throw RuntimeError.apiNotAvailable
        } catch {
            throw RuntimeError.apiNotAvailable
        }
    }

    /// Gets recent log entries from the mihomo API.
    public func getLogs(level: String = "debug", lines: Int = 200) async throws -> [String] {
        guard let wrapper = apiClientWrapper, isRunning else {
            throw RuntimeError.notRunning
        }
        do {
            return try await wrapper.client.getLogs(level: level, lines: lines)
        } catch is MihomoAPIError {
            throw RuntimeError.apiNotAvailable
        } catch {
            throw RuntimeError.apiNotAvailable
        }
    }

    // MARK: - Private Methods

    /// Detects the primary network service name for system proxy configuration.
    private func detectPrimaryService() async -> String {
        let (service, _) = await helperConnection.detectNetworkService()
        return service ?? "Wi-Fi"
    }

    /// Detects the primary network service via command line (for sudo fallback).
    private func detectPrimaryServiceViaCLI() async -> String {
        let service = await runCommand(
            "/usr/sbin/networksetup", "-listallnetworkservices"
        )
        if let output = service {
            let lines = output.components(separatedBy: "\n").dropFirst()
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("*") {
                    return trimmed
                }
            }
        }
        return "Wi-Fi"
    }

    /// Enables system proxy via sudo networksetup (fallback when helper is not installed).
    private func sudoEnableSystemProxy() async throws {
        let service = await detectPrimaryServiceViaCLI()
        let port = "\(defaultMixedPort)"

        try await runSudoCommand("/usr/sbin/networksetup", "-setwebproxy", service, "127.0.0.1", port)
        try await runSudoCommand("/usr/sbin/networksetup", "-setsecurewebproxy", service, "127.0.0.1", port)
    }

    /// Disables system proxy via sudo networksetup (fallback when helper is not installed).
    private func sudoDisableSystemProxy() async throws {
        let service = await detectPrimaryServiceViaCLI()

        try? await runSudoCommand("/usr/sbin/networksetup", "-setwebproxystate", service, "off")
        try? await runSudoCommand("/usr/sbin/networksetup", "-setsecurewebproxystate", service, "off")
        try? await runSudoCommand("/usr/sbin/networksetup", "-setsocksfirewallproxystate", service, "off")
    }

    /// Runs a command with sudo, prompting for password if needed.
    private func runSudoCommand(_ path: String, _ arguments: String...) async throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = [path] + arguments
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw RuntimeError.launchFailed("sudo \(path) failed (exit \(proc.terminationStatus))")
        }
    }

    /// Runs a command and returns stdout (for non-privileged queries).
    private func runCommand(_ path: String, _ arguments: String...) async -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

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
