import Foundation

// MARK: - LaunchAgentManager

/// Manages the per-user LaunchAgent that runs Riptide at user login.
///
/// The actor writes a property list into `~/Library/LaunchAgents/` and instructs
/// `launchctl` to load or unload it. All filesystem and process operations run
/// off the main actor so SwiftUI callers never block while waiting for the
/// privileged helper or `launchctl` to respond.
///
/// The actor is fully driven by dependency injection:
/// - `fileManager` controls all filesystem access (default: `.default`).
/// - `launchAgentsDirectory` is the directory that will contain the plist.
/// - `launchctlPath` and `processRunner` are used to invoke `launchctl`; the
///   default runner uses `Process` on a detached task, while tests can pass a
///   closure that records calls and returns synthetic output.
public actor LaunchAgentManager {

    // MARK: - Public Types

    /// Captured output from a single `launchctl` invocation.
    public struct ProcessOutput: Sendable, Equatable {
        public let terminationStatus: Int32
        public let stdout: String
        public let stderr: String

        public init(terminationStatus: Int32, stdout: String = "", stderr: String = "") {
            self.terminationStatus = terminationStatus
            self.stdout = stdout
            self.stderr = stderr
        }
    }

    /// Closure that runs an external command and returns its output.
    /// `executable` is the absolute path to the binary; `arguments` are passed as-is.
    public typealias ProcessRunner = @Sendable (String, [String]) async throws -> ProcessOutput

    // MARK: - Properties

    private let fileManager: FileManager
    private let plistLabel: String
    private let executablePath: String
    private let launchAgentsDirectory: URL
    private let launchctlPath: String
    private let processRunner: ProcessRunner

    /// Shared singleton using the production configuration.
    public static let shared = LaunchAgentManager()

    // MARK: - Initialization

    public init(
        fileManager: FileManager = .default,
        plistLabel: String = "com.riptide.app",
        executablePath: String = "/Applications/RiptideApp.app/Contents/MacOS/Riptide",
        launchAgentsDirectory: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true),
        launchctlPath: String = "/bin/launchctl",
        processRunner: ProcessRunner? = nil
    ) {
        self.fileManager = fileManager
        self.plistLabel = plistLabel
        self.executablePath = executablePath
        self.launchAgentsDirectory = launchAgentsDirectory
        self.launchctlPath = launchctlPath
        self.processRunner = processRunner ?? LaunchAgentManager.defaultProcessRunner
    }

    // MARK: - Public API

    /// Path to the LaunchAgent plist managed by this actor.
    public var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(plistLabel).plist")
    }

    /// Returns `true` if the LaunchAgent plist currently exists on disk.
    public func isRegistered() async -> Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    /// Registers the LaunchAgent: writes the plist (if needed) and tells
    /// `launchctl` to load it.
    ///
    /// - Throws: `RiptideError.launchAgentRegistrationFailed` for any
    ///   filesystem or process failure.
    public func register() async throws {
        // 1. Make sure the LaunchAgents directory exists.
        try ensureLaunchAgentsDirectory()

        // 2. Build the plist content.
        let plistDict: [String: Any] = [
            "Label": plistLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive"
        ]

        let data: Data
        do {
            data = try PropertyListSerialization.data(
                fromPropertyList: plistDict,
                format: .xml,
                options: 0
            )
        } catch {
            throw RiptideError.launchAgentRegistrationFailed(
                "Failed to serialize plist: \(error.localizedDescription)"
            )
        }

        // 3. Write the plist only if it doesn't already exist (idempotent).
        if !fileManager.fileExists(atPath: plistURL.path) {
            do {
                try data.write(to: plistURL, options: .atomic)
            } catch {
                throw RiptideError.launchAgentRegistrationFailed(
                    "Failed to write plist at \(plistURL.path): \(error.localizedDescription)"
                )
            }
        }

        // 4. Ask launchctl to load the plist (so it starts at the next login
        //    and, because of `-w`, becomes registered persistently).
        try await invokeLaunchctl(arguments: ["load", "-w", plistURL.path])
    }

    /// Unregisters the LaunchAgent: tells `launchctl` to unload the plist,
    /// then deletes the plist file from disk.
    ///
    /// Failures from `launchctl unload` are tolerated because the file is
    /// still removed from disk. A no-op when the plist does not exist.
    ///
    /// - Throws: `RiptideError.launchAgentRegistrationFailed` only when the
    ///   plist file exists and cannot be deleted.
    public func unregister() async throws {
        let plistExists = fileManager.fileExists(atPath: plistURL.path)
        guard plistExists else {
            return
        }

        // launchctl unload failures are non-fatal — the plist still gets
        // deleted so subsequent loads cannot re-trigger an old registration.
        do {
            _ = try await processRunner(launchctlPath, ["unload", plistURL.path])
        } catch {
            // Swallow: we still want to delete the plist from disk.
        }

        do {
            try fileManager.removeItem(at: plistURL)
        } catch {
            throw RiptideError.launchAgentRegistrationFailed(
                "Failed to delete plist at \(plistURL.path): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Private Helpers

    private func ensureLaunchAgentsDirectory() throws {
        if fileManager.fileExists(atPath: launchAgentsDirectory.path) {
            return
        }
        do {
            try fileManager.createDirectory(
                at: launchAgentsDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw RiptideError.launchAgentRegistrationFailed(
                "Failed to create LaunchAgents directory at \(launchAgentsDirectory.path): \(error.localizedDescription)"
            )
        }
    }

    private func invokeLaunchctl(arguments: [String]) async throws {
        let result: ProcessOutput
        do {
            result = try await processRunner(launchctlPath, arguments)
        } catch {
            throw RiptideError.launchAgentRegistrationFailed(
                "launchctl \(arguments.first ?? "") failed: \(error.localizedDescription)"
            )
        }
        if result.terminationStatus != 0 {
            throw RiptideError.launchAgentRegistrationFailed(
                "launchctl \(arguments.first ?? "") exited with status \(result.terminationStatus): \(result.stderr)"
            )
        }
    }

    /// Default `ProcessRunner` implementation: spawns `Process` on a detached
    /// task so the call doesn't block the main actor.
    private static let defaultProcessRunner: ProcessRunner = { path, arguments in
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            return ProcessOutput(
                terminationStatus: process.terminationStatus,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
        }.value
    }
}
