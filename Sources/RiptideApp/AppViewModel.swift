import Foundation
import Observation
import Riptide

// MARK: - App-Shell Stub Types

/// Stub profile type used by the app layer.
/// Wraps a Riptide `TunnelProfile` for app-level profile management.
public struct Profile: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let config: RiptideConfig

    public init(name: String, config: RiptideConfig) {
        self.id = UUID()
        self.name = name
        self.config = config
    }

    /// Convert to a `TunnelProfile` for use by the tunnel runtime.
    public var tunnelProfile: TunnelProfile {
        TunnelProfile(name: name, config: config)
    }
}

/// Stub subscription type for remote config sources.
public struct Subscription: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let url: String
    public let lastUpdated: Date?

    public init(name: String, url: String, lastUpdated: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Display Models

public struct ProxyNodeDisplay: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let kind: ProxyKind
    public let delayMs: Int?
    public let isSelected: Bool
    public let status: ProxyStatus

    public enum ProxyStatus: Equatable {
        case available
        case timeout
        case error
    }
}

public struct ProxyGroupDisplay: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let kind: ProxyGroupKind
    public let nodes: [ProxyNodeDisplay]
    public let selectedNodeName: String?
}

public struct ConnectionInfo: Identifiable {
    public let id: UUID
    public let host: String
    public let port: Int
    public let `protocol`: String
    public let proxyName: String
    public let connectionCount: Int
}

public struct RuleMatchLog: Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let domain: String
    public let matchedRule: String
    public let resolvedNode: String
}

public struct LogEntry: Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
}

public enum LogLevel: String, CaseIterable, Equatable {
    case all
    case info
    case warn
    case error
}

public enum ConnectionMode: String, Equatable {
    case systemProxy
    case tun
}

// MARK: - AppViewModel

@MainActor
@Observable
public final class AppViewModel {

    // MARK: - Published State

    public private(set) var tunnelState: TunnelLifecycleState = .stopped
    public private(set) var proxyMode: ProxyMode = .rule
    public var connectionMode: ConnectionMode = .systemProxy

    // Config
    public private(set) var profiles: [Profile] = []
    public private(set) var activeProfile: Profile?
    public private(set) var subscriptions: [Subscription] = []

    // Proxies
    public private(set) var proxyGroups: [ProxyGroupDisplay] = []
    public private(set) var allProxies: [ProxyNodeDisplay] = []

    // Traffic
    public private(set) var currentSpeedUp: Int64 = 0
    public private(set) var currentSpeedDown: Int64 = 0
    public private(set) var totalTrafficUp: Int64 = 0
    public private(set) var totalTrafficDown: Int64 = 0
    public private(set) var activeConnections: [ConnectionInfo] = []

    // Rules
    public private(set) var rules: [ProxyRule] = []
    public private(set) var ruleMatches: [RuleMatchLog] = []

    // Logs
    public private(set) var logEntries: [LogEntry] = []
    public var logLevelFilter: LogLevel = .all

    // Errors
    public private(set) var lastError: String?

    // MARK: - Private

    private let controlChannel: InProcessTunnelControlChannel
    private let importService: ConfigImportService
    private var statsTask: Task<Void, Never>?
    private let lifecycleManager: TunnelLifecycleManager

    // MARK: - Init

    public init() {
        let dnsConfig = DNSConfig()
        let dnsPipeline = DNSPipeline(config: dnsConfig, ruleEngine: nil)
        let runtime = LiveTunnelRuntime(
            proxyDialer: TCPTransportDialer(),
            directDialer: TCPTransportDialer(),
            geoIPResolver: .none,
            dnsPipeline: dnsPipeline
        )
        self.lifecycleManager = TunnelLifecycleManager(runtime: runtime)
        self.controlChannel = InProcessTunnelControlChannel(lifecycleManager: lifecycleManager)
        self.importService = ConfigImportService()
    }

    // MARK: - Actions

    public func toggleTunnel() async {
        if tunnelState == .running {
            await stop()
        } else {
            await start()
        }
    }

