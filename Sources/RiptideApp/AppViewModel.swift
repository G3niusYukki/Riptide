// swiftlint:disable file_length type_body_length
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
    public let userinfo: SubscriptionUserinfo?

    public init(
        id: UUID, name: String, url: String, autoUpdate: Bool,
        lastUpdated: Date?, lastError: String?, profileCount: Int = 0,
        userinfo: SubscriptionUserinfo? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.autoUpdate = autoUpdate
        self.lastUpdated = lastUpdated
        self.lastError = lastError
        self.profileCount = profileCount
        self.userinfo = userinfo
    }
}

/// Display-friendly rule set provider model for the UI layer.
public struct RuleSetDisplay: Identifiable, Equatable {
    public let id: String  // provider name
    public let name: String
    public let url: String
    public let interval: Int
    public let ruleCount: Int
    public let lastUpdated: Date?

    public init(id: String, name: String, url: String, interval: Int, ruleCount: Int, lastUpdated: Date? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.interval = interval
        self.ruleCount = ruleCount
        self.lastUpdated = lastUpdated
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
    /// Raw backend connection ID — use this for close operations.
    public let backendId: String
    public let host: String
    public let port: Int
    public let `protocol`: String
    public let proxyName: String
    public let connectionCount: Int

    // Detail fields for connection detail panel
    public let sourceIP: String?
    public let sourcePort: String?
    public let destinationIP: String?
    public let destinationPort: String?
    public let matchedRule: String?
    public let rulePayload: String?
    public let chain: [String]
    public let startTime: String?
    public let uploadBytes: Int
    public let downloadBytes: Int
    public let networkType: String?

    public init(
        id: UUID, backendId: String, host: String, port: Int,
        protocol: String, proxyName: String, connectionCount: Int,
        sourceIP: String? = nil, sourcePort: String? = nil,
        destinationIP: String? = nil, destinationPort: String? = nil,
        matchedRule: String? = nil, rulePayload: String? = nil,
        chain: [String] = [], startTime: String? = nil,
        uploadBytes: Int = 0, downloadBytes: Int = 0,
        networkType: String? = nil
    ) {
        self.id = id
        self.backendId = backendId
        self.host = host
        self.port = port
        self.protocol = `protocol`
        self.proxyName = proxyName
        self.connectionCount = connectionCount
        self.sourceIP = sourceIP
        self.sourcePort = sourcePort
        self.destinationIP = destinationIP
        self.destinationPort = destinationPort
        self.matchedRule = matchedRule
        self.rulePayload = rulePayload
        self.chain = chain
        self.startTime = startTime
        self.uploadBytes = uploadBytes
        self.downloadBytes = downloadBytes
        self.networkType = networkType
    }
}

public struct RuleMatchLog: Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let domain: String
    public let matchedRule: String
    public let resolvedNode: String
}

public enum ConnectionMode: String, Equatable, CaseIterable {
    case systemProxy
    case tun

    public static var productAvailableModes: [ConnectionMode] {
        RuntimeMode.productAvailableModes.map { mode in
            switch mode {
            case .systemProxy:
                return .systemProxy
            case .tun:
                return .tun
            }
        }
    }

    public var displayName: String {
        switch self {
        case .systemProxy:
            return "系统代理"
        case .tun:
            return "TUN模式"
        }
    }
}

// MARK: - AppViewModel

@Observable
public final class AppViewModel: @unchecked Sendable {

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

    /// Per-group user-customized node order. Persisted to UserDefaults so
    /// drag/drop rearrangements survive app relaunches. Maps groupID to an
    /// ordered list of node names. Nodes not present in the list (or new
    /// nodes from a refreshed profile) are appended at the end.
    public private(set) var nodeOrder: [String: [String]] = [:]

    // Traffic
    public private(set) var currentSpeedUp: Int64 = 0
    public private(set) var currentSpeedDown: Int64 = 0
    public private(set) var totalTrafficUp: Int64 = 0
    public private(set) var totalTrafficDown: Int64 = 0
    public private(set) var activeConnections: [ConnectionInfo] = []

    // Rules
    public private(set) var rules: [ProxyRule] = []
    public private(set) var ruleMatches: [RuleMatchLog] = []

