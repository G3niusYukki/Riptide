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

#if canImport(NetworkExtension)
import NetworkExtension

public final class VPNTunnelManager: NSObject, VPNTunnelManagerProtocol {
    private var manager: NETunnelProviderManager?
    private var delegate: VPNTunnelDelegate?
    private var packetBuffer: [Data] = []
    private var running = false

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
}

public enum VPNManagerError: Error {
    case notConfigured
}
#else
// Stub for Swift PM builds (NetworkExtension not available)
public final class VPNTunnelManager: VPNTunnelManagerProtocol {
    public var isRunning: Bool { false }

    public init() {}
    public func setDelegate(_: VPNTunnelDelegate) {}
    public func start(configuration: VPNConfiguration) {}
    public func stop() {}
    public func handlePackets(_: [Data]) {}
    public func installConfiguration() async throws {}
    public func connect() async throws {}
    public func disconnect() {}
}
#endif

public protocol VPNTunnelManagerProtocol: AnyObject {}
