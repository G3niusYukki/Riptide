import Foundation
import Observation
import AppKit
import Riptide

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
    public internal(set) var profiles: [Profile] = []
    public internal(set) var activeProfile: Profile?
    public internal(set) var subscriptions: [SubscriptionDisplay] = []

    // Proxies
    public internal(set) var proxyGroups: [ProxyGroupDisplay] = []
    public internal(set) var allProxies: [ProxyNodeDisplay] = []
    private var proxyDelays: [String: Int] = [:]  // proxy name -> delay ms

    /// Per-group user-customized node order. Persisted to UserDefaults so
    /// drag/drop rearrangements survive app relaunches. Maps groupID to an
    /// ordered list of node names. Nodes not present in the list (or new
    /// nodes from a refreshed profile) are appended at the end.
    public internal(set) var nodeOrder: [String: [String]] = [:]

    // URL Scheme — stored properties must live in the main type body
    public var pendingImportURL: String?
    public var urlSchemeError: String?

    // Traffic
    public internal(set) var currentSpeedUp: Int64 = 0
    public internal(set) var currentSpeedDown: Int64 = 0
    public internal(set) var totalTrafficUp: Int64 = 0
    public internal(set) var totalTrafficDown: Int64 = 0
    public internal(set) var activeConnections: [ConnectionInfo] = []

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
    public internal(set) var lastError: String?
    /// Warning shown when system proxy guard is unavailable (no helper).
    public private(set) var guardUnavailableWarning: String?

    // Mihomo core management
    public internal(set) var mihomoVersion: String = ""
    public internal(set) var availableUpdate: MihomoDownloader.UpdateInfo?
    public internal(set) var isDownloadingMihomo: Bool = false
    public internal(set) var mihomoDownloadProgress: Double = 0
    public var mihomoChannel: MihomoDownloader.Channel = .stable
    public internal(set) var mihomoDownloadError: String?

    // MARK: - Window Reference
    public weak var mainWindow: NSWindow?

    // MARK: - Logbook

    /// Persistent diagnostic Logbook (store + writer + view model trio).
    /// Wired here so business modules can later receive the writer via DI.
    public let logbook: LogbookContainer

    // MARK: - Private

    private let mihomoManager: any MihomoRuntimeManaging
    internal let modeCoordinator: ModeCoordinator
    private let importService: ConfigImportService
    internal let subscriptionManager: SubscriptionManager
    private let profileStore: ProfileStore
    private let overrideStore: OverrideStore
    internal var statsTask: Task<Void, Never>?
    internal var subscriptionScheduler: SubscriptionUpdateScheduler?

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
        // Restore any persisted drag/drop node order from a prior session.
        loadNodeOrder()
        let writer = self.logbook.writer
        Task {
            await self.modeCoordinator.setLogbookWriter(writer)
            await self.mihomoManager.setLogbookWriter(writer)
            await self.subscriptionManager.setLogbookWriter(writer)
            await self.overrideStore.setLogbookWriter(writer)
            await self.mihomoManager.helperConnection.setLogbookWriter(writer)
            // Clear a system proxy left pointing at our local port by a prior
            // crashed/force-quit session, so the user isn't stranded without internet.
            await cleanupStaleSystemProxy()
            await loadProfilesFromStore()

            await loadSubscriptionsFromBackend()
            await ensureSubscriptionProfiles()
            startSubscriptionScheduler()
            await checkMihomoOnLaunch()
        }
    }

    // MARK: - Stale System Proxy Cleanup

    /// At launch the engine is never running, so if the macOS system proxy still
    /// points at our local mixed port (6152), it is a leftover from a session that
    /// crashed or was force-quit without clearing it. Reset it so traffic flows.
    private func cleanupStaleSystemProxy() async {
        let controller = NetworksetupSystemProxyController()
        if await controller.activeHTTPProxyPort() == 6152 {
            try? await controller.disable()
        }
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
        guard let profile = activeProfile else {
            lastError = "No active profile selected"
            return
        }

        let runtimeMode: RuntimeMode = connectionMode == .tun ? .tun : .systemProxy

        // TUN mode pre-check: the standalone sing-box core must be locatable. It
        // runs as root via a launchd daemon (see TunDaemonController); the first
        // TUN start shows one administrator-password prompt to install that daemon.
        if runtimeMode == .tun && SingBoxBinaryLocator.locate() == nil {
            lastError = "TUN 模式需要 riptide-singbox 核心（打包缺失）。开发时先运行 Scripts/build-singbox-bin.sh。"
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

    // MARK: - Helpers

    internal func rebuildProxyGroupDisplays() {
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
