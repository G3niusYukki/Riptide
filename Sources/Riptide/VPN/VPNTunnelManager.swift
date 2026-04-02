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

public final class VPNTunnelManager: @unchecked Sendable {
    private var delegate: VPNTunnelDelegate?
    private var running: Bool = false
    private var packetBuffer: [Data] = []

    public init() {}

    public func setDelegate(_ delegate: VPNTunnelDelegate) {
        self.delegate = delegate
    }

    public func start(configuration: VPNConfiguration) {
        running = true
        delegate?.tunnelDidStart(configuration: configuration)
    }

    public func stop(reason: String = "user initiated") {
        running = false
        delegate?.tunnelDidStop(reason: reason)
    }

    public func handlePackets(_ packets: [Data]) {
        guard running else { return }
        packetBuffer.append(contentsOf: packets)
        delegate?.tunnelDidReceivePackets(packets)
    }

    public func writePackets(_ packets: [Data]) {
        packetBuffer.removeAll()
    }

    public var isRunning: Bool { running }
}