    public func start() async {
        guard let profile = activeProfile else {
            lastError = "No active profile selected"
            return
        }

        do {
            let response = try await controlChannel.send(.start(profile.tunnelProfile))
            switch response {
            case .ack:
                tunnelState = .running
                await refreshStatus()
                rebuildProxyGroupDisplays()
                lastError = nil
            case .error(let message):
                lastError = "Start failed: \(message)"
            case .status:
                lastError = "Start failed: unexpected status response"
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    public func stop() async {
        do {
            let response = try await controlChannel.send(.stop)
            guard case .ack = response else { return }
            tunnelState = .stopped
            stopStatsPolling()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    public func switchMode(_ mode: ProxyMode) async {
        proxyMode = mode
        guard let profile = activeProfile else { return }

        // Send the current profile to the runtime for re-evaluation with the new mode.
        // The runtime will re-resolve rules using profile.config.mode (now updated).
        do {
            let response = try await controlChannel.send(.update(profile.tunnelProfile))
            guard case .ack = response else { return }
        } catch {
            lastError = String(describing: error)
        }
    }

    public func selectProxy(groupID: String, nodeName: String) async {
        rebuildProxyGroupDisplays()
        lastError = nil
    }

    public func testDelay(groupID: String? = nil) async {
        rebuildProxyGroupDisplays()
    }

    public func importConfig(from url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            guard let yaml = String(data: data, encoding: .utf8) else {
                lastError = "Could not read config file"
                return
            }
            let config = try ClashConfigParser.parse(yaml: yaml)
            let profile = Profile(name: url.deletingPathExtension().lastPathComponent, config: config)
            profiles.append(profile)
            activeProfile = profile
            rebuildProxyGroupDisplays()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    public func addSubscription(url subscriptionURL: String, name: String) async {
        lastError = "Subscriptions not yet implemented"
    }

    public func activateProfile(_ profile: Profile) {
        activeProfile = profile
        rebuildProxyGroupDisplays()
    }

    public func removeProfile(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfile?.id == profile.id {
            activeProfile = profiles.first
        }
        rebuildProxyGroupDisplays()
    }

    // MARK: - Status & Polling

    private func refreshStatus() async {
        do {
            let response = try await controlChannel.send(.status)
            if case .status(let snapshot) = response {
                tunnelState = snapshot.state
                currentSpeedUp = Int64(snapshot.bytesUp)
                currentSpeedDown = Int64(snapshot.bytesDown)
                totalTrafficUp = Int64(snapshot.bytesUp)
                totalTrafficDown = Int64(snapshot.bytesDown)
                if let errorMsg = snapshot.lastError {
                    lastError = errorMsg
                }
            }
        } catch {
            // Ignore polling errors silently
        }
    }

    private func startStatsPolling() {
        statsTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await refreshStatus()
            }
        }
    }

    private func stopStatsPolling() {
        statsTask?.cancel()
        statsTask = nil
        currentSpeedUp = 0
        currentSpeedDown = 0
    }

    // MARK: - Helpers

    private func rebuildProxyGroupDisplays() {
        guard let profile = activeProfile else {
            proxyGroups = []
            allProxies = []
            rules = []
            return
        }

        // Build proxy group displays from the active profile
        var groups: [ProxyGroupDisplay] = []
        for group in profile.config.proxyGroups {
            var nodes: [ProxyNodeDisplay] = []
            for nodeName in group.proxies {
                if let node = profile.config.proxies.first(where: { $0.name == nodeName }) {
                    let isSelected = group.kind == .select && group.proxies.first == nodeName
                    nodes.append(ProxyNodeDisplay(
                        id: node.name,
                        name: node.name,
                        kind: node.kind,
                        delayMs: nil,
                        isSelected: isSelected,
                        status: .available
                    ))
                }
            }
            groups.append(ProxyGroupDisplay(
                id: group.id,
                name: group.id,
                kind: group.kind,
                nodes: nodes,
                selectedNodeName: group.proxies.first
            ))
        }
        proxyGroups = groups

        // All leaf proxies (proxies not used as groups)
        let groupIDs = Set(profile.config.proxyGroups.map { $0.id })
        allProxies = profile.config.proxies
            .filter { !groupIDs.contains($0.name) }
            .map { node in
                ProxyNodeDisplay(
                    id: node.name,
                    name: node.name,
                    kind: node.kind,
                    delayMs: nil,
                    isSelected: false,
                    status: .available
                )
            }

        rules = profile.config.rules
    }
}
