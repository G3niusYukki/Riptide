import Foundation
import Observation
import AppKit
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

    /// Convenience for menu bar bindings.
    public var isRunning: Bool { tunnelState == .running }

    // Config
    public private(set) var profiles: [Profile] = []
    public private(set) var activeProfile: Profile?
    public private(set) var subscriptions: [Subscription] = []

    // Proxies
    public private(set) var proxyGroups: [ProxyGroupDisplay] = []
    public private(set) var allProxies: [ProxyNodeDisplay] = []
    private var proxyDelays: [String: Int] = [:]  // proxy name -> delay ms

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
    public private(set) var logEntries: [Riptide.LogEntry] = []
    public var logLevelFilter: Riptide.LogLevel = .debug

    // Errors
    public private(set) var lastError: String?

    // Helper installation
    public private(set) var helperInstalled: Bool = false
    public var showHelperSetup: Bool = false

    // MARK: - Window Reference
    public weak var mainWindow: NSWindow?

    // MARK: - Private

    private let modeCoordinator: ModeCoordinator
    private let importService: ConfigImportService
    private var statsTask: Task<Void, Never>?
    private let smManager = SMJobBlessManager()

    // MARK: - Init

    public init() {
        let mihomoManager = MihomoRuntimeManager()
        self.modeCoordinator = ModeCoordinator(mihomoManager: mihomoManager)
        self.importService = ConfigImportService()
        checkHelperInstallation()
    }

    // MARK: - Helper Installation

    public func checkHelperInstallation() {
        smManager.checkHelperStatus()
        helperInstalled = smManager.isHelperInstalled
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
        // Check helper installation before starting
        await checkHelperInstallationAsync()

        guard helperInstalled else {
            showHelperSetup = true
            return
        }

        guard let profile = activeProfile else {
            lastError = "No active profile selected"
            return
        }

        let runtimeMode: RuntimeMode = connectionMode == .tun ? .tun : .systemProxy

        do {
            try await modeCoordinator.start(mode: runtimeMode, profile: profile.tunnelProfile)
            tunnelState = .running
            startStatsPolling()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Demo entry point for menu bar quick-start.
    public func startDemo() async {
        await start()
    }

    public func stop() async {
        do {
            try await modeCoordinator.stop()
            tunnelState = .stopped
            stopStatsPolling()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    public func switchMode(_ mode: ProxyMode) async {
        proxyMode = mode
        guard var profile = activeProfile else { return }

        // Update the profile's config with the new mode so the runtime receives
        // the correct mode when we send .update.
        let updatedConfig = RiptideConfig(
            mode: mode,
            proxies: profile.config.proxies,
            rules: profile.config.rules,
            proxyGroups: profile.config.proxyGroups,
            dnsPolicy: profile.config.dnsPolicy
        )
        profile = Profile(name: profile.name, config: updatedConfig)
        activeProfile = profile
        rebuildProxyGroupDisplays()
    }

    public func selectProxy(groupID: String, nodeName: String) async {
        rebuildProxyGroupDisplays()
        lastError = nil
    }

    public func testDelay(groupID: String? = nil) async {
        guard let profile = activeProfile else { return }
        guard isRunning else {
            lastError = "请先启动代理服务"
            return
        }

        // Get list of proxies to test
        var proxiesToTest: [(name: String, groupID: String?)] = []

        if let groupID = groupID {
            // Test specific group
            if let group = profile.config.proxyGroups.first(where: { $0.id == groupID }) {
                for proxyName in group.proxies {
                    proxiesToTest.append((proxyName, groupID))
                }
            }
        } else {
            // Test all proxies
            for proxy in profile.config.proxies {
                proxiesToTest.append((proxy.name, nil))
            }
        }

        // Test each proxy and update delays
        for (proxyName, _) in proxiesToTest {
            if let delay = await modeCoordinator.testProxyDelay(proxyName: proxyName) {
                // Store delay result
                await MainActor.run {
                    self.updateProxyDelay(proxyName: proxyName, delay: delay)
                }
            } else {
                // Mark as timeout/error
                await MainActor.run {
                    self.updateProxyDelay(proxyName: proxyName, delay: nil)
                }
            }
            // Small delay between tests to avoid overwhelming the API
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        await MainActor.run {
            self.rebuildProxyGroupDisplaysWithDelays()
        }
    }

    private func updateProxyDelay(proxyName: String, delay: Int?) {
        // This will be called from MainActor
        proxyDelays[proxyName] = delay
    }

    private func rebuildProxyGroupDisplaysWithDelays() {
        guard let profile = activeProfile else {
            proxyGroups = []
            allProxies = []
            rules = []
            return
        }

        // Build proxy group displays with delays
        var groups: [ProxyGroupDisplay] = []
        for group in profile.config.proxyGroups {
            var nodes: [ProxyNodeDisplay] = []
            for nodeName in group.proxies {
                if let node = profile.config.proxies.first(where: { $0.name == nodeName }) {
                    let isSelected = nodeName == group.proxies.first
                    let delay = proxyDelays[node.name]
                    let status: ProxyNodeDisplay.ProxyStatus = delay != nil ? .available : .timeout

                    nodes.append(ProxyNodeDisplay(
                        id: node.name,
                        name: node.name,
                        kind: node.kind,
                        delayMs: delay,
                        isSelected: isSelected,
                        status: status
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

        // All leaf proxies with delays
        let groupIDs = Set(profile.config.proxyGroups.map { $0.id })
        allProxies = profile.config.proxies
            .filter { !groupIDs.contains($0.name) }
            .map { node in
                let delay = proxyDelays[node.name]
                let status: ProxyNodeDisplay.ProxyStatus = delay != nil ? .available : .timeout
                return ProxyNodeDisplay(
                    id: node.name,
                    name: node.name,
                    kind: node.kind,
                    delayMs: delay,
                    isSelected: false,
                    status: status
                )
            }

        rules = profile.config.rules
    }

    public func importConfig(from url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            guard let yaml = String(data: data, encoding: .utf8) else {
                lastError = "Could not read config file"
                return
            }
            let (config, _) = try ClashConfigParser.parse(yaml: yaml)
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

    private func checkHelperInstallationAsync() async {
        let installed = await modeCoordinator.isHelperInstalled()
        await MainActor.run {
            helperInstalled = installed
        }
    }

    private func startStatsPolling() {
        statsTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await refreshStats()
            }
        }
    }

    private func stopStatsPolling() {
        statsTask?.cancel()
        statsTask = nil
        currentSpeedUp = 0
        currentSpeedDown = 0
    }

    private func refreshStats() async {
        let traffic = await modeCoordinator.getTraffic()
        let connections = await modeCoordinator.getConnections()

        await MainActor.run {
            currentSpeedUp = traffic.up
            currentSpeedDown = traffic.down
            totalTrafficUp += traffic.up
            totalTrafficDown += traffic.down
            // Update active connections count
            if connections != activeConnections.count {
                // For now, just track the count - full connection list would need API support
            }
        }
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
