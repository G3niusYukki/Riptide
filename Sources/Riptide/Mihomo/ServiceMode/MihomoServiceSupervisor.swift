import Foundation

/// Errors raised by `MihomoServiceSupervisor`.
public enum MihomoServiceSupervisorError: Error, Equatable, Sendable {
    case alreadyRunning
    case notRunning
    case corePathNotAllowed(String)
    case configPathNotAllowed(String)
    case coreSourceNotAllowed(String)
    case launchFailed(String)
    case terminationFailed(String)
    case coreInstallFailed(String)
}

/// Owns the mihomo child process inside the `riptide-mihomo-service` daemon.
///
/// The daemon runs as root, so every requested path is validated by
/// `MihomoServicePathPolicy` before the process is spawned. Lifecycle
/// semantics (`-f config -d dir`, SIGTERM → 5s → SIGKILL, append-to log
/// file, termination-handler state cleanup) mirror Riptide's existing
/// privileged launchers so all three strategies behave identically.
public actor MihomoServiceSupervisor {

    /// Admin-writable root the supervisor installs/executes cores under.
    private let systemRoot: URL

    /// Per-user Riptide directories configs and core sources may come from.
    private let userRoots: [String]

    /// Log file the core's stdout/stderr is appended to.
    private let coreLogURL: URL

    private var process: Process?
    private var startedAt: Date?

    /// - Parameters:
    ///   - systemRoot: admin-writable install root
    ///     (default `/Library/Application Support/Riptide`).
    ///   - userRoots: allowed per-user Riptide roots. Defaults to the current
    ///     user's `~/Library/Application Support/Riptide`; the daemon passes
    ///     the installing user's home instead.
    ///   - coreLogURL: core stdout/stderr log file.
    public init(
        systemRoot: URL = MihomoServicePaths.systemRoot,
        userRoots: [String]? = nil,
        coreLogURL: URL = MihomoServicePaths.coreLogURL
    ) {
        self.systemRoot = systemRoot
        if let userRoots {
            self.userRoots = userRoots
        } else {
            let home = NSHomeDirectory()
            self.userRoots = [home + "/Library/Application Support/Riptide"]
        }
        self.coreLogURL = coreLogURL
    }

    // MARK: - Core lifecycle

    /// Whether a supervised core is currently running.
    public var isRunning: Bool {
        process?.isRunning ?? false
    }

    /// Spawns the core as a root child process.
    /// - Returns: the post-launch status.
    public func start(request: MihomoServiceProtocol.StartRequest) throws -> MihomoServiceProtocol.Status {
        guard !isRunning else {
            throw MihomoServiceSupervisorError.alreadyRunning
        }
        guard MihomoServicePathPolicy.isAllowedCorePath(request.corePath, systemRoot: systemRoot.path) else {
            throw MihomoServiceSupervisorError.corePathNotAllowed(request.corePath)
        }
        guard MihomoServicePathPolicy.isAllowedConfigPath(
            request.configPath,
            systemRoot: systemRoot.path,
            userRoots: userRoots
        ) else {
            throw MihomoServiceSupervisorError.configPathNotAllowed(request.configPath)
        }
        guard FileManager.default.fileExists(atPath: request.configPath) else {
            throw MihomoServiceSupervisorError.configPathNotAllowed("config missing: \(request.configPath)")
        }

        let configURL = URL(fileURLWithPath: request.configPath)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: MihomoServicePathPolicy.normalized(request.corePath))
        child.arguments = [
            "-f", configURL.path,
            "-d", configURL.deletingLastPathComponent().path,
        ]
        if !request.environment.isEmpty {
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in request.environment {
                environment[key] = value
            }
            child.environment = environment
        }

        do {
            try FileManager.default.createDirectory(
                at: coreLogURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: coreLogURL.path) {
                FileManager.default.createFile(atPath: coreLogURL.path, contents: nil)
            }
            let logHandle = try FileHandle(forWritingTo: coreLogURL)
            logHandle.seekToEndOfFile()
            child.standardOutput = logHandle
            child.standardError = logHandle
            let banner = "[riptide-mihomo-service] launching core at \(Date()) config=\(configURL.path)\n"
            logHandle.write(Data(banner.utf8))
            child.terminationHandler = { [weak self] terminated in
                Task { [weak self] in
                    await self?.handleTermination(terminated)
                }
            }
            try child.run()
        } catch {
            throw MihomoServiceSupervisorError.launchFailed(error.localizedDescription)
        }

        process = child
        startedAt = Date()
        return status()
    }

    /// Terminates the core: SIGTERM, wait up to 5s, then SIGKILL.
    /// - Returns: the post-stop (idle) status.
    public func stop() async throws -> MihomoServiceProtocol.Status {
        guard let child = process else {
            throw MihomoServiceSupervisorError.notRunning
        }
        if child.isRunning {
            child.terminate()
            let deadline = ContinuousClock.now + .seconds(5)
            while child.isRunning, ContinuousClock.now < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            if child.isRunning, let pid = pid {
                kill(pid, SIGKILL)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        if child.isRunning {
            throw MihomoServiceSupervisorError.terminationFailed("core did not exit after SIGKILL")
        }
        clearState()
        return status()
    }

    /// Current snapshot of the supervised core.
    public func status() -> MihomoServiceProtocol.Status {
        guard let child = process, child.isRunning else {
            return .idle
        }
        let uptime: Int?
        if let startedAt {
            uptime = max(0, Int(Date().timeIntervalSince(startedAt)))
        } else {
            uptime = nil
        }
        let arguments = child.arguments ?? []
        let configPath = arguments.count > 1 ? arguments[1] : nil
        return MihomoServiceProtocol.Status(
            running: true,
            pid: Int(child.processIdentifier),
            uptimeSeconds: uptime,
            corePath: child.executableURL?.path,
            configPath: configPath
        )
    }

    /// PID of the running core, if any.
    var pid: pid_t? {
        process?.isRunning == true ? process?.processIdentifier : nil
    }

    // MARK: - Core installation

    /// Copies a user-supplied core binary into the system root so it can be
    /// executed as root. Skips the copy when the installed binary is already
    /// byte-identical (unless `force`).
    /// - Returns: the install outcome including the final target path.
    public func installCore(
        request: MihomoServiceProtocol.CoreInstallRequest
    ) throws -> MihomoServiceProtocol.CoreInstallResponse {
        guard MihomoServicePathPolicy.isAllowedCoreSource(
            request.sourcePath,
            systemRoot: systemRoot.path,
            userRoots: userRoots
        ) else {
            throw MihomoServiceSupervisorError.coreSourceNotAllowed(request.sourcePath)
        }
        let sourceURL = URL(fileURLWithPath: MihomoServicePathPolicy.normalized(request.sourcePath))
        let targetURL = systemRoot.appendingPathComponent("mihomo")
        let fileManager = FileManager.default

        guard let sourceData = try? Data(contentsOf: sourceURL) else {
            throw MihomoServiceSupervisorError.coreInstallFailed("unreadable source: \(sourceURL.path)")
        }
        if !request.force,
           let existing = try? Data(contentsOf: targetURL),
           existing == sourceData {
            return MihomoServiceProtocol.CoreInstallResponse(targetPath: targetURL.path, copied: false)
        }

        do {
            try fileManager.createDirectory(at: systemRoot, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try sourceData.write(to: targetURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetURL.path)
        } catch {
            throw MihomoServiceSupervisorError.coreInstallFailed(error.localizedDescription)
        }
        return MihomoServiceProtocol.CoreInstallResponse(targetPath: targetURL.path, copied: true)
    }

    // MARK: - Private

    private func handleTermination(_ terminated: Process) {
        let message = "[riptide-mihomo-service] core exited with status "
            + "\(terminated.terminationStatus) at \(Date())\n"
        if let logHandle = terminated.standardOutput as? FileHandle {
            logHandle.write(Data(message.utf8))
            try? logHandle.close()
        }
        clearState()
    }

    private func clearState() {
        process = nil
        startedAt = nil
    }
}