    // Rule engine — built lazily by `buildRuleEngine()` for the rule tester.
    // Cached and rebuilt only when the active config changes.
    public private(set) var ruleEngine: RuleEngine?
    private var ruleEngineConfig: RiptideConfig?

    // Rule Sets
    private var activeRuleSetProviders: [String: RuleSetProvider] = [:]
    private var ruleSetConfigs: [String: RuleSetProviderConfig] = [:]
    public private(set) var ruleSetDisplays: [RuleSetDisplay] = []

    // Backups
    private let backupManager = ConfigBackupManager()
    public private(set) var backupDisplays: [ConfigBackup] = []

    // Logs
    public private(set) var logEntries: [Riptide.LogEntry] = []
    public var logLevelFilter: Riptide.LogLevel = .debug

    // Errors
    public private(set) var lastError: String?
    /// Warning shown when system proxy guard is unavailable (no helper).
    public private(set) var guardUnavailableWarning: String?

    // Helper installation
    public private(set) var helperInstalled: Bool = false
    public var showHelperSetup: Bool = false

    // Mihomo core management
    public private(set) var mihomoVersion: String = ""
    public private(set) var availableUpdate: MihomoDownloader.UpdateInfo?
    public private(set) var isDownloadingMihomo: Bool = false
    public private(set) var mihomoDownloadProgress: Double = 0
    public var mihomoChannel: MihomoDownloader.Channel = .stable
    public private(set) var mihomoDownloadError: String?

    // MARK: - Window Reference
    public weak var mainWindow: NSWindow?

    // MARK: - Logbook

    /// Persistent diagnostic Logbook (store + writer + view model trio).
    /// Wired here so business modules can later receive the writer via DI.
    public let logbook: LogbookContainer

    // MARK: - Private

    private let mihomoManager: any MihomoRuntimeManaging
    private let modeCoordinator: ModeCoordinator
    private let importService: ConfigImportService
    private let subscriptionManager: SubscriptionManager
    private let profileStore: ProfileStore
    private let overrideStore: OverrideStore
    private var statsTask: Task<Void, Never>?
    private let smManager: SMJobBlessManager
    private var subscriptionScheduler: SubscriptionUpdateScheduler?

    // MARK: - Init

