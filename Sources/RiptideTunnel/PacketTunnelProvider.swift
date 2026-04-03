import NetworkExtension
import Riptide

public class RiptidePacketTunnelProvider: PacketTunnelProvider {

    private var runtime: LiveTunnelRuntime?
    private var dnsPipeline: DNSPipeline?

    public override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        Task {
            do {
                // 1. Read config from protocolConfiguration
                guard let tunnelConfig = protocolConfiguration as? NETunnelProviderProtocol,
                      let providerConfig = tunnelConfig.providerConfiguration else {
                    completionHandler(TunnelError.invalidConfiguration)
                    return
                }

                // 2. Parse profile from provider config
                let yaml = providerConfig["configYAML"] as? String ?? ""
                let config = try ClashConfigParser.parse(yaml: yaml)
                let profile = TunnelProfile(name: "tunnel", config: config)

                // 3. Create DNS pipeline
                let dnsPipeline = DNSPipeline(dnsPolicy: profile.config.dnsPolicy)

                // 4. Create runtime
                let runtime = LiveTunnelRuntime(
                    proxyDialer: TCPTransportDialer(),
                    directDialer: TCPTransportDialer(),
                    geoIPResolver: .none,
                    dnsPipeline: dnsPipeline
                )
                try await runtime.start(profile: profile)
                self.runtime = runtime
                self.dnsPipeline = dnsPipeline

                // 5. Configure tunnel network settings
                let settings = NEPacketTunnelNetworkSettings(
                    tunnelRemoteAddress: config.proxies.first?.server ?? "127.0.0.1"
                )

                if profile.config.dnsPolicy.fakeIPRange != nil {
                    // Fake-IP mode: set the tunnel to claim the 198.18.0.0/15 range
                    // so that any destination in that range is intercepted for DNS.
                    // The gateway address (198.18.0.1) is used as the tunnel's IPv4 address.
                    settings.ipv4Settings = NEIPv4Settings(
                        addresses: ["198.18.0.1"],
                        subnetMasks: ["255.255.0.0"]
                    )
                }

                settings.dnsSettings = NEDNSSettings(servers: ["198.18.0.1"])

                try await setTunnelNetworkSettings(settings)

                // 6. Start packet flow
                startPacketFlow()

                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    public override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        Task {
            try? await runtime?.stop()
            completionHandler()
        }
    }

    public override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)?
    ) {
        // Handle commands from the containing app
        guard let command = try? JSONDecoder().decode(TunnelCommand.self, from: messageData) else {
            completionHandler?(nil)
            return
        }
        Task {
            switch command {
            case .switchProfile:
                // Full profile switching requires stopping the existing runtime
                // and reloading the new profile. Stubbed for now (Task 13).
                completionHandler?(Data())
            default:
                completionHandler?(nil)
            }
        }
    }

    // MARK: - Packet Flow

    private func startPacketFlow() {
        packetFlow.readPackets { [weak self] packets, protocols in
            self?.handlePackets(packets, protocols: protocols)
            self?.startPacketFlow()
        }
    }

    private func handlePackets(_ packets: [Data], protocols: [NSNumber]) {
        for (packet, _) in zip(packets, protocols) {
            guard let result = PacketHandler.parseIPPacket(packet) else { continue }
            Task {
                await routePacket(result.ip)
            }
        }
    }

    private func routePacket(_ ip: IPHeader) async {
        // Routing logic:
        //   - TCP (protocol 6): hand off to UserSpaceTCP for userspace stack processing
        //   - UDP port 53 (DNS): intercept and resolve via fake-IP or forward to upstream
        //   - Other UDP: forward directly or via proxy
        //
        // Full implementation lives in Task 13 (UserSpaceTCP / VPN routing engine).
        switch ip.ipProtocol {
        case 6:  // TCP
            // Hand off to UserSpaceTCP for userspace TCP/IP processing
            // UserSpaceTCP will terminate the connection locally and proxy the data
            break
        case 17: // UDP
            if let udp = UDPHeader(ip.payload), udp.destinationPort == 53 {
                // DNS query — resolve via DNSPipeline (fake-IP or real-IP)
                if let query = PacketHandler.extractDNSQuery(ip.payload) {
                    _ = dnsPipeline?.resolve(query: query)
                }
            }
            // Other UDP packets: forward directly or through proxy (stubbed)
        default:
            break
        }
    }
}

// MARK: - App <-> Extension Communication

public enum TunnelCommand: Codable {
    case start(profileData: Data)
    case stop
    case switchProfile(Data)
}

// MARK: - Errors

enum TunnelError: Error, LocalizedError {
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid tunnel configuration"
        }
    }
}
