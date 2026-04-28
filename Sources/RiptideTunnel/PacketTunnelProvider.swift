import NetworkExtension
import Riptide

public class RiptidePacketTunnelProvider: NEPacketTunnelProvider {

    private var runtime: LiveTunnelRuntime?
    private var dnsPipeline: DNSPipeline?
    private var routingEngine: TUNRoutingEngine?

    override public func startTunnel(
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
                let (config, ruleSetProviders) = try ClashConfigParser.parse(yaml: yaml)
                let profile = TunnelProfile(name: "tunnel", config: config, ruleSetProviders: ruleSetProviders)

                // 3. Create DNS pipeline
                let pipeline = DNSPipeline(dnsPolicy: profile.config.dnsPolicy)

                // 4. Create runtime
                let tunnelRuntime = LiveTunnelRuntime(
                    proxyDialer: TCPTransportDialer(),
                    directDialer: TCPTransportDialer(),
                    geoIPResolver: .none,
                    dnsPipeline: pipeline
                )
                try await tunnelRuntime.start(profile: profile)
                self.runtime = tunnelRuntime
                self.dnsPipeline = pipeline

                // Create TUN routing engine
                let connector = ProxyConnector(pool: TransportConnectionPool(
                    dialer: TCPTransportDialer(),
                    dialerSelector: .defaultSelector
                ))
                let vpnConfig = VPNConfiguration()
                var ruleSets: [String: [ProxyRule]] = [:]
                for (name, provider) in ruleSetProviders {
                    ruleSets[name] = await provider.rules()
                }
                self.routingEngine = TUNRoutingEngine(
                    proxyConnector: connector,
                    dnsPipeline: pipeline,
                    configuration: vpnConfig,
                    ruleEngine: RuleEngine(
                        rules: config.rules,
                        ruleSets: ruleSets
                    ),
                    proxyNodes: config.proxies
                )

                // 5. Configure tunnel network settings
                let settings = NEPacketTunnelNetworkSettings(
                    tunnelRemoteAddress: config.proxies.first?.server ?? "127.0.0.1"
                )

                if config.dnsPolicy.fakeIPEnabled {
                    // Fake-IP mode: set the tunnel to claim the fake IP range
                    // so that any destination in that range is intercepted for DNS.
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

    override public func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        Task {
            try? await runtime?.stop()
            completionHandler()
        }
    }

    override public func handleAppMessage(
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
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self else { return }
            guard let engine = self.routingEngine else {
                self.packetFlow.writePackets(packets, withProtocols: packets.map { _ in NSNumber(value: AF_INET) })
                self.startPacketFlow()
                return
            }

            Task { [weak self] in
                guard let self else { return }
                var responsePackets: [Data] = []
                for packet in packets {
                    do {
                        let responses = try await engine.handlePacket(packet)
                        responsePackets.append(contentsOf: responses)
                    } catch {
                        // Drop malformed packets
                    }
                }
                if !responsePackets.isEmpty {
                    let protoArray = responsePackets.map { packet -> NSNumber in
                        if !packet.isEmpty, packet[0] >> 4 == 6 {
                            return NSNumber(value: AF_INET6)
                        }
                        return NSNumber(value: AF_INET)
                    }
                    self.packetFlow.writePackets(responsePackets, withProtocols: protoArray)
                }
                // Sequence: only read next batch after current processing completes
                self.startPacketFlow()
            }
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
