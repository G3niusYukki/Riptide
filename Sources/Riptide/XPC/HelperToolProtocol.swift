import Foundation

// MARK: - XPC Protocol

/// XPC protocol for the privileged helper tool that manages mihomo core.
/// This protocol is exposed via NSXPCInterface to allow the main app
/// to communicate with the root-privileged helper.
@objc(HelperToolProtocol)
public protocol HelperToolProtocol {

    /// Launches mihomo with the specified configuration and mode.
    /// - Parameters:
    ///   - configPath: Absolute path to the mihomo config.yaml file
    ///   - mode: Launch mode - "systemProxy" or "tun"
    ///   - reply: Completion handler with optional error
    func launchMihomo(configPath: String, mode: String, reply: @escaping (Error?) -> Void)

    /// Terminates the running mihomo process gracefully.
    /// - Parameter reply: Completion handler with optional error
    func terminateMihomo(reply: @escaping (Error?) -> Void)

    /// Gets the current status of the mihomo process.
    /// - Parameter reply: Completion handler with (statusData, error)
    ///   Status data is JSON-encoded MihomoStatus struct
    func getMihomoStatus(reply: @escaping (Data?, Error?) -> Void)

    /// Installs or updates the mihomo binary to the system location.
    /// - Parameters:
    ///   - binaryPath: Path to the mihomo binary to install
    ///   - reply: Completion handler with optional error
    func installMihomo(binaryPath: String, reply: @escaping (Error?) -> Void)
}

// MARK: - Launch Mode

/// Launch modes for mihomo core.
public enum MihomoLaunchMode: String, Sendable, Codable {
    case systemProxy = "systemProxy"
    case tun = "tun"
}

// MARK: - Status

/// Current status of the mihomo process.
public struct MihomoStatus: Codable, Sendable {
    public let running: Bool
    public let pid: Int?
    public let mode: String?
    public let configPath: String?
    public let startTime: Date?

    public init(
        running: Bool,
        pid: Int? = nil,
        mode: String? = nil,
        configPath: String? = nil,
        startTime: Date? = nil
    ) {
        self.running = running
        self.pid = pid
        self.mode = mode
        self.configPath = configPath
        self.startTime = startTime
    }
}

// MARK: - Error Types

/// Errors that can occur in the helper tool.
public enum HelperToolError: Error, Equatable, Sendable {
    case invalidConfigPath
    case invalidBinaryPath
    case pathNotInWhitelist
    case mihomoAlreadyRunning
    case mihomoNotRunning
    case processLaunchFailed(String)
    case processTerminationFailed(String)
    case installationFailed(String)
    case invalidMode(String)
    case encodingFailed
}

extension HelperToolError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfigPath:
            return "Invalid configuration file path"
        case .invalidBinaryPath:
            return "Invalid binary path"
        case .pathNotInWhitelist:
            return "Path is not in allowed whitelist"
        case .mihomoAlreadyRunning:
            return "Mihomo is already running"
        case .mihomoNotRunning:
            return "Mihomo is not running"
        case .processLaunchFailed(let reason):
            return "Failed to launch process: \(reason)"
        case .processTerminationFailed(let reason):
            return "Failed to terminate process: \(reason)"
        case .installationFailed(let reason):
            return "Installation failed: \(reason)"
        case .invalidMode(let mode):
            return "Invalid launch mode: \(mode)"
        case .encodingFailed:
            return "Failed to encode status data"
        }
    }
}

// MARK: - NSXPC helpers

/// Creates the NSXPCInterface for the helper tool protocol.
public func createHelperToolInterface() -> NSXPCInterface {
    let interface = NSXPCInterface(with: HelperToolProtocol.self)
    return interface
}
