import Foundation
import Network

public enum VPNAddressType: Sendable {
    case ipv4
    case ipv6
}

public struct VPNConfiguration: Sendable {
    public let tunnelAddress: String
    public let tunnelSubnetMask: String
    public let tunnelRemoteAddress: String
    public let dnsServers: [String]
    public let includedRoutes: [String]
    public let excludedRoutes: [String]
    public let mtu: Int

    public init(
        tunnelAddress: String = "198.18.0.1",
        tunnelSubnetMask: String = "255.255.0.0",
        tunnelRemoteAddress: String = "127.0.0.1",
        dnsServers: [String] = ["198.18.0.1"],
        includedRoutes: [String] = ["0.0.0.0/0"],
        excludedRoutes: [String] = ["192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12", "127.0.0.0/8"],
        mtu: Int = 9000
    ) {
        self.tunnelAddress = tunnelAddress
        self.tunnelSubnetMask = tunnelSubnetMask
        self.tunnelRemoteAddress = tunnelRemoteAddress
        self.dnsServers = dnsServers
        self.includedRoutes = includedRoutes
        self.excludedRoutes = excludedRoutes
        self.mtu = mtu
    }
}

public protocol VPNTunnelDelegate: AnyObject, Sendable {
    func tunnelDidStart(configuration: VPNConfiguration)
    func tunnelDidStop(reason: String)
    func tunnelDidReceivePackets(_ packets: [Data])
    func tunnelDidEncounterError(_ error: Error)
}

public protocol VPNTunnelManagerProtocol: AnyObject {}

#if canImport(NetworkExtension)
import NetworkExtension

public final class VPNTunnelManager: NSObject, VPNTunnelManagerProtocol {
    private var manager: NETunnelProviderManager?
    private var delegate: VPNTunnelDelegate?
    private var packetBuffer: [Data] = []
    private var running = false

    /// The TUN routing engine for processing IP packets.
    /// Set this before calling `start()` to enable packet routing.
    public var routingEngine: TUNRoutingEngine?

    public override init() {
        super.init()
    }

    /// Whether the VPN tunnel is currently running.
    public var isRunning: Bool { running }

    /// Start the VPN tunnel with the given configuration.
    public func start(configuration: VPNConfiguration) {
        running = true
        delegate?.tunnelDidStart(configuration: configuration)
    }

    /// Stop the VPN tunnel.
    public func stop() {
        running = false
        Task { [routingEngine] in
            await routingEngine?.shutdown()
        }
        delegate?.tunnelDidStop(reason: "stopped by user")
    }

    /// Handle packets received from the tunnel interface.
    public func handlePackets(_ packets: [Data]) {
        packetBuffer.append(contentsOf: packets)
        delegate?.tunnelDidReceivePackets(packets)
    }

    public func setDelegate(_ delegate: VPNTunnelDelegate) {
        self.delegate = delegate
    }

