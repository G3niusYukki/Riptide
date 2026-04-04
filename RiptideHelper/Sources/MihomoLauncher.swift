import Foundation

// MARK: - Launcher Errors

/// Errors specific to mihomo launching operations.
enum MihomoLauncherError: Error, Equatable {
    case alreadyRunning
    case notRunning
    case launchFailed(String)
    case terminationFailed(String)
    case invalidExecutable
    case invalidConfigPath
}

// MARK: - Launcher

/// Manages the mihomo core process lifecycle.
/// Handles launching, monitoring, and terminating the mihomo binary.
actor MihomoLauncher {

    // MARK: - Properties

    /// The current running process, if any.
    private var process: Process?

    /// Process identifier of the running mihomo.
    private(set) var pid: pid_t?

    /// The mode mihomo was launched in.
    private(set) var launchMode: String?

    /// The config path used for launch.
    private(set) var configPath: String?

    /// When the process was started.
    private(set) var startTime: Date?

    /// Log file handle for capturing output.
    private var logFileHandle: FileHandle?

    /// Standard install location for mihomo binary.
    static let defaultBinaryPath = "/Library/Application Support/Riptide/mihomo"

    /// Log file path for mihomo output.
    static let logFilePath = "/Library/Application Support/Riptide/logs/mihomo.log"

    // MARK: - Initialization

    init() {
        // Ensure log directory exists
        let logDir = URL(fileURLWithPath: "/Library/Application Support/Riptide/logs")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    // MARK: - Process Management

    /// Checks if mihomo is currently running.
    var isRunning: Bool {
        guard let process = process else { return false }
        return process.isRunning
    }

    /// Launches mihomo with the specified configuration.
    /// - Parameters:
    ///   - configPath: Path to the mihomo config.yaml
    ///   - mode: Launch mode ("systemProxy" or "tun")
    /// - Throws: MihomoLauncherError if launch fails
    func launch(configPath: String, mode: String) async throws {
        guard !isRunning else {
            throw MihomoLauncherError.alreadyRunning
        }

        // Validate config path exists
        let configURL = URL(fileURLWithPath: configPath)
        guard FileManager.default.fileExists(atPath: configPath) else {
            throw MihomoLauncherError.invalidConfigPath
        }

        // Validate binary exists and is executable
        let binaryPath = Self.defaultBinaryPath
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw MihomoLauncherError.invalidExecutable
        }

        // Create and configure process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "-f", configURL.path,
            "-d", configURL.deletingLastPathComponent().path
        ]

        // Set environment for TUN mode if needed
        if mode == "tun" {
            var environment = ProcessInfo.processInfo.environment
            environment["MIHOMO_TUN_MODE"] = "1"
            process.environment = environment
        }

        // Setup log file
        let logURL = URL(fileURLWithPath: Self.logFilePath)
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Create log file if it doesn't exist
        if !FileManager.default.fileExists(atPath: Self.logFilePath) {
            FileManager.default.createFile(atPath: Self.logFilePath, contents: nil)
        }

        // Open log file for writing
        let logHandle = try FileHandle(forWritingTo: logURL)
        logHandle.seekToEndOfFile()
        process.standardOutput = logHandle
        process.standardError = logHandle
        self.logFileHandle = logHandle

        // Set up termination handler
        process.terminationHandler = { [weak self] terminatedProcess in
            Task { [weak self] in
                await self?.handleProcessTermination(terminatedProcess)
            }
        }

        // Launch the process
        do {
            try process.run()
        } catch {
            throw MihomoLauncherError.launchFailed(error.localizedDescription)
        }

        // Store state
        self.process = process
        self.pid = process.processIdentifier
        self.launchMode = mode
        self.configPath = configPath
        self.startTime = Date()

        // Write launch event to log
        let launchMessage = "[RiptideHelper] Mihomo launched at \(Date()) with PID \(process.processIdentifier), mode: \(mode)\n"
        if let data = launchMessage.data(using: .utf8) {
            logHandle.write(data)
        }
    }

    /// Terminates the mihomo process gracefully.
    /// First attempts SIGTERM, then SIGKILL after 5 second timeout.
    /// - Throws: MihomoLauncherError if termination fails
    func terminate() async throws {
        guard let process = process, process.isRunning else {
            throw MihomoLauncherError.notRunning
        }

        guard let pid = pid else {
            throw MihomoLauncherError.notRunning
        }

        // Log termination attempt
        let logHandle = self.logFileHandle
        let termMessage = "[RiptideHelper] Terminating mihomo (PID: \(pid)) at \(Date())\n"
        if let data = termMessage.data(using: .utf8) {
            logHandle?.write(data)
        }

        // First try graceful termination with SIGTERM
        process.terminate()

        // Wait up to 5 seconds for graceful termination
        let timeout: UInt64 = 5_000_000_000  // 5 seconds in nanoseconds
        let startTime = ContinuousClock().now

        while process.isRunning {
            let elapsed = ContinuousClock().now.duration(to: startTime)
            if elapsed >= .nanoseconds(Int64(timeout)) {
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        // If still running, force kill with SIGKILL
        if process.isRunning {
            let killMessage = "[RiptideHelper] Force killing mihomo (PID: \(pid)) after timeout\n"
            if let data = killMessage.data(using: .utf8) {
                logHandle?.write(data)
            }

            kill(pid, SIGKILL)

            // Wait briefly for kill to take effect
            try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        }

        // Clean up state
        if !process.isRunning {
            let exitMessage = "[RiptideHelper] Mihomo terminated at \(Date())\n"
            if let data = exitMessage.data(using: .utf8) {
                logHandle?.write(data)
            }

            self.process = nil
            self.pid = nil
            self.launchMode = nil
            self.configPath = nil
            self.startTime = nil

            logHandle?.closeFile()
            self.logFileHandle = nil
        } else {
            throw MihomoLauncherError.terminationFailed("Process did not terminate after SIGKILL")
        }
    }

    /// Gets the current status of the mihomo process.
    /// - Returns: A tuple containing running status, PID, mode, config path, and start time
    func getStatus() -> (running: Bool, pid: Int?, mode: String?, configPath: String?, startTime: Date?) {
        return (
            running: isRunning,
            pid: pid.map(Int.init),
            mode: launchMode,
            configPath: configPath,
            startTime: startTime
        )
    }

    // MARK: - Private Methods

    /// Handles process termination callback.
    private func handleProcessTermination(_ terminatedProcess: Process) {
        let exitMessage = "[RiptideHelper] Mihomo process terminated with status \(terminatedProcess.terminationStatus) at \(Date())\n"
        if let data = exitMessage.data(using: .utf8) {
            logFileHandle?.write(data)
        }

        // Clean up state if this is the current process
        if terminatedProcess === process {
            process = nil
            pid = nil
            launchMode = nil
            configPath = nil
            startTime = nil
            logFileHandle?.closeFile()
            logFileHandle = nil
        }
    }
}
