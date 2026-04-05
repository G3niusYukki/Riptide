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
    public let source: ProfileSource

    public init(id: UUID = UUID(), name: String, config: RiptideConfig, source: ProfileSource = .local) {
        self.id = id
        self.name = name
        self.config = config
        self.source = source
    }

    /// Convert to a `TunnelProfile` for use by the tunnel runtime.
    public var tunnelProfile: TunnelProfile {
        TunnelProfile(name: name, config: config)
    }
}

/// Where a profile came from.
public enum ProfileSource: Equatable {
    case local
    case subscription(id: UUID, name: String)
}

// MARK: - Display Models

/// Display-friendly subscription model for the UI layer.
public struct SubscriptionDisplay: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let url: String
    public let autoUpdate: Bool
    public let lastUpdated: Date?
    public let lastError: String?
    public let profileCount: Int

    public init(
        id: UUID, name: String, url: String, autoUpdate: Bool,
        lastUpdated: Date?, lastError: String?, profileCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.autoUpdate = autoUpdate
        self.lastUpdated = lastUpdated
        self.lastError = lastError
        self.profileCount = profileCount
    }
}

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
    public private(set) var subscriptions: [SubscriptionDisplay] = []

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
    private let subscriptionManager: SubscriptionManager
    private var statsTask: Task<Void, Never>?
    private let smManager = SMJobBlessManager()

    // MARK: - Init

    public init() {
        let mihomoManager = MihomoRuntimeManager()
        self.modeCoordinator = ModeCoordinator(mihomoManager: mihomoManager)
        self.importService = ConfigImportService()
        self.subscriptionManager = SubscriptionManager()
        checkHelperInstallation()
        Task { await loadSubscriptionsFromBackend() }
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
            // Fetch initial logs
            Task { await fetchLogs() }
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
        await modeCoordinator.selectProxy(groupID: groupID, nodeName: nodeName)
        // Update the display to reflect the selection
        await MainActor.run {
            rebuildProxyGroupDisplaysWithSelection(groupID: groupID, nodeName: nodeName)
            lastError = nil
        }
    }

    /// Rebuilds proxy group displays with a specific selection highlighted.
    private func rebuildProxyGroupDisplaysWithSelection(groupID: String, nodeName: String) {
        guard let profile = activeProfile else {
            proxyGroups = []
            allProxies = []
            rules = []
            return
        }

        var groups: [ProxyGroupDisplay] = []
        for group in profile.config.proxyGroups {
            var nodes: [ProxyNodeDisplay] = []
            for proxyName in group.proxies {
                if let node = profile.config.proxies.first(where: { $0.name == proxyName }) {
                    let isSelected = (group.id == groupID && proxyName == nodeName)
                    let delay = proxyDelays[node.name]
                    let status: ProxyNodeDisplay.ProxyStatus = delay != nil ? .available : .available

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
            let selectedName = (group.id == groupID) ? nodeName : group.proxies.first
            groups.append(ProxyGroupDisplay(
                id: group.id,
                name: group.id,
                kind: group.kind,
                nodes: nodes,
                selectedNodeName: selectedName
            ))
        }
        proxyGroups = groups

        let groupIDs = Set(profile.config.proxyGroups.map { $0.id })
        allProxies = profile.config.proxies
            .filter { !groupIDs.contains($0.name) }
            .map { node in
                let delay = proxyDelays[node.name]
                return ProxyNodeDisplay(
                    id: node.name,
                    name: node.name,
                    kind: node.kind,
                    delayMs: delay,
                    isSelected: false,
                    status: .available
                )
            }
        rules = profile.config.rules
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

    // MARK: - Subscription Management

    /// Loads subscriptions from the backend and refreshes their display profiles.
    public func loadSubscriptionsFromBackend() async {
        let subs = await subscriptionManager.allSubscriptions()
        await MainActor.run {
            subscriptions = subs.map { sub in
                let profileCount = profiles.count { $0.source == .subscription(id: sub.id, name: sub.name) }
                return SubscriptionDisplay(
                    id: sub.id, name: sub.name, url: sub.url,
                    autoUpdate: sub.autoUpdate, lastUpdated: sub.lastUpdated,
                    lastError: sub.lastError, profileCount: profileCount
                )
            }
        }
    }

    /// Adds a new subscription, fetches its nodes, and creates a profile.
    public func addSubscription(url subscriptionURL: String, name: String, autoUpdate: Bool, interval: TimeInterval) async {
        let sub = await subscriptionManager.addSubscription(
            name: name, url: subscriptionURL, autoUpdate: autoUpdate, interval: interval
        )
        let result = await subscriptionManager.updateSubscription(id: sub.id)
        switch result {
        case .success(let proxies):
            let config = RiptideConfig(
                mode: .rule,
                proxies: proxies,
                rules: [],
                proxyGroups: [],
                dnsPolicy: DNSPolicy()
            )
            let profile = Profile(name: name, config: config, source: .subscription(id: sub.id, name: sub.name))
            await MainActor.run {
                profiles.append(profile)
                if activeProfile == nil { activeProfile = profile }
                rebuildProxyGroupDisplays()
            }
        case .failure(let error):
            await MainActor.run { lastError = "订阅拉取失败: \(error)" }
        case .noChange:
            break
        }
        await loadSubscriptionsFromBackend()
    }

    /// Removes a subscription and its associated profile.
    public func removeSubscription(id: UUID) async {
        await subscriptionManager.removeSubscription(id: id)
        await MainActor.run {
            profiles.removeAll { profile in
                if case .subscription(let subID, _) = profile.source { return subID == id }
                return false
            }
            if let active = activeProfile,
               case .subscription(let subID, _) = active.source, subID == id {
                activeProfile = profiles.first
            }
            rebuildProxyGroupDisplays()
        }
        await loadSubscriptionsFromBackend()
    }

    /// Updates (refreshes) a subscription by fetching fresh nodes.
    public func updateSubscription(id: UUID) async {
        let result = await subscriptionManager.updateSubscription(id: id)
        switch result {
        case .success(let proxies):
            let sub = await subscriptionManager.subscription(id: id)
            if let sub {
                let config = RiptideConfig(
                    mode: .rule,
                    proxies: proxies,
                    rules: [],
                    proxyGroups: [],
                    dnsPolicy: DNSPolicy()
                )
                let newProfile = Profile(name: sub.name, config: config, source: .subscription(id: sub.id, name: sub.name))
                await MainActor.run {
                    if let idx = profiles.firstIndex(where: { p in
                        if case .subscription(let sid, _) = p.source { return sid == id }
                        return false
                    }) {
                        profiles[idx] = newProfile
                        if activeProfile?.id == profiles[idx].id { activeProfile = newProfile }
                    }
                    rebuildProxyGroupDisplays()
                }
            }
        case .failure(let error):
            await MainActor.run { lastError = "订阅更新失败: \(error)" }
        case .noChange:
            break
        }
        await loadSubscriptionsFromBackend()
    }

    /// Edits subscription properties.
    public func editSubscription(id: UUID, name: String? = nil, url: String? = nil, autoUpdate: Bool? = nil, interval: TimeInterval? = nil) async {
        await subscriptionManager.updateSubscription(
            id: id, name: name, url: url, autoUpdate: autoUpdate, interval: interval
        )
        await loadSubscriptionsFromBackend()
    }

    /// Closes a specific connection.
    public func closeConnection(id: String) async {
        await modeCoordinator.closeConnection(id: id)
        await refreshStats()
    }

    /// Closes all connections.
    public func closeAllConnections() async {
        await modeCoordinator.closeAllConnections()
        await refreshStats()
    }

    /// Fetches logs from the mihomo API and populates logEntries.
    public func fetchLogs() async {
        let rawLogs = await modeCoordinator.getLogs(level: vmLogLevelString, lines: 300)
        let parser = LogEntryParser()
        let entries = rawLogs.map { parser.parse($0) }
        await MainActor.run {
            logEntries = entries
        }
    }

    private var vmLogLevelString: String {
        switch logLevelFilter {
        case .debug: return "debug"
        case .info: return "info"
        case .warning: return "warning"
        case .error: return "error"
        }
    }

    /// Clears all log entries.
    public func clearLogs() {
        logEntries = []
    }

    /// Exports log entries to a file.
    public func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "riptide-logs-\(ISODate(Date())).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = logEntries.map { "[\($0.timestamp.formatted())] [\($0.level.displayName)] \($0.message)" }.joined(separator: "\n")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = "导出失败: \(error.localizedDescription)"
        }
    }

    private func ISODate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
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
            var logCounter = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await refreshStats()
                // Refresh logs every 3 polling cycles (3 seconds)
                logCounter += 1
                if logCounter >= 3 {
                    logCounter = 0
                    await fetchLogs()
                }
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

            // Map connection tuples to ConnectionInfo
            let mapped = connections.map { conn in
                ConnectionInfo(
                    id: UUID(uuidString: conn.id) ?? UUID(),
                    host: conn.host,
                    port: 0,
                    protocol: conn.network,
                    proxyName: conn.proxy,
                    connectionCount: 1
                )
            }
            activeConnections = mapped
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
