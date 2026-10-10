import Foundation

/// Wire protocol types shared by the `riptide-mihomo-service` root daemon and
/// the app-side `MihomoServiceClient`.
///
/// This mirrors the Clash Verge service architecture: a privileged launchd
/// daemon exposes an HTTP API over a Unix domain socket, and the GUI asks it
/// to start/stop the core instead of elevating on every toggle.
public enum MihomoServiceProtocol {

    /// Protocol version reported by `GET /health`. Bump on breaking changes to
    /// the request/response shapes below.
    public static let version = "1.0.0"

    // MARK: - Requests

    /// Body of `POST /v1/start` — asks the daemon to launch the mihomo core
    /// as root (the payload mirrors Clash Verge's `CoreConfig`).
    public struct StartRequest: Codable, Equatable, Sendable {
        /// Absolute path of the core executable the daemon should run.
        public let corePath: String
        /// Absolute path of the mihomo `config.yaml`.
        public let configPath: String
        /// Extra environment for the core process (e.g. `MIHOMO_TUN_MODE=1`).
        public let environment: [String: String]

        public init(corePath: String, configPath: String, environment: [String: String] = [:]) {
            self.corePath = corePath
            self.configPath = configPath
            self.environment = environment
        }
    }

    /// Body of `POST /v1/core/install` — asks the daemon (running as root) to
    /// copy a user-downloaded core binary into the admin-writable system
    /// location so it can later be executed as root.
    public struct CoreInstallRequest: Codable, Equatable, Sendable {
        /// User-readable source path of the core binary to install.
        public let sourcePath: String
        /// Copy even when the installed binary is byte-identical.
        public let force: Bool

        public init(sourcePath: String, force: Bool = false) {
            self.sourcePath = sourcePath
            self.force = force
        }
    }

    // MARK: - Responses

    /// Response of `GET /health`.
    public struct Health: Codable, Equatable, Sendable {
        public let status: String
        public let version: String

        public init(status: String = "ok", version: String = MihomoServiceProtocol.version) {
            self.status = status
            self.version = version
        }
    }

    /// Response of `GET /v1/status`, `POST /v1/start`, and `POST /v1/stop`.
    public struct Status: Codable, Equatable, Sendable {
        public let running: Bool
        public let pid: Int?
        public let uptimeSeconds: Int?
        public let corePath: String?
        public let configPath: String?

        public init(
            running: Bool,
            pid: Int? = nil,
            uptimeSeconds: Int? = nil,
            corePath: String? = nil,
            configPath: String? = nil
        ) {
            self.running = running
            self.pid = pid
            self.uptimeSeconds = uptimeSeconds
            self.corePath = corePath
            self.configPath = configPath
        }

        /// The canonical "no core running" status.
        public static let idle = Status(running: false)
    }

    /// Response of `POST /v1/core/install`.
    public struct CoreInstallResponse: Codable, Equatable, Sendable {
        /// The system path the core is now installed at.
        public let targetPath: String
        /// True when the daemon actually copied bytes this call (vs. skipping
        /// an identical existing installation).
        public let copied: Bool

        public init(targetPath: String, copied: Bool) {
            self.targetPath = targetPath
            self.copied = copied
        }
    }

    /// Error body used by all non-2xx responses.
    public struct ErrorResponse: Codable, Equatable, Sendable {
        public let error: String

        public init(error: String) {
            self.error = error
        }
    }
}
