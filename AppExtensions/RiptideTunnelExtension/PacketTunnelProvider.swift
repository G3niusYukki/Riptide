import Foundation
import NetworkExtension

/// A minimal PacketTunnelProvider skeleton.
/// This file lives in the RiptideTunnelExtension target and implements the
/// NEPacketTunnelProvider protocol for TUN-mode packet tunnel operations.
///
/// To build the extension:
/// 1. Add a new target to Package.swift for RiptideTunnelExtension
/// 2. Add the NetworkExtension entitlement to AppExtensions/RiptideTunnelExtension/RiptideTunnelExtension.entitlements
/// 3. Configure the app extension host relationship
///
/// The extension communicates with the host app via:
/// - AppGroupStateStore (shared JSON file in app group container)
/// - TunnelProviderBridge / TunnelProviderCommand (NETunnelProviderSession messaging)
@available(macOS 14.0, *)
public final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let stateStore: AppGroupStateStore?

    public override init() {
        self.stateStore = try? AppGroupStateStore()
        super.init()
    }

    public override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // Retrieve configuration from the protocol configuration.
        guard let tunnelConfig = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfig = tunnelConfig.providerConfiguration else {
            completionHandler(NEVPNError(.configurationInvalid))
            return
        }

        // Parse the configuration data.
        guard let configData = providerConfig["config"] as? Data else {
            completionHandler(NEVPNError(.configurationInvalid))
            return
        }

        // Update shared state with TUN mode.
        Task {
            try? await stateStore?.update(mode: .tun)
        }

        // Configure the virtual interface.
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.0.0.1")
        settings.ipv4Settings = NEIPv4Settings(
            addresses: ["198.18.0.1"],
            subnetMasks: ["255.255.0.0"]
        )
        settings.dnsSettings = NEDNSSettings(servers: ["198.18.0.1"])
        settings.mtu = 9000

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                completionHandler(error)
                return
            }

            // Start reading packets from the virtual interface.
            self?.readPackets()
            completionHandler(nil)
        }
    }

    public override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        Task {
            try? await stateStore?.update(mode: .systemProxy)
        }
        completionHandler()
    }

    public override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Handle messages from the host app via NETunnelProviderSession.
        guard let command = try? JSONDecoder().decode(TunnelProviderCommand.self, from: messageData) else {
            completionHandler?(nil)
            return
        }

        Task {
            switch command {
            case .start:
                completionHandler?(nil)
            case .stop:
                cancelTunnelWithError(nil)
                completionHandler?(nil)
            case .snapshot:
                let snapshot = await stateStore?.read()
                let data = try? JSONEncoder().encode(snapshot)
                completionHandler?(data)
            }
        }
    }

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            // Forward packets to the host app runtime for processing.
            self?.processPackets(packets, protocols: protocols)
            self?.readPackets()
        }
    }

    private func processPackets(_ packets: [Data], protocols: [NSNumber]) {
        // In a full implementation, packets are forwarded to the
        // LiveTunnelRuntime via the connection pool.
        // For the scaffold, packets are simply acknowledged.
        packetFlow.writePackets(packets, withProtocols: protocols)
    }
}
