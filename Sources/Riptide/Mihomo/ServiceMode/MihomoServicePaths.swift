import Foundation

/// Filesystem layout for the mihomo service mode (the privileged
/// `riptide-mihomo-service` launchd daemon), mirroring Clash Verge's
/// `/Library/PrivilegedHelperTools` + `/tmp/verge/verge-mihomo.sock` layout
/// but rooted under Riptide's system support directory.
public enum MihomoServicePaths {

    /// launchd label of the privileged daemon.
    public static let serviceLabel = "com.riptide.mihomo.service"

    /// Default system support root: `/Library/Application Support/Riptide`.
    public static var systemRoot: URL {
        URL(fileURLWithPath: "/Library/Application Support/Riptide", isDirectory: true)
    }

    /// Installed daemon executable: `<root>/riptide-mihomo-service`.
    public static var daemonExecutable: URL {
        systemRoot.appendingPathComponent("riptide-mihomo-service")
    }

    /// IPC socket: `<root>/mihomo-service.sock`.
    public static var socketURL: URL {
        systemRoot.appendingPathComponent("mihomo-service.sock")
    }

    /// Convenience string form of `socketURL.path`.
    public static var socketPath: String { socketURL.path }

    /// System-wide core binary the daemon executes as root:
    /// `<root>/mihomo` (same location the XPC helper and the sudo fallback
    /// already use, so all three launch strategies converge on one binary).
    public static var systemCoreExecutable: URL {
        systemRoot.appendingPathComponent("mihomo")
    }

    /// Daemon's own log: `<root>/logs/mihomo-service.log`.
    public static var serviceLogURL: URL {
        systemRoot.appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("mihomo-service.log")
    }

    /// Core stdout/stderr log: `<root>/logs/mihomo.log`.
    public static var coreLogURL: URL {
        systemRoot.appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("mihomo.log")
    }

    /// Owner file written at install time: `<root>/mihomo-service.owner`
    /// contains the installing user's UID. The daemon only accepts IPC
    /// connections from that UID (or root), which prevents any other local
    /// user from commanding the root service.
    public static var ownerFileURL: URL {
        systemRoot.appendingPathComponent("mihomo-service.owner")
    }

    /// LaunchDaemon plist:
    /// `/Library/LaunchDaemons/com.riptide.mihomo.service.plist`.
    public static var launchDaemonPlistURL: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons/\(serviceLabel).plist")
    }
}

/// Locates a runnable `riptide-mihomo-service` binary to install.
///
/// Search order: the app bundle's Resources (shipping), an explicit
/// `RIPTIDE_MIHOMO_SERVICE_PATH` override (dev/CI), then `Binaries/` and
/// `.build/debug` relative to the current directory (`swift run` / script
/// installs from the repo root).
public enum MihomoServiceBinaryLocator {

    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let url = Bundle.main.url(forResource: "riptide-mihomo-service", withExtension: nil),
           fileManager.isExecutableFile(atPath: url.path) {
            return url
        }
        if let override = environment["RIPTIDE_MIHOMO_SERVICE_PATH"],
           fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let candidates = [
            fileManager.currentDirectoryPath + "/Binaries/riptide-mihomo-service",
            fileManager.currentDirectoryPath + "/.build/debug/riptide-mihomo-service",
            fileManager.currentDirectoryPath + "/.build/release/riptide-mihomo-service",
        ]
        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }
}
