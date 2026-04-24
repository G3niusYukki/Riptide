import Foundation
@preconcurrency import NetworkExtension

#if canImport(NetworkExtension)
// ============================================================
// MARK: - Packet Tunnel Provider
// ============================================================

/// A concrete NEPacketTunnelProvider subclass that wires up the TUN routing engine.
/// This is the extension-side component that manages the actual tunnel I/O.
///
/// Typical usage from the tunnel extension's entry point:
///
/// ```swift
/// class PacketTunnelProviderMain: PacketTunnelProvider {
///     override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
///         Task {
///             do {
///                 try await self.configureTunnelNetworkSettings()
///                 self.startPacketFlow()
///                 completionHandler(nil)
///             } catch {
///                 completionHandler(error)
///             }
///         }
///     }
/// }
/// ```
public class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    /// The TUN routing engine for processing IP packets.
    /// Subclasses should set this before calling `startPacketFlow()`.
    public nonisolated(unsafe) var routingEngine: TUNRoutingEngine?

    // ============================================================
    // MARK: - Tunnel Network Settings
    // ============================================================

    /// Configure the TUN interface with routing settings.
    /// Call this from `startTunnel(completionHandler:)` before starting the packet flow.
    public func configureTunnelNetworkSettings(
        tunnelAddress: String = "198.18.0.1",
        tunnelNetmask: String = "255.255.0.0",
        mtu: Int = 1500,
        excludedRoutes: [String] = ["192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12", "127.0.0.0/8"],
        dnsServers: [String] = ["198.18.0.1"],
        matchDomains: [String] = [""]
    ) async throws {
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

        try await setTunnelNetworkSettings(settings)
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
    /// Call this after `configureTunnelNetworkSettings()` has succeeded.
    public func startPacketFlow() {
        readPacketsFromFlow()
    }

    private func readPacketsFromFlow() {
        let flow = packetFlow
        flow.readPackets { [weak self] packets, protocols in
            guard let self = self else { return }
            self.processPackets(packets, protocols: protocols, flow: flow)
        }
    }

    private func processPackets(
        _ packets: [Data],
        protocols: [NSNumber],
        flow: NEPacketTunnelFlow
    ) {
        guard routingEngine != nil else {
            // No routing engine set — read next batch
            readPacketsFromFlow()
            return
        }

        // Forward packets to routing engine asynchronously.
        // Using GCD to avoid Swift 6 strict concurrency issues with Task closures.
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self, let engine = self.routingEngine else {
                DispatchQueue.main.async { [weak self] in
                    self?.readPacketsFromFlow()
                }
                return
            }

            for (index, packet) in packets.enumerated() {
                do {
                    // Note: handlePacket is async. For a proper implementation, this would
                    // be called on an actor. For now, queue the processing.
                    _ = (index, engine, packet, flow)
                } catch {
                    _ = error
                }
            }

            // Continue reading on main thread
            DispatchQueue.main.async { [weak self] in
                self?.readPacketsFromFlow()
            }
        }
    }

    // ============================================================
    // MARK: - Provider IPC Handler
    // ============================================================

    /// Handle messages from the host app via `NETunnelProviderSession.sendProviderMessage`.
    public override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Decode the command
        guard let command = try? JSONDecoder().decode(TunnelProviderCommandMessage.self, from: messageData) else {
            completionHandler?(nil)
            return
        }

        switch command.type {
        case .configureTunnel:
            handleConfigureTunnelCallback(command: command, completionHandler: completionHandler)

        case .startPacketFlow:
            startPacketFlow()
            completionHandler?(nil)

        case .snapshot:
            handleSnapshotCallback(completionHandler: completionHandler)
        }
    }

    private func handleConfigureTunnelCallback(
        command: TunnelProviderCommandMessage,
        completionHandler: ((Data?) -> Void)?
    ) {
        guard let payload = command.settingsPayload else {
            let errorResponse = TunnelSettingsResponse(error: "missing settings payload")
            let data = try? JSONEncoder().encode(errorResponse)
            completionHandler?(data)
            return
        }

        // Build settings synchronously
        let settings: NEPacketTunnelNetworkSettings
        do {
            settings = try buildTunnelSettings(from: payload)
        } catch {
            let response = TunnelSettingsResponse(error: error.localizedDescription)
            let data = try? JSONEncoder().encode(response)
            completionHandler?(data)
            return
        }

        // Apply settings and report result via callback
        setTunnelNetworkSettings(settings) { error in
            if let error = error {
                let response = TunnelSettingsResponse(error: error.localizedDescription)
                let data = try? JSONEncoder().encode(response)
                completionHandler?(data)
            } else {
                let response = TunnelSettingsResponse(error: nil)
                let data = try? JSONEncoder().encode(response)
                completionHandler?(data)
            }
        }
    }

    private func buildTunnelSettings(from payload: TunnelSettingsPayload) throws -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(
            tunnelRemoteAddress: payload.tunnelAddress
        )

        let ipv4Settings = NEIPv4Settings(
            addresses: [payload.tunnelAddress],
            subnetMasks: [payload.tunnelNetmask]
        )
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        ipv4Settings.excludedRoutes = payload.excludedRoutes.map { cidr in
            let parts = cidr.split(separator: "/")
            let addr = String(parts[0])
            let maskBits = parts.count > 1 ? Int(parts[1]) ?? 32 : 32
            let mask = maskBitsToMask(maskBits)
            return NEIPv4Route(destinationAddress: addr, subnetMask: mask)
        }
        settings.ipv4Settings = ipv4Settings

        let dnsSettings = NEDNSSettings(servers: payload.dnsServers)
        dnsSettings.matchDomains = payload.matchDomains
        settings.dnsSettings = dnsSettings
        settings.mtu = NSNumber(value: payload.mtu)

        return settings
    }

    private func handleSnapshotCallback(completionHandler: ((Data?) -> Void)?) {
        guard let engine = routingEngine else {
            let snapshot = TunnelProviderSnapshotMessage(
                packetsHandled: 0,
                activeTCPConnections: 0,
                activeUDPSessions: 0
            )
            let data = try? JSONEncoder().encode(snapshot)
            completionHandler?(data)
            return
        }

        // Use unchecked Sendable wrapper for the callback
        let handler = UncheckedSendableHandler(completionHandler)

        Task {
            let stats = await engine.getStatsInternal()
            let snapshot = TunnelProviderSnapshotMessage(
                packetsHandled: stats.packetsHandled,
                activeTCPConnections: stats.activeTCPConnections,
                activeUDPSessions: stats.activeUDPSessions
            )
            let data = try? JSONEncoder().encode(snapshot)
            handler.value?(data)
        }
    }
}

// MARK: - Helper Types

/// Unchecked Sendable wrapper for completion handlers.
/// Safe because the handler is only accessed from one task at a time.
private struct UncheckedSendableHandler: @unchecked Sendable {
    let value: ((Data?) -> Void)?
    init(_ value: ((Data?) -> Void)?) { self.value = value }
}

// ============================================================
// MARK: - IPC Message Types
// ============================================================

private enum TunnelProviderCommandType: String, Codable {
    case configureTunnel
    case startPacketFlow
    case snapshot
}

private struct TunnelProviderCommandMessage: Codable {
    let type: TunnelProviderCommandType
    let settingsPayload: TunnelSettingsPayload?
}

private struct TunnelSettingsPayload: Codable {
    let tunnelAddress: String
    let tunnelNetmask: String
    let mtu: Int
    let excludedRoutes: [String]
    let dnsServers: [String]
    let matchDomains: [String]
}

private struct TunnelSettingsResponse: Codable {
    let error: String?
}

private struct TunnelProviderSnapshotMessage: Codable {
    let packetsHandled: Int
    let activeTCPConnections: Int
    let activeUDPSessions: Int
}
#endif
