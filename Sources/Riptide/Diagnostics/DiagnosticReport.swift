import Foundation

// MARK: - Diagnostic Report

/// A structured diagnostic report capturing all runtime state for debugging.
/// Designed to be serialized as JSON for export/sharing when users report issues.
public struct DiagnosticReport: Sendable, Codable {
    /// When the report was generated.
    public let timestamp: Date
    /// Riptide version (from bundle if available).
    public let riptideVersion: String
    /// Current runtime mode (systemProxy / tun).
    public let mode: String
    /// Whether the mihomo sidecar is currently running.
    public let mihomoRunning: Bool
    /// Mihomo binary version string.
    public let mihomoVersion: String?
    /// Current VPN connection status.
    public let vpnStatus: String?
    /// System proxy settings state.
    public let systemProxy: SystemProxyReport?
    /// DNS configuration in use.
    public let dnsConfig: DNSReport?
    /// Recent errors (last 20, newest first).
    public let recentErrors: [DiagnosticErrorEntry]
    /// Active connection count.
    public let activeConnections: Int
    /// Total bytes transferred (up/down).
    public let totalTraffic: TrafficReport
    /// Runtime uptime since mihomo started.
    public let uptimeSeconds: TimeInterval?
    /// Helper tool installation status.
    public let helperInstalled: Bool
    /// Tun device name (if TUN mode).
    public let tunDeviceName: String?

    public struct SystemProxyReport: Sendable, Codable {
        public let enabled: Bool
        public let httpPort: Int
        public let socksPort: Int?
        public let guarded: Bool
    }

    public struct DNSReport: Sendable, Codable {
        public let mode: String
        public let fakeIPCIDR: String?
        public let remoteServers: [String]
        public let doHEndpoints: [String]
        public let cacheEnabled: Bool
    }

    public struct TrafficReport: Sendable, Codable {
        public let bytesUp: UInt64
        public let bytesDown: UInt64
    }

    public struct DiagnosticErrorEntry: Sendable, Codable {
        public let code: String
        public let message: String
        public let timestamp: Date
    }
}

// MARK: - Diagnostic Collector

/// Collects runtime state from all components to produce a DiagnosticReport.
/// This is a non-actor value type that the ModeCoordinator populates with
/// data gathered from its managed subcomponents.
public struct DiagnosticCollector: Sendable {
    private let riptideVersion: String
    private let tunDeviceName: String

    public init(riptideVersion: String = "0.0.0", tunDeviceName: String = "utun120") {
        self.riptideVersion = riptideVersion
        self.tunDeviceName = tunDeviceName
    }

    /// Build a diagnostic report from the provided component snapshots.
    public func buildReport(
        mode: RuntimeMode,
        mihomoRunning: Bool,
        mihomoVersion: String?,
        vpnStatus: String?,
        systemProxy: DiagnosticReport.SystemProxyReport?,
        dnsConfig: DiagnosticReport.DNSReport?,
        recentErrors: [DiagnosticReport.DiagnosticErrorEntry],
        activeConnections: Int,
        bytesUp: UInt64,
        bytesDown: UInt64,
        uptimeSeconds: TimeInterval?,
        helperInstalled: Bool
    ) -> DiagnosticReport {
        DiagnosticReport(
            timestamp: Date(),
            riptideVersion: riptideVersion,
            mode: mode.rawValue,
            mihomoRunning: mihomoRunning,
            mihomoVersion: mihomoVersion,
            vpnStatus: vpnStatus,
            systemProxy: systemProxy,
            dnsConfig: dnsConfig,
            recentErrors: recentErrors.suffix(20),
            activeConnections: activeConnections,
            totalTraffic: DiagnosticReport.TrafficReport(
                bytesUp: bytesUp,
                bytesDown: bytesDown
            ),
            uptimeSeconds: uptimeSeconds,
            helperInstalled: helperInstalled,
            tunDeviceName: mode == .tun ? tunDeviceName : nil
        )
    }
}
