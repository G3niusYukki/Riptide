import Foundation

// MARK: - Gateway Enabler

/// Manages macOS system-level configuration required for Gateway / Enhanced Mode:
/// - IP forwarding (`net.inet.ip.forwarding`)
/// - NAT (via `pfctl` packet filter rules)
/// - DHCP (via `bootpd` configuration)
///
/// All operations require root privileges and should be executed through
/// the existing XPC helper (`HelperToolConnection`).
public struct GatewayEnabler: Sendable {

    public struct GatewayConfig: Sendable, Equatable, Codable {
        /// Subnet for LAN clients, e.g. "192.168.2.0/24"
        public var subnet: String
        /// Gateway IP (this Mac) on the subnet, e.g. "192.168.2.1"
        public var gatewayIP: String
        /// DHCP range start, e.g. "192.168.2.100"
        public var dhcpRangeStart: String
        /// DHCP range end, e.g. "192.168.2.200"
        public var dhcpRangeEnd: String
        /// Interface to NAT outbound traffic through, e.g. "en0"
        public var outboundInterface: String
        /// DNS server for DHCP clients (default: this gateway)
        public var dnsServer: String
        /// Whether gateway mode is enabled
        public var enabled: Bool

        public static let `default` = GatewayConfig(
            subnet: "192.168.2.0/24",
            gatewayIP: "192.168.2.1",
            dhcpRangeStart: "192.168.2.100",
            dhcpRangeEnd: "192.168.2.200",
            outboundInterface: "en0",
            dnsServer: "192.168.2.1",
            enabled: false
        )
    }

    public init() {}

    // MARK: - IP Forwarding

    /// Enables or disables IP forwarding (kernel-level packet routing).
    /// Equivalent to: `sudo sysctl net.inet.ip.forwarding=1`
    public func setIPForwarding(enabled: Bool) throws {
        let value = enabled ? "1" : "0"
        try runPrivilegedCommand(
            executable: "/usr/sbin/sysctl",
            arguments: ["-w", "net.inet.ip.forwarding=\(value)"]
        )
    }

    /// Returns the current IP forwarding status.
    public func isIPForwardingEnabled() -> Bool {
        let output = runCommand(
            executable: "/usr/sbin/sysctl",
            arguments: ["-n", "net.inet.ip.forwarding"]
        )
        return output?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    // MARK: - NAT (pfctl)

    /// Enables NAT on the outbound interface for the given subnet.
    /// Writes a temporary pf anchor file and enables it.
    public func enableNAT(config: GatewayConfig) throws {
        let anchorFile = "/tmp/riptide_nat_anchor.conf"
        let rules = """
        nat on \(config.outboundInterface) from \(config.subnet) to any -> (\(config.outboundInterface))
        pass in on bridge100 from \(config.subnet) to any
        pass out on \(config.outboundInterface) from any to any
        """
        try rules.write(toFile: anchorFile, atomically: true, encoding: .utf8)

        // Load pf rules
        try runPrivilegedCommand(
            executable: "/sbin/pfctl",
            arguments: ["-e"]
        )
        try runPrivilegedCommand(
            executable: "/sbin/pfctl",
            arguments: ["-a", "riptide", "-f", anchorFile]
        )
    }

    /// Disables NAT and removes the riptide anchor.
    public func disableNAT() throws {
        try runPrivilegedCommand(
            executable: "/sbin/pfctl",
            arguments: ["-a", "riptide", "-F", "all"]
        )
    }

    // MARK: - DHCP (bootpd)

    /// Configures the macOS built-in DHCP server (`bootpd`) for the subnet.
    /// This requires editing `/etc/bootpd.plist`.
    public func configureDHCP(config: GatewayConfig) throws {
        let plist: [String: Any] = [
            "Subnets": [
                [
                    "name": config.subnet,
                    "net_address": config.subnet,
                    "net_mask": "255.255.255.0",
                    "net_range": [
                        config.dhcpRangeStart,
                        config.dhcpRangeEnd,
                    ],
                    "dhcp_router": config.gatewayIP,
                    "dhcp_domain_name_server": [config.dnsServer],
                ]
            ]
        ]

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        let tempPath = "/tmp/riptide_bootpd.plist"
        try plistData.write(to: URL(fileURLWithPath: tempPath))

        try runPrivilegedCommand(
            executable: "/bin/cp",
            arguments: [tempPath, "/etc/bootpd.plist"]
        )

        // Restart bootpd
        try runPrivilegedCommand(
            executable: "/usr/bin/sudo",
            arguments: ["/bin/launchctl", "unload", "/System/Library/LaunchDaemons/bootps.plist"]
        )
        try runPrivilegedCommand(
            executable: "/usr/bin/sudo",
            arguments: ["/bin/launchctl", "load", "/System/Library/LaunchDaemons/bootps.plist"]
        )
    }

    /// Disables DHCP by unloading bootpd.
    public func disableDHCP() throws {
        try runPrivilegedCommand(
            executable: "/usr/bin/sudo",
            arguments: ["/bin/launchctl", "unload", "/System/Library/LaunchDaemons/bootps.plist"]
        )
    }

    // MARK: - Enable / Disable All

    /// Enables all gateway components in one call.
    public func enableGateway(config: GatewayConfig) throws {
        try setIPForwarding(enabled: true)
        try enableNAT(config: config)
        try configureDHCP(config: config)
    }

    /// Disables all gateway components in one call.
    public func disableGateway() throws {
        try setIPForwarding(enabled: false)
        try disableNAT()
        try disableDHCP()
    }

    /// Returns a list of connected devices from the ARP table.
    public func connectedDevices() -> [ConnectedDevice] {
        let output = runCommand(
            executable: "/usr/sbin/arp",
            arguments: ["-a"]
        ) ?? ""
        return output.split(separator: "\n").compactMap { line in
            let parts = String(line).split(separator: " ").filter { !$0.isEmpty }
            guard parts.count >= 4 else { return nil }
            let ip = String(parts[1]).replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
            let mac = parts.count >= 4 ? String(parts[3]) : "unknown"
            let hostname = parts.count >= 1 ? String(parts[0]) : "unknown"
            return ConnectedDevice(ip: ip, mac: mac, hostname: hostname)
        }
    }

    // MARK: - Private Helpers

    /// Runs a command with root privileges via sudo.
    private func runPrivilegedCommand(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = [executable] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw GatewayError.commandFailed(
                "\(executable) \(arguments.joined(separator: " "))",
                process.terminationStatus
            )
        }
    }

    /// Runs a non-privileged command and returns stdout.
    private func runCommand(executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

// MARK: - Models

public struct ConnectedDevice: Sendable, Identifiable {
    public let id = UUID()
    public let ip: String
    public let mac: String
    public let hostname: String
}

public enum GatewayError: Error, Sendable, LocalizedError {
    case commandFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let status):
            return "命令失败: \(cmd) (exit \(status))"
        }
    }
}