    public func installConfiguration() async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let existing = managers.first {
            manager = existing
            return
        }
        let newManager = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "com.riptide.tunnel"
        proto.serverAddress = "Riptide"
        newManager.protocolConfiguration = proto
        newManager.localizedDescription = "Riptide"
        newManager.isEnabled = true
        try await newManager.saveToPreferences()
        try await newManager.loadFromPreferences()
        manager = newManager
    }

    public func connect() async throws {
        guard let manager = manager else {
            throw VPNManagerError.notConfigured
        }
        try manager.connection.startVPNTunnel()
    }

    public func disconnect() {
        manager?.connection.stopVPNTunnel()
    }

    // ============================================================
    // MARK: - Tunnel Network Settings
    // ============================================================

    /// Configure the TUN interface with routing settings.
    ///
    /// **Architecture note:** `setTunnelNetworkSettings` is only available on
    /// `NEPacketTunnelProvider` (the tunnel extension side), not on
    /// `NETunnelProviderSession` (the host app side). The host app communicates
    /// tunnel settings to the provider via `sendProviderMessage`.
    ///
    /// In a typical `NEPacketTunnelProvider` subclass, apply settings from
    /// `startTunnelWithOptions(completionHandler:)` by calling:
    /// ```swift
    /// self.setTunnelNetworkSettings(settings) { error in
    ///     if let error = error { completionHandler(error) }
    ///     else { completionHandler(nil) }
    /// }
    /// ```
    ///
    /// This method on `VPNTunnelManager` sends the settings to the tunnel
    /// provider over the IPC channel for the provider to apply them.
    public func configureTunnelNetworkSettings(
        tunnelAddress: String = "198.18.0.1",
        tunnelNetmask: String = "255.255.0.0",
        mtu: Int = 1500,
        excludedRoutes: [String] = ["192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12", "127.0.0.0/8"],
        dnsServers: [String] = ["198.18.0.1"],
        matchDomains: [String] = [""]
    ) async throws {
        guard let manager = manager,
              let session = manager.connection as? NETunnelProviderSession else {
            throw VPNManagerError.notConfigured
        }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: tunnelAddress)

        // IPv4 settings
        let ipv4Settings = NEIPv4Settings(
            addresses: [tunnelAddress],
            subnetMasks: [tunnelNetmask]
        )
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        ipv4Settings.excludedRoutes = excludedRoutes.map { cidr in
            let parts = cidr.split(separator: "/")
            let addr = String(parts[0])
            let maskBits = parts.count > 1 ? Int(parts[1]) ?? 32 : 32
            let mask = maskBitsToMask(maskBits)
            return NEIPv4Route(destinationAddress: addr, subnetMask: mask)
        }
        settings.ipv4Settings = ipv4Settings

        // DNS settings
        let dnsSettings = NEDNSSettings(servers: dnsServers)
        dnsSettings.matchDomains = matchDomains
        settings.dnsSettings = dnsSettings

        // MTU
        settings.mtu = NSNumber(value: mtu)

        // Send settings to the tunnel provider via IPC.
        // The tunnel provider (PacketTunnelProvider) receives this message
        // and calls its own setTunnelNetworkSettings to apply them.
        let encoder = JSONEncoder()
        let settingsData = try encoder.encode(TunnelSettingsPayload(
            tunnelAddress: tunnelAddress,
            tunnelNetmask: tunnelNetmask,
            mtu: mtu,
            excludedRoutes: excludedRoutes,
            dnsServers: dnsServers,
            matchDomains: matchDomains
        ))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try session.sendProviderMessage(settingsData) { responseData in
                    if let data = responseData,
                       let response = try? JSONDecoder().decode(TunnelSettingsResponse.self, from: data),
                       let errorMessage = response.error {
                        continuation.resume(throwing: VPNManagerError.settingsFailed(errorMessage))
                    } else {
                        continuation.resume()
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Convert CIDR prefix length to dotted-decimal subnet mask.
    private func maskBitsToMask(_ bits: Int) -> String {
        var mask: UInt32 = 0
        for i in 0..<32 {
            if i < bits {
                mask |= (1 << (31 - i))
            }
        }
        return "\((mask >> 24) & 0xFF).\((mask >> 16) & 0xFF).\((mask >> 8) & 0xFF).\(mask & 0xFF)"
    }

    // ============================================================
    // MARK: - Packet Flow
    // ============================================================

    /// Start reading packets from the TUN interface and processing them through the routing engine.
    /// Call this after the tunnel connection is established and network settings are configured.
    ///
    /// This sends a message to the tunnel provider (PacketTunnelProvider) to start its
    /// packet flow loop. The provider reads from its `packetFlow`, processes packets
    /// through the TUNRoutingEngine, and writes responses back to the TUN interface.
    public func startPacketFlow() {
        guard let manager = manager,
              let session = manager.connection as? NETunnelProviderSession else { return }

        let command = TunnelProviderCommandMessage(
            type: .startPacketFlow,
            settingsPayload: nil
        )

        guard let data = try? JSONEncoder().encode(command) else { return }

        do {
            try session.sendProviderMessage(data) { _ in }
        } catch {
            _ = error
        }
    }
}

public enum VPNManagerError: Error, Sendable {
    case notConfigured
    case settingsFailed(String)
}

// ============================================================
// MARK: - IPC Types for Tunnel Control
// ============================================================

private enum TunnelProviderCommandType: String, Codable, Sendable {
    case configureTunnel
    case startPacketFlow
    case snapshot
}

private struct TunnelProviderCommandMessage: Codable, Sendable {
    let type: TunnelProviderCommandType
    let settingsPayload: TunnelSettingsPayload?
}

/// Payload sent from the host app to the tunnel provider via sendProviderMessage.
private struct TunnelSettingsPayload: Codable, Sendable {
    let tunnelAddress: String
    let tunnelNetmask: String
    let mtu: Int
    let excludedRoutes: [String]
    let dnsServers: [String]
    let matchDomains: [String]
}

/// Response from the tunnel provider after applying settings.
private struct TunnelSettingsResponse: Codable, Sendable {
    let error: String?
}
#else
// Stub for Swift PM builds (NetworkExtension not available)
public final class VPNTunnelManager: VPNTunnelManagerProtocol {
    public var isRunning: Bool { false }

    /// The TUN routing engine for processing IP packets.
    public var routingEngine: TUNRoutingEngine?

    public init() {}
    public func setDelegate(_: VPNTunnelDelegate) {}
    public func start(configuration: VPNConfiguration) {}
    public func stop() {}
    public func handlePackets(_: [Data]) {}
    public func installConfiguration() async throws {}
    public func connect() async throws {}
    public func disconnect() {}
    public func configureTunnelNetworkSettings(
        tunnelAddress: String = "198.18.0.1",
        tunnelNetmask: String = "255.255.0.0",
        mtu: Int = 1500,
        excludedRoutes: [String] = ["192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12", "127.0.0.0/8"],
        dnsServers: [String] = ["198.18.0.1"],
        matchDomains: [String] = [""]
    ) async throws {}
    public func startPacketFlow() {}
}
#endif