    public init() {
        // Wire the Logbook trio first so subsequent constructors can pick up
        // `logbook.writer` via DI in Task 12.
        self.logbook = LogbookContainer(paths: .default)

        let manager = GoCoreTunnelRuntime()
        self.mihomoManager = manager
        self.modeCoordinator = ModeCoordinator(mihomoManager: manager)
        self.importService = ConfigImportService()
        self.subscriptionManager = SubscriptionManager()
        do {
            self.profileStore = try ProfileStore()
            self.overrideStore = try OverrideStore()
        } catch {
            fatalError("Failed to initialize ProfileStore: \(error)")
        }
        self.smManager = SMJobBlessManager()
        // Inject the Logbook writer into each business module so its
        // fire-and-forget logInfo/logError calls reach the persistent store.
        checkHelperInstallation()
        // Restore any persisted drag/drop node order from a prior session.
        loadNodeOrder()
        let writer = self.logbook.writer
        Task {
            await self.modeCoordinator.setLogbookWriter(writer)
            await self.mihomoManager.setLogbookWriter(writer)
            await self.subscriptionManager.setLogbookWriter(writer)
            await self.overrideStore.setLogbookWriter(writer)
            await self.mihomoManager.helperConnection.setLogbookWriter(writer)
            await loadProfilesFromStore()

            await loadSubscriptionsFromBackend()
            startSubscriptionScheduler()
            await checkMihomoOnLaunch()
        }
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

    // MARK: - Hotkey Actions

    /// Routes a hotkey action from `HotkeyManager` to the appropriate
    /// `AppViewModel` method. Safe to call from any actor — handlers that
    /// touch UI state hop to `MainActor` internally.
    public func handleHotkeyAction(_ action: HotkeyManager.HotkeyAction) async {
        switch action {
        case .toggleTunnel:
            await toggleTunnel()
        case .toggleMode:
            // Cycle connection modes: off -> systemProxy -> tun -> off
            await cycleConnectionMode()
        case .showPanel:
            await MainActor.run {
                NSApp.activate(ignoringOtherApps: true)
                if let window = AppCoordinator.shared.mainWindow {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        case .toggleSystemProxy:
            await toggleSystemProxy()
        case .switchNextNode:
            await switchToNextNode()
        case .testAllDelay:
            await testDelay()
        }
    }

    /// Cycles through `off -> systemProxy -> tun -> off`. When the tunnel
    /// is currently running, it is restarted in the new mode. When stopping,
    /// `stop()` halts the runtime.
    private func cycleConnectionMode() async {
        let wasRunning = tunnelState == .running
        let next: ConnectionMode?
        switch connectionMode {
        case .systemProxy: next = .tun
        case .tun:        next = .systemProxy  // wrap back to systemProxy (no explicit "off" in ConnectionMode)
        }
        if let next {
            connectionMode = next
            if wasRunning {
                await stop()
                await start()
            }
        }
    }

    /// Toggles the system proxy connection mode. If the tunnel is currently
    /// running in TUN mode, the runtime is restarted in system-proxy mode
    /// (and vice versa). Stops the runtime if it is already in the target
    /// mode.
    private func toggleSystemProxy() async {
        let wasRunning = tunnelState == .running
        if connectionMode == .systemProxy {
            if wasRunning {
                await stop()
            } else {
                connectionMode = .tun
            }
        } else {
            connectionMode = .systemProxy
            if wasRunning {
                await stop()
                await start()
            }
        }
    }

    /// Advances the first `.select` group to its next node, wrapping around
    /// at the end. No-op if there is no `.select` group or no current
    /// selection.
    private func switchToNextNode() async {
        guard let primaryGroup = proxyGroups.first(where: { $0.kind == .select }),
              let currentName = primaryGroup.selectedNodeName,
              let currentIdx = primaryGroup.nodes.firstIndex(where: { $0.name == currentName }),
              !primaryGroup.nodes.isEmpty else {
            return
        }
        let nextIdx = (currentIdx + 1) % primaryGroup.nodes.count
        let nextNode = primaryGroup.nodes[nextIdx]
        await selectProxy(groupID: primaryGroup.id, nodeName: nextNode.name)
    }

    public func start() async {
        // Check helper installation (non-blocking — sudo fallback available)
        await checkHelperInstallationAsync()

        guard let profile = activeProfile else {
            lastError = "No active profile selected"
            return
        }

        let runtimeMode: RuntimeMode = connectionMode == .tun ? .tun : .systemProxy

        // TUN mode pre-check: mihomo binary must exist
        if runtimeMode == .tun && !FileManager.default.isExecutableFile(atPath: MihomoPaths().executable) {
            lastError = "TUN 模式需要 mihomo 二进制，请先下载"
            return
        }

        do {
            try await modeCoordinator.start(mode: runtimeMode, profile: profile.tunnelProfile)
            tunnelState = .running
            startStatsPolling()
            Task { await fetchLogs() } // Fetch initial logs
            // Check for guard unavailability in System Proxy mode
            let events = await modeCoordinator.recentEvents()
            if let guardEvent = events.first(where: {
                if case .guardUnavailable = $0 { return true }
                return false
            }), case .guardUnavailable(let reason) = guardEvent {
                self.guardUnavailableWarning = reason
            }
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
                // Notify when latency exceeds the 5s timeout threshold — the
                // user is likely to want to switch to a healthier node.
                if delay > 5000 {
                    await UserNotificationManager.shared.notifyNodeFailure(
                        nodeName: proxyName, latencyMs: delay
                    )
                }
            } else {
                // Mark as timeout/error
                await MainActor.run {
                    self.updateProxyDelay(proxyName: proxyName, delay: nil)
                }
                await UserNotificationManager.shared.notifyNodeFailure(
                    nodeName: proxyName, latencyMs: 0
                )
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

            // Persist to ProfileStore
            _ = try? await profileStore.importProfile(name: profile.name, yaml: yaml)
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Loads persisted profiles from ProfileStore on startup.
    private func loadProfilesFromStore() async {
        let stored = await profileStore.allProfiles()
        guard !stored.isEmpty else { return }

        var loaded: [Profile] = []
        for storedProfile in stored {
            if let (config, _) = try? ClashConfigParser.parse(yaml: storedProfile.rawYAML) {
                let profile = Profile(
                    id: storedProfile.id,
                    name: storedProfile.name,
                    config: config,
                    source: .local
                )
                loaded.append(profile)
            }
        }

        let loadedProfiles = loaded
        await MainActor.run {
            if !loadedProfiles.isEmpty {
                self.profiles = loadedProfiles
                if self.activeProfile == nil {
                    self.activeProfile = loadedProfiles.first
                    self.rebuildProxyGroupDisplays()
                }
            }
        }
    }

    // MARK: - Subscription Management

    /// Starts the subscription auto-update scheduler (5-minute interval).
    private func startSubscriptionScheduler() {
        let scheduler = SubscriptionUpdateScheduler(manager: subscriptionManager, checkInterval: 300)
        Task { await scheduler.start() }
        subscriptionScheduler = scheduler
    }

    /// Stops the subscription auto-update scheduler.
    private func stopSubscriptionScheduler() {
        guard let scheduler = subscriptionScheduler else { return }
        Task { await scheduler.stop() }
        subscriptionScheduler = nil
    }

    /// Loads subscriptions from the backend and refreshes their display profiles.
    public func loadSubscriptionsFromBackend() async {
        let subs = await subscriptionManager.allSubscriptions()
        await MainActor.run {
            subscriptions = subs.map { sub in
                // Match by subscription ID only (name may change over time)
                let profileCount = profiles.count {
                    guard case let .subscription(id, _) = $0.source else { return false }
                    return id == sub.id
                }
                return SubscriptionDisplay(
                    id: sub.id, name: sub.name, url: sub.url,
                    autoUpdate: sub.autoUpdate, lastUpdated: sub.lastUpdated,
                    lastError: sub.lastError, profileCount: profileCount,
                    userinfo: sub.userinfo
                )
            }
        }
        await notifyExpiringSubscriptions(subs)
    }

    /// Surfaces a system notification for any subscription that is within
    /// 3 days of expiry. Called whenever the subscription list is reloaded.
    private func notifyExpiringSubscriptions(_ subs: [Riptide.Subscription]) async {
        for sub in subs {
            guard let userinfo = sub.userinfo,
                  let expiry = userinfo.expireDate else { continue }
            let secondsRemaining = expiry.timeIntervalSinceNow
            guard secondsRemaining > 0, secondsRemaining <= 3 * 24 * 3600 else { continue }
            let days = max(1, Int((secondsRemaining / 86_400).rounded(.up)))
            await UserNotificationManager.shared.notifySubscriptionExpiring(
                name: sub.name, daysRemaining: days
            )
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
                lastError = nil  // Clear any previous error
                profiles.append(profile)
                if activeProfile == nil { activeProfile = profile }
                rebuildProxyGroupDisplays()
            }
        case .failure(let error):
            await MainActor.run { lastError = "订阅拉取失败: \(error)" }
        case .noChange:
            await MainActor.run { lastError = nil }  // Clear stale error
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

    /// Refresh every subscription sequentially. Used by the dashboard quick-action
    /// button. Failures are recorded on each subscription's `lastError` and don't
    /// short-circuit the rest.
    public func refreshAllSubscriptions() async {
        for sub in await subscriptionManager.allSubscriptions() {
            await updateSubscription(id: sub.id)
        }
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
                await MainActor.run {
                    if let idx = profiles.firstIndex(where: { profile in
                        if case .subscription(let sid, _) = profile.source { return sid == id }
                        return false
                    }) {
                        // Preserve original profile ID so activeProfile reference stays valid
                        let existingProfile = profiles[idx]
                        let wasActiveProfile = activeProfile?.id == existingProfile.id
                        let refreshedProfile = Profile(
                            id: existingProfile.id,
                            name: sub.name, config: config,
                            source: .subscription(id: sub.id, name: sub.name)
                        )
                        profiles[idx] = refreshedProfile
                        if wasActiveProfile { activeProfile = refreshedProfile }
                        rebuildProxyGroupDisplays()
                    }
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

    // MARK: - Rule Set Lifecycle

    private func startRuleSetProviders(from profile: Profile) {
        stopRuleSetProviders()

        for (name, config) in profile.config.ruleProviders {
            ruleSetConfigs[name] = config
            let provider = RuleSetProvider(config: config)
            activeRuleSetProviders[name] = provider
            Task { await provider.start() }
        }

        Task { await refreshRuleSetDisplays() }
    }

    private func stopRuleSetProviders() {
        let providers = activeRuleSetProviders
        activeRuleSetProviders.removeAll()
        ruleSetConfigs.removeAll()
        ruleSetDisplays = []

        for provider in providers.values {
            Task { await provider.stop() }
        }
    }

    public func refreshRuleSetProvider(name: String) async {
        guard let provider = activeRuleSetProviders[name] else { return }
        await provider.refresh()
        await refreshRuleSetDisplays()
    }

    private func refreshRuleSetDisplays() async {
        var displays: [RuleSetDisplay] = []
        for (name, provider) in activeRuleSetProviders {
            let rules = await provider.rules()
            let config = ruleSetConfigs[name]
            displays.append(RuleSetDisplay(
                id: name,
                name: name,
                url: config?.url ?? "",
                interval: config?.interval ?? 0,
                ruleCount: rules.count
            ))
        }
        ruleSetDisplays = displays
    }

    // MARK: - Rule Engine Builder

    /// Returns the active profile's `RiptideConfig`, or nil if there is no
    /// active profile.
    public func currentRiptideConfig() -> RiptideConfig? {
        activeProfile?.config
    }

    /// Builds (or returns the cached) `RuleEngine` for the active profile.
    ///
    /// GeoIP and GeoSite resolvers are loaded lazily from the default mihomo
    /// cache directory. Missing databases degrade gracefully to a resolver
    /// that always returns nil.
    public func buildRuleEngine() -> RuleEngine? {
        guard let config = currentRiptideConfig() else { return nil }
        if let cached = ruleEngine, ruleEngineConfig == config {
            return cached
        }

        // Try to load resolvers from default geo asset paths.
        let geoIPPath = "\(NSHomeDirectory())/Library/Application Support/Riptide/mihomo/cache/GeoIP.dat"
        let geoSitePath = "\(NSHomeDirectory())/Library/Application Support/Riptide/mihomo/cache/GeoSite.dat"

        let geoIPResolver: GeoIPResolver
        if let db = try? GeoIPDatabase(filePath: geoIPPath) {
            geoIPResolver = GeoIPResolver(database: db)
        } else {
            geoIPResolver = .none
        }
        let geoSiteResolver = try? GeoSiteResolver(filePath: geoSitePath)

        ruleEngine = RuleEngine(
            rules: config.rules,
            geoIPResolver: geoIPResolver,
            geoSiteResolver: geoSiteResolver,
            asnResolver: nil
        )
        ruleEngineConfig = config
        return ruleEngine
    }

    // MARK: - Rule Mutation

    /// Appends a rule to the active profile's rule list and refreshes the
    /// display copy. The change is in-memory only — persist the profile via
    /// `ProfileStore` (Task 4.2 YAML editor) if a disk write is desired.
    @MainActor
    public func appendRule(_ rule: ProxyRule) {
        guard var profile = activeProfile else { return }
        let updatedRules = profile.config.rules + [rule]
        let updatedConfig = RiptideConfig(
            mode: profile.config.mode,
            proxies: profile.config.proxies,
            rules: updatedRules,
            proxyGroups: profile.config.proxyGroups,
            dnsPolicy: profile.config.dnsPolicy,
            ruleProviders: profile.config.ruleProviders,
            proxyProviders: profile.config.proxyProviders
        )
        profile = Profile(
            id: profile.id,
            name: profile.name,
            config: updatedConfig,
            source: profile.source
        )
        activeProfile = profile
        rules = updatedRules
    }

    // MARK: - Backup Management

    public func loadBackups() async {
        do {
            backupDisplays = try await backupManager.listBackups()
        } catch {
            lastError = "加载备份失败: \(error.localizedDescription)"
        }
    }

    public func createManualBackup() async {
        guard let profile = activeProfile else { return }
        do {
            if let stored = await profileStore.profile(id: profile.id) {
                try await backupManager.backup(yaml: stored.rawYAML, name: profile.name)
                await loadBackups()
            }
        } catch {
            lastError = "备份失败: \(error.localizedDescription)"
        }
    }

    public func restoreBackup(_ backup: ConfigBackup) async {
        do {
            let yaml = try await backupManager.restore(from: backup)
            let name = "恢复-\(backup.name)"
            _ = try await profileStore.importProfile(name: name, yaml: yaml)
            await loadProfilesFromStore()
            await loadBackups()
        } catch {
            lastError = "恢复失败: \(error.localizedDescription)"
        }
    }

    public func deleteBackup(_ backup: ConfigBackup) async {
        do {
            try await backupManager.delete(backup)
            await loadBackups()
        } catch {
            lastError = "删除备份失败: \(error.localizedDescription)"
        }
    }

    /// Returns the raw YAML of the profile with the given id, or an empty
    /// string if the profile is not present in `ProfileStore`.
    public func profileYAML(id: UUID) async -> String {
        await profileStore.profile(id: id)?.rawYAML ?? ""
    }

    /// Updates the active profile's raw YAML (and the in-memory `RiptideConfig`
    /// derived from it) and persists the change via `ProfileStore`. The
    /// profile's `id` and `source` are preserved; subscription-backed
    /// profiles keep their existing `subscriptionURL`.
    ///
    /// - Throws: `ClashConfigError` if the YAML cannot be parsed.
    @MainActor
    public func updateProfileYAML(_ profileID: UUID, yaml: String) async throws {
        let (newConfig, _) = try ClashConfigParser.parse(yaml: yaml)
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let existing = profiles[idx]
        let updated = Profile(
            id: existing.id,
            name: existing.name,
            config: newConfig,
            source: existing.source
        )
        profiles[idx] = updated
        if activeProfile?.id == profileID {
            activeProfile = updated
            rebuildProxyGroupDisplays()
        }
        // Persist via the actor-backed store. `importProfile` creates a new
        // internal id for the stored record, so we re-read it back and
        // re-link the in-memory profile to the stored id when possible.
        _ = try? await profileStore.importProfile(name: updated.name, yaml: yaml)
    }

    public func activateProfile(_ profile: Profile) {
        // Backup current config before switching
        if let currentID = activeProfile?.id, let currentName = activeProfile?.name {
            Task {
                if let stored = await profileStore.profile(id: currentID) {
                    try? await backupManager.backup(yaml: stored.rawYAML, name: currentName)
                }
            }
        }

        activeProfile = profile
        rebuildProxyGroupDisplays()
        startRuleSetProviders(from: profile)
    }

    public func removeProfile(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfile?.id == profile.id {
            activeProfile = profiles.first
            if let newProfile = activeProfile {
                startRuleSetProviders(from: newProfile)
            } else {
                stopRuleSetProviders()
            }
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

            // Map enriched backend ConnectionInfo to app-level ConnectionInfo
            let mapped = connections.map { conn in
                let meta = conn.metadata
                return ConnectionInfo(
                    id: UUID(uuidString: conn.id) ?? UUID(),
                    backendId: conn.id,
                    host: meta.host ?? meta.destinationIP ?? "unknown",
                    port: Int(meta.destinationPort ?? "") ?? 0,
                    protocol: meta.network.uppercased(),
                    proxyName: conn.chains.last ?? "Direct",
                    connectionCount: 1,
                    sourceIP: meta.sourceIP,
                    sourcePort: meta.sourcePort,
                    destinationIP: meta.destinationIP,
                    destinationPort: meta.destinationPort,
                    matchedRule: conn.rule,
                    rulePayload: conn.rulePayload,
                    chain: conn.chains,
                    startTime: conn.start,
                    uploadBytes: conn.upload,
                    downloadBytes: conn.download,
                    networkType: meta.type
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

    // MARK: - Node Order (drag/drop persistence)

    /// Returns the persisted node-name order for a group, or an empty array
    /// if the user has not yet reordered the group.
    public func nodeOrder(for groupID: String) -> [String] {
        nodeOrder[groupID] ?? []
    }

    /// Persists a new node-name order for a group and updates the in-memory
    /// state. Saving is best-effort; a JSON encode failure is silently
    /// ignored (the in-memory change still applies for the current session).
    public func setNodeOrder(_ order: [String], for groupID: String) {
        nodeOrder[groupID] = order
        saveNodeOrder()
    }

    /// Reads the persisted node-order map from UserDefaults. Missing or
    /// undecodable data is treated as "no persisted order".
    public func loadNodeOrder() {
        guard let data = UserDefaults.standard.data(forKey: "riptide.proxyGroup.nodeOrder"),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return
        }
        nodeOrder = decoded
    }

    private func saveNodeOrder() {
        guard let data = try? JSONEncoder().encode(nodeOrder) else { return }
        UserDefaults.standard.set(data, forKey: "riptide.proxyGroup.nodeOrder")
    }

    // MARK: - Mihomo Core Management

    /// Checks mihomo status on launch and downloads if needed.
    public func checkMihomoOnLaunch() async {
        let paths = MihomoPaths()
        let mihomoPath = paths.baseDirectory.appendingPathComponent("mihomo").path

        if !FileManager.default.fileExists(atPath: mihomoPath) {
            // First launch - no kernel installed
            await downloadLatestMihomo(channel: mihomoChannel)
        } else {
            // Check current version
            let version = getCurrentMihomoVersion(executablePath: mihomoPath)
            await MainActor.run {
                self.mihomoVersion = version
            }

            // Check for updates
            let downloader = MihomoDownloader()
            if let update = await downloader.checkForUpdate(currentVersion: version, channel: mihomoChannel) {
                await MainActor.run {
                    self.availableUpdate = update
                    self.mihomoDownloadError = nil
                }
            }
        }

        // Install mihomo to system path via helper (needed for privileged TUN mode)
        await installMihomoToSystemPath()
    }

    /// Copies the user-space mihomo binary to the system path via the XPC helper.
    /// The helper runs as root and can write to /Library/Application Support/Riptide/mihomo.
    private func installMihomoToSystemPath() async {
        guard helperInstalled else { return }

        let paths = MihomoPaths()
        let userBinaryPath = paths.executable

        guard FileManager.default.isExecutableFile(atPath: userBinaryPath) else {
            return
        }

        if let error = await mihomoManager.helperConnection.installMihomo(binaryPath: userBinaryPath) {
            // Non-fatal: binary may already be installed and up-to-date
            print("[AppViewModel] installMihomoToSystemPath: \(error.localizedDescription)")
        }

    }

    /// Downloads the latest mihomo version.
    public func downloadLatestMihomo(channel: MihomoDownloader.Channel? = nil) async {
        let effectiveChannel = channel ?? mihomoChannel

        await MainActor.run {
            isDownloadingMihomo = true
            mihomoDownloadProgress = 0
            mihomoDownloadError = nil
        }

        defer {
            Task { @MainActor in
                isDownloadingMihomo = false
            }
        }

        do {
            let downloader = MihomoDownloader(progressDelegate: self)
            let downloadedPath = try await downloader.downloadLatest(channel: effectiveChannel)

            // Replace current kernel
            try replaceCurrentMihomo(with: downloadedPath)

            // Update version info
            let paths = MihomoPaths()
            let mihomoPath = paths.baseDirectory.appendingPathComponent("mihomo").path
            let newVersion = getCurrentMihomoVersion(executablePath: mihomoPath)

            await MainActor.run {
                mihomoVersion = newVersion
                availableUpdate = nil
                mihomoDownloadProgress = 1.0
            }
        } catch {
            await MainActor.run {
                mihomoDownloadError = error.localizedDescription
            }
        }
    }

    /// Switches to a specific mihomo version.
    public func switchMihomoVersion(to version: String) async {
        // 1. Stop current proxy if running
        if tunnelState == .running {
            await stop()
        }

        // 2. Check if version is already downloaded
        let downloader = MihomoDownloader()
        if let existingPath = downloader.pathForVersion(version) {
            do {
                try replaceCurrentMihomo(with: existingPath)

                let paths = MihomoPaths()
                let mihomoPath = paths.baseDirectory.appendingPathComponent("mihomo").path
                let currentVersion = getCurrentMihomoVersion(executablePath: mihomoPath)

                await MainActor.run {
                    mihomoVersion = currentVersion
                    availableUpdate = nil
                }
            } catch {
                await MainActor.run {
                    mihomoDownloadError = error.localizedDescription
                }
            }
            return
        }

        // 3. Download the specified version
        await MainActor.run {
            isDownloadingMihomo = true
            mihomoDownloadProgress = 0
        }

        defer {
            Task { @MainActor in
                isDownloadingMihomo = false
            }
        }

        do {
            let downloadedPath = try await downloader.downloadVersion(version)
            try replaceCurrentMihomo(with: downloadedPath)

            let paths = MihomoPaths()
            let mihomoPath = paths.baseDirectory.appendingPathComponent("mihomo").path
            let currentVersion = getCurrentMihomoVersion(executablePath: mihomoPath)

            await MainActor.run {
                mihomoVersion = currentVersion
                availableUpdate = nil
            }
        } catch {
            await MainActor.run {
                mihomoDownloadError = error.localizedDescription
            }
        }
    }

    /// Lists all locally available mihomo versions.
    public func listLocalMihomoVersions() -> [String] {
        let downloader = MihomoDownloader()
        return downloader.listLocalVersions()
    }

    // MARK: - URL Scheme Support
    //
    // Properties and methods below are entry points used by
    // `URLSchemeHandler` to route `riptide://...` commands delivered by
    // LaunchServices. They are intentionally minimal — they delegate to
    // existing runtime APIs rather than introducing new orchestration.

    /// URL string pre-filled into the import dialog when a
    /// `riptide://import?url=...` command is delivered. The UI watches this
    /// property and clears it after consumption.
    public var pendingImportURL: String?

    /// Last error from URL-scheme routing (e.g. unrecognized URL, missing
    /// group). Distinct from `lastError` so URL failures don't pollute the
    /// proxy-runner error stream.
    public var urlSchemeError: String?

    /// Activates the proxy group with the given id and selects its first
    /// available node. Fails explicitly (via `urlSchemeError`) if the group
    /// is not present in the active profile — no silent fallback.
    public func selectGroup(named name: String) async {
        guard let profile = activeProfile else {
            urlSchemeError = "Cannot switch group: no active profile"
            return
        }
        guard let group = profile.config.proxyGroups.first(where: { $0.id == name }) else {
            urlSchemeError = "Proxy group '\(name)' not found"
            return
        }
        guard let firstNode = group.proxies.first else {
            urlSchemeError = "Proxy group '\(name)' has no nodes"
            return
        }
        await selectProxy(groupID: group.id, nodeName: firstNode)
    }

    /// Selects a node by name in whichever group contains it. Fails
    /// explicitly if the node is not present in the active profile.
    public func selectNode(named name: String) async {
        guard let profile = activeProfile else {
            urlSchemeError = "Cannot select node: no active profile"
            return
        }
        guard let group = profile.config.proxyGroups.first(where: { $0.proxies.contains(name) }) else {
            urlSchemeError = "Node '\(name)' not found in any group"
            return
        }
        await selectProxy(groupID: group.id, nodeName: name)
    }

    /// Switches the connection mode from a URL value. Accepts
    /// `"tun"`, `"system"`, and `"off"`. If the tunnel is currently running
    /// and a non-`off` value is given, the runtime is restarted in the new
    /// mode. Unknown values set `urlSchemeError` and are otherwise ignored.
    public func setMode(fromString value: String) async {
        let normalized = value.lowercased()
        let wasRunning = tunnelState == .running
        switch normalized {
        case "tun":
            connectionMode = .tun
        case "system":
            connectionMode = .systemProxy
        case "off":
            if wasRunning {
                await stop()
            }
            return
        default:
            urlSchemeError = "Unknown mode '\(value)' (expected: tun, system, off)"
            return
        }
        if wasRunning {
            await stop()
            await start()
        }
    }

    /// Generates a diagnostic report from the runtime and stores it in
    /// `lastError` for now (a dedicated diagnostics sheet can be wired up
    /// later by the UI layer). Returns the JSON-encoded report.
    @discardableResult
    public func runDiagnostics() async -> String {
        let report = await modeCoordinator.generateDiagnosticReport()
        // Surface a concise one-line summary so the UI shows something even
        // before a dedicated diagnostics sheet is implemented.
        let summary = "diagnostics: mihomo=\(report.mihomoRunning ? "running" : "stopped")"
        lastError = summary
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(report))
            .flatMap { String(data: $0, encoding: .utf8) } ?? summary
    }
}

// MARK: - MihomoDownloadProgressDelegate

extension AppViewModel: MihomoDownloadProgressDelegate {
    nonisolated public func downloadProgress(_ bytesDownloaded: Int64, totalBytes: Int64) {
        guard totalBytes > 0 else { return }
        let progress = Double(bytesDownloaded) / Double(totalBytes)
        Task { @MainActor in
            self.mihomoDownloadProgress = min(max(progress, 0.0), 1.0)
        }
    }
}
// swiftlint:enable file_length type_body_length
