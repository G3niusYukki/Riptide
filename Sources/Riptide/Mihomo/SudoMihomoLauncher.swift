import Foundation

/// Launches and manages a mihomo process using `/usr/bin/sudo` for root privileges.
///
/// This is a fallback for when the SMJobBless helper tool is not installed.
/// macOS will show a standard authentication dialog when sudo is invoked.
///
/// Trade-offs vs SMJobBless:
/// - No Apple Developer certificate required
/// - Shows password prompt each launch (cached 5-15 min by sudo)
/// - Process is child of sudo, not launchd (won't survive restart)
/// - Suitable for development, testing, and personal use
public actor SudoMihomoLauncher {

    /// Errors specific to sudo-based mihomo launching.
    public enum SudoLaunchError: Error, Equatable, Sendable {
        case alreadyRunning
        case notRunning
        case binaryNotFound(String)
        case launchFailed(String)
        case terminationFailed(String)
    }

    /// The running sudo process, if any.
    private var process: Process?

    /// Whether mihomo is currently running.
    public var isRunning: Bool {
        guard let process else { return false }
        return process.isRunning
    }

    /// PID of the running mihomo process (the child of sudo).
    public var pid: pid_t? {
        process?.processIdentifier
    }

    public init() {}

    /// Launches mihomo with sudo privileges.
    /// - Parameters:
    ///   - binaryPath: Absolute path to the mihomo binary.
    ///   - configPath: Absolute path to the config.yaml file.
    /// - Throws: `SudoLaunchError` if launch fails.
    public func launch(binaryPath: String, configPath: String) async throws {
        guard !isRunning else {
            throw SudoLaunchError.alreadyRunning
        }

        // Verify binary exists
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw SudoLaunchError.binaryNotFound(binaryPath)
        }

        let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent().path

        // Ensure log directory and file exist
        let logDir = "/Library/Application Support/Riptide/logs"
        let logPath = "\(logDir)/mihomo.log"
        try? FileManager.default.createDirectory(
            atPath: logDir,
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = [
            binaryPath,
            "-f", configPath,
            "-d", configDir
        ]

        // Redirect output to log file
        if let logHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logPath)) {
            logHandle.seekToEndOfFile()
            proc.standardOutput = logHandle
            proc.standardError = logHandle
        }

        // Set termination handler
        proc.terminationHandler = { [weak self] _ in
            Task { [weak self] in
                await self?.handleTermination()
            }
        }

        do {
            try proc.run()
            self.process = proc
        } catch {
            throw SudoLaunchError.launchFailed(error.localizedDescription)
        }
    }

    /// Terminates the running mihomo process.
    /// Sends SIGTERM first, then SIGKILL after 5 seconds if still running.
    public func terminate() async throws {
        guard let proc = process else {
            throw SudoLaunchError.notRunning
        }

        guard proc.isRunning else {
            self.process = nil
            return
        }

        // SIGTERM first
        proc.terminate()

        // Wait up to 5 seconds
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !proc.isRunning { break }
        }

        // SIGKILL if still running
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        if proc.isRunning {
            throw SudoLaunchError.terminationFailed("Process still running after SIGKILL")
        }

        self.process = nil
    }

    private func handleTermination() {
        // Process exited — clear reference
        self.process = nil
    }
}
