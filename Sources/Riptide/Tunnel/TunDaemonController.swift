import Foundation

/// Locates the bundled standalone `riptide-singbox` core (the elevated TUN core).
public enum SingBoxBinaryLocator {
    /// Returns the first runnable `riptide-singbox` found, or nil.
    ///
    /// Search order: the app bundle's Resources (shipping), an explicit
    /// `RIPTIDE_SINGBOX_PATH` override (dev/CI), then `Binaries/riptide-singbox`
    /// relative to the current directory (`swift run` from the repo root).
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let url = Bundle.main.url(forResource: "riptide-singbox", withExtension: nil),
           fileManager.isExecutableFile(atPath: url.path) {
            return url
        }
        if let override = environment["RIPTIDE_SINGBOX_PATH"],
           fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let dev = fileManager.currentDirectoryPath + "/Binaries/riptide-singbox"
        if fileManager.isExecutableFile(atPath: dev) {
            return URL(fileURLWithPath: dev)
        }
        return nil
    }
}

/// Manages the privileged launchd daemon that runs `riptide-singbox` as root for
/// macOS TUN mode (creating the utun + modifying the routing table requires root,
/// which an unentitled GUI app cannot do in-process).
///
/// Design — one prompt, then prompt-free toggling:
/// - `install()` copies the core to a root location, writes a LaunchDaemon plist,
///   and bootstraps it. The plist's `KeepAlive.PathState` watches a flag file. This
///   is the only step that shows the admin-password dialog.
/// - `enable()` writes the generated config and **creates the flag file**; launchd
///   sees the path appear and starts the root core — no prompt.
/// - `disable()` **removes the flag file**; launchd's KeepAlive condition fails and
///   it sends the core SIGTERM, so sing-box reverts the routes it added — no prompt.
///
/// The `tun/` working directory is handed to the installing user (mode 0700) so the
/// app can write the config/flag without elevation, while keeping the proxy
/// credentials in the config unreadable by other local users.
public actor TunDaemonController {
    public enum TunDaemonError: Error, Equatable, Sendable {
        case binaryNotFound
        case authorizationCancelled
        case privilegedActionFailed(String)
        case writeFailed(String)
        case notInstalled
    }

    public static let daemonLabel = "com.riptide.tun"

    private let supportDir: URL
    private let tunDir: URL
    private let installedBinaryPath: URL
    private let plistPath: URL
    private let uid: UInt32
    private let fileManager: FileManager

    /// Runs a shell script with administrator privileges (a single password
    /// prompt). Injectable so tests can record the script instead of elevating.
    private let privilegedRunner: @Sendable (_ script: String) async throws -> Void

    private var configPath: URL { tunDir.appendingPathComponent("config.json") }
    private var flagPath: URL { tunDir.appendingPathComponent("enabled") }
    private var logPath: URL { tunDir.appendingPathComponent("singbox.log") }

    /// Resolved filesystem paths handed to the privileged script builders.
    struct Layout {
        let installedBinary: String
        let supportDir: String
        let tunDir: String
        let flag: String
        let config: String
        let log: String
        let plist: String
        let label: String
    }

    private var layout: Layout {
        Layout(
            installedBinary: installedBinaryPath.path,
            supportDir: supportDir.path,
            tunDir: tunDir.path,
            flag: flagPath.path,
            config: configPath.path,
            log: logPath.path,
            plist: plistPath.path,
            label: Self.daemonLabel
        )
    }

    public init(
        supportDir: URL = URL(fileURLWithPath: "/Library/Application Support/Riptide"),
        launchDaemonsDir: URL = URL(fileURLWithPath: "/Library/LaunchDaemons"),
        uid: UInt32 = getuid(),
        fileManager: FileManager = .default,
        privilegedRunner: @escaping @Sendable (_ script: String) async throws -> Void
            = TunDaemonController.osascriptAdminRunner
    ) {
        self.supportDir = supportDir
        self.tunDir = supportDir.appendingPathComponent("tun", isDirectory: true)
        self.installedBinaryPath = supportDir.appendingPathComponent("riptide-singbox")
        self.plistPath = launchDaemonsDir.appendingPathComponent("\(Self.daemonLabel).plist")
        self.uid = uid
        self.fileManager = fileManager
        self.privilegedRunner = privilegedRunner
    }

    /// True when both the LaunchDaemon plist and the installed core are present.
    public func isInstalled() -> Bool {
        fileManager.fileExists(atPath: plistPath.path)
            && fileManager.fileExists(atPath: installedBinaryPath.path)
    }

    /// True when the KeepAlive flag exists (i.e. TUN has been enabled).
    public func isEnabled() -> Bool {
        fileManager.fileExists(atPath: flagPath.path)
    }

    /// Installs the daemon. Shows one administrator-password prompt.
    public func install(binarySource: URL) async throws {
        guard fileManager.isExecutableFile(atPath: binarySource.path) else {
            throw TunDaemonError.binaryNotFound
        }
        let resolved = layout
        let plist = Self.plistXML(
            label: resolved.label,
            binary: resolved.installedBinary,
            config: resolved.config,
            flag: resolved.flag,
            log: resolved.log
        )
        let script = Self.installScript(
            binarySource: binarySource.path,
            layout: resolved,
            plistXML: plist,
            uid: uid
        )
        try await privilegedRunner(script)
    }

    /// Writes the config and creates the flag so launchd starts the root core.
    /// No prompt. Requires `install()` to have run.
    public func enable(configJSON: String) throws {
        guard isInstalled() else { throw TunDaemonError.notInstalled }
        try? fileManager.createDirectory(at: tunDir, withIntermediateDirectories: true)
        do {
            try Data(configJSON.utf8).write(to: configPath, options: .atomic)
            fileManager.createFile(atPath: flagPath.path, contents: Data())
        } catch {
            throw TunDaemonError.writeFailed(String(describing: error))
        }
    }

    /// Removes the flag so launchd SIGTERMs the core (clean route teardown). No prompt.
    public func disable() throws {
        try? fileManager.removeItem(at: flagPath)
    }

    /// Removes the daemon, plist, and working directory. Shows one prompt.
    public func uninstall() async throws {
        try await privilegedRunner(Self.uninstallScript(layout: layout))
    }

    // MARK: - Script assembly

    static func plistXML(label: String, binary: String, config: String, flag: String, log: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(binary)</string>
                <string>-c</string>
                <string>\(config)</string>
            </array>
            <key>KeepAlive</key>
            <dict>
                <key>PathState</key>
                <dict>
                    <key>\(flag)</key>
                    <true/>
                </dict>
            </dict>
            <key>RunAtLoad</key>
            <false/>
            <key>StandardOutPath</key>
            <string>\(log)</string>
            <key>StandardErrorPath</key>
            <string>\(log)</string>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """
    }

    static func installScript(binarySource: String, layout: Layout, plistXML: String, uid: UInt32) -> String {
        """
        set -e
        mkdir -p "\(layout.supportDir)"
        cp "\(binarySource)" "\(layout.installedBinary)"
        chmod 755 "\(layout.installedBinary)"
        mkdir -p "\(layout.tunDir)"
        chown \(uid) "\(layout.tunDir)"
        chmod 700 "\(layout.tunDir)"
        rm -f "\(layout.flag)"
        cat > "\(layout.plist)" <<'RIPTIDE_PLIST_EOF'
        \(plistXML)
        RIPTIDE_PLIST_EOF
        chown root:wheel "\(layout.plist)"
        chmod 644 "\(layout.plist)"
        launchctl bootout system "\(layout.plist)" 2>/dev/null || true
        launchctl bootstrap system "\(layout.plist)"
        launchctl enable system/\(layout.label)
        """
    }

    static func uninstallScript(layout: Layout) -> String {
        """
        launchctl bootout system/\(layout.label) 2>/dev/null || true
        launchctl bootout system "\(layout.plist)" 2>/dev/null || true
        rm -f "\(layout.plist)"
        rm -f "\(layout.installedBinary)"
        rm -rf "\(layout.tunDir)"
        """
    }

    // MARK: - Production privileged runner

    /// Runs `script` as root via a single `osascript … with administrator
    /// privileges` prompt. The script is written to a user-owned temp file
    /// (mode 0700) and executed as `/bin/sh <file>`, which sidesteps AppleScript
    /// quoting of multi-line shell.
    public static let osascriptAdminRunner: @Sendable (_ script: String) async throws -> Void = { script in
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("riptide-tun-\(UUID().uuidString).sh")
        do {
            try Data(script.utf8).write(to: tmp, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tmp.path)
        } catch {
            throw TunDaemonError.writeFailed(String(describing: error))
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let appleScript = "do shell script \"/bin/sh \" & quoted form of \"\(tmp.path)\" "
            + "with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", appleScript]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            proc.terminationHandler = { finished in
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                if finished.terminationStatus == 0 {
                    cont.resume()
                } else if errStr.contains("-128") || errStr.lowercased().contains("cancel") {
                    cont.resume(throwing: TunDaemonError.authorizationCancelled)
                } else {
                    cont.resume(throwing: TunDaemonError.privilegedActionFailed(
                        errStr.isEmpty ? "osascript exit \(finished.terminationStatus)" : errStr
                    ))
                }
            }
            do {
                try proc.run()
            } catch {
                cont.resume(throwing: TunDaemonError.privilegedActionFailed(error.localizedDescription))
            }
        }
    }
}
