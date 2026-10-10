import Foundation

/// Installs and uninstalls the privileged `riptide-mihomo-service` launchd
/// daemon — the Clash Verge service-mode lifecycle, adapted to Riptide's
/// existing `TunDaemonController` install pattern:
///
/// - `install()` copies the daemon binary to the system root, records the
///   installing user's UID in an owner file, writes a LaunchDaemon plist
///   (`RunAtLoad` + `KeepAlive`, so the service survives reboots and
///   crashes), and bootstraps it. This is the only password prompt.
/// - After install, the app talks to the daemon over its Unix socket with no
///   further elevation: core start/stop/status/install are plain IPC calls.
/// - The daemon refuses IPC from any UID other than the recorded owner (or
///   root), so other local users cannot command the root service.
public actor MihomoServiceInstaller {

    public enum InstallerError: Error, Equatable, Sendable {
        case binaryNotFound
        case authorizationCancelled
        case privilegedActionFailed(String)
        case writeFailed(String)
    }

    private let supportDir: URL
    private let launchDaemonsDir: URL
    private let uid: UInt32
    private let fileManager: FileManager

    /// Runs a shell script with administrator privileges (a single password
    /// prompt). Injectable so tests can record the script instead of elevating.
    private let privilegedRunner: @Sendable (_ script: String) async throws -> Void

    private var daemonBinaryPath: URL {
        supportDir.appendingPathComponent("riptide-mihomo-service")
    }

    private var socketPath: URL {
        supportDir.appendingPathComponent("mihomo-service.sock")
    }

    private var ownerFilePath: URL {
        supportDir.appendingPathComponent("mihomo-service.owner")
    }

    private var serviceLogPath: URL {
        supportDir.appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("mihomo-service.log")
    }

    private var plistPath: URL {
        launchDaemonsDir.appendingPathComponent("\(MihomoServicePaths.serviceLabel).plist")
    }

    /// Resolved filesystem paths handed to the privileged script builders.
    struct Layout {
        let supportDir: String
        let logsDir: String
        let daemonBinary: String
        let socket: String
        let ownerFile: String
        let serviceLog: String
        let plist: String
        let label: String
    }

    private var layout: Layout {
        Layout(
            supportDir: supportDir.path,
            logsDir: supportDir.appendingPathComponent("logs", isDirectory: true).path,
            daemonBinary: daemonBinaryPath.path,
            socket: socketPath.path,
            ownerFile: ownerFilePath.path,
            serviceLog: serviceLogPath.path,
            plist: plistPath.path,
            label: MihomoServicePaths.serviceLabel
        )
    }

    public init(
        supportDir: URL = MihomoServicePaths.systemRoot,
        launchDaemonsDir: URL = URL(fileURLWithPath: "/Library/LaunchDaemons"),
        uid: UInt32 = getuid(),
        fileManager: FileManager = .default,
        privilegedRunner: @escaping @Sendable (_ script: String) async throws -> Void
            = TunDaemonController.osascriptAdminRunner
    ) {
        self.supportDir = supportDir
        self.launchDaemonsDir = launchDaemonsDir
        self.uid = uid
        self.fileManager = fileManager
        self.privilegedRunner = privilegedRunner
    }

    /// True when both the LaunchDaemon plist and the installed daemon binary
    /// are present.
    public func isInstalled() -> Bool {
        fileManager.fileExists(atPath: plistPath.path)
            && fileManager.fileExists(atPath: daemonBinaryPath.path)
    }

    /// Installs the daemon. Shows one administrator-password prompt.
    /// - Parameter binarySource: runnable `riptide-mihomo-service` binary
    ///   (e.g. from `MihomoServiceBinaryLocator.locate()`).
    public func install(binarySource: URL) async throws {
        guard fileManager.isExecutableFile(atPath: binarySource.path) else {
            throw InstallerError.binaryNotFound
        }
        let resolved = layout
        let plist = Self.plistXML(
            label: resolved.label,
            binary: resolved.daemonBinary,
            log: resolved.serviceLog
        )
        let script = Self.installScript(
            binarySource: binarySource.path,
            layout: resolved,
            plistXML: plist,
            uid: uid
        )
        do {
            try await privilegedRunner(script)
        } catch let error as TunDaemonController.TunDaemonError {
            throw Self.mapDaemonError(error)
        }
    }

    /// Removes the daemon, plist, owner file, and socket. Shows one prompt.
    /// Stops the supervised core first so TUN routes are torn down cleanly.
    public func uninstall() async throws {
        let script = Self.uninstallScript(layout: layout)
        do {
            try await privilegedRunner(script)
        } catch let error as TunDaemonController.TunDaemonError {
            throw Self.mapDaemonError(error)
        }
    }

    // MARK: - Script assembly

    static func plistXML(label: String, binary: String, log: String) -> String {
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
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
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
        mkdir -p "\(layout.logsDir)"
        cp "\(binarySource)" "\(layout.daemonBinary)"
        chmod 755 "\(layout.daemonBinary)"
        printf '%s' '\(uid)' > "\(layout.ownerFile)"
        chown root:wheel "\(layout.ownerFile)"
        chmod 644 "\(layout.ownerFile)"
        rm -f "\(layout.socket)"
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
        rm -f "\(layout.daemonBinary)"
        rm -f "\(layout.ownerFile)"
        rm -f "\(layout.socket)"
        """
    }

    private static func mapDaemonError(_ error: TunDaemonController.TunDaemonError) -> InstallerError {
        switch error {
        case .authorizationCancelled:
            return .authorizationCancelled
        case .writeFailed(let detail):
            return .writeFailed(detail)
        case .privilegedActionFailed(let detail):
            return .privilegedActionFailed(detail)
        case .binaryNotFound:
            return .binaryNotFound
        case .notInstalled:
            return .privilegedActionFailed("not installed")
        }
    }
}
