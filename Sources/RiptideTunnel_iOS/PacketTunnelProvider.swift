import NetworkExtension
import RiptideCore

/// iOS Packet Tunnel Provider — runs the TUN interface and proxy engine
/// inside the NetworkExtension process.
///
/// Key differences from macOS:
/// - No XPC helper: the NE process IS the privileged tunnel context.
/// - Communicates with the host app via `NETunnelProviderSession` +
///   `TunnelProviderMessages` (shared with macOS via RiptideCore).
/// - Simpler lifecycle: `startTunnel` / `stopTunnel` with
///   `completionHandler` callbacks.
open class PacketTunnelProvider: NEPacketTunnelProvider {

    // MARK: - Properties

    private var proxyEngine: ProxyEngine?
    private var tunnelMonitor: NWPathMonitor?

    // MARK: - Tunnel Lifecycle

    open override func startTunnel(options: [String: NSObject]? = nil) async throws {
        // 1. Read tunnel configuration from protocolConfiguration
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfig = proto.providerConfiguration else {
            throw TunnelError.missingConfiguration
        }

        // 2. Parse the profile from provider config
        let profileData: Data
        if let raw = providerConfig["profile"] as? Data {
            profileData = raw
        } else if let jsonStr = providerConfig["profile"] as? String,
                  let data = jsonStr.data(using: .utf8) {
            profileData = data
        } else {
            throw TunnelError.missingConfiguration
        }

        // 3. Parse TUN settings
        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(
            tunnelRemoteAddress: providerConfig["tunnelAddress"] as? String ?? "10.0.0.1"
        )

        let dnsSettings = NENetworkRule.DNSSettings(
            servers: providerConfig["dnsServers"] as? [String] ?? ["1.1.1.1", "8.8.8.8"]
        )
        dnsSettings.matchDomains = [""] // match all

        let ipv4 = NEIPv4Settings(
            addresses: [providerConfig["ipv4Address"] as? String ?? "10.0.0.2"],
            subnetMasks: [providerConfig["ipv4Subnet"] as? String ?? "255.255.255.0"]
        )
        ipv4.includedRoutes = [NEIPv4Route.default()]
        tunnelNetworkSettings.ipv4Settings = ipv4
        tunnelNetworkSettings.dnsSettings = dnsSettings

        // 4. Apply TUN settings
        try await setTunnelNetworkSettings(tunnelNetworkSettings)

        // 5. Start proxy engine (reuses RiptideCore protocols/DNS/rules)
        let engine = ProxyEngine()
        // TODO: Initialize with parsed profile + Riptide config
        try await engine.start()
        self.proxyEngine = engine

        // 6. Read packets from TUN interface
        startReadingPackets(engine: engine)

        // 7. Monitor network path for reachability
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                if path.status != .satisfied {
                    await self?.proxyEngine?.pause()
                } else {
                    try? await self?.proxyEngine?.resume()
                }
            }
        }
        monitor.start(queue: .global())
        self.tunnelMonitor = monitor
    }

    open override func stopTunnel(with reason: NEProviderStopReason) async {
        tunnelMonitor?.cancel()
        tunnelMonitor = nil
        await proxyEngine?.stop()
        proxyEngine = nil
    }

    // MARK: - Packet Reading

    private func startReadingPackets(engine: ProxyEngine) {
        packetFlow.readPackets { [weak self] packets, protocols in
            Task { [weak self] in
                for packet in packets {
                    await self?.proxyEngine?.handlePacket(packet, protocolFamily: protocols.first ?? AF_INET)
                }
                // Re-register to keep reading
                self?.startReadingPackets(engine: engine)
            }
        }
    }

    // MARK: - App Communication

    /// Handle messages from the host app (e.g., switch proxy, update config).
    open override func handleAppMessage(_ messageData: Data) async -> Data? {
        // TODO: Decode TunnelProviderMessage, route to proxyEngine
        // For now, acknowledge all messages
        return "ok".data(using: .utf8)
    }
}

// MARK: - Errors

enum TunnelError: Error {
    case missingConfiguration
    case engineStartFailed(String)
}

// MARK: - Proxy Engine Stub

/// Placeholder for the proxy engine that drives the TUN interface on iOS.
/// In production this is backed by RiptideCore's full proxy stack
/// (Protocols + Transport + DNS + Rules + Config).
actor ProxyEngine {
    private(set) var isRunning = false
    private(set) var isPaused = false

    func start() async throws {
        // TODO: Initialize RiptideConfig, RuleEngine, DNSPipeline
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }

    func pause() async {
        isPaused = true
    }

    func resume() async throws {
        isPaused = false
    }

    func handlePacket(_ packet: Data, protocolFamily: Int32) async {
        // TODO: Parse IP packet → determine target → match rules → route to proxy
    }
}
