import Foundation
import Network

/// Coordinates runtime mode transitions between system proxy and TUN,
/// using MihomoRuntimeManager as the underlying runtime.
/// Surfaces degraded-state recommendations when a mode fails to start.
public actor ModeCoordinator {
    private let mihomoManager: any MihomoRuntimeManaging
    private let systemProxyController: (any SystemProxyControlling)?
    private var activeMode: RuntimeMode
    private var eventBuffer: [RuntimeEvent]
    private var providerScheduler: ProviderUpdateScheduler?
    private var registeredProviders: [UUID: ProxyProviderConfig] = [:]
    private var systemProxyGuard: SystemProxyGuard?
    private var systemProxyMonitor: SystemProxyMonitor?
    private var healthCheckTask: Task<Void, Never>?
    private var healthResults: [String: HealthResult] = [:]
    private var sleepWakeObserver: SleepWakeObserver?
    private let pathMonitor = NWPathMonitor()
    private var pathMonitorQueue: DispatchQueue?

    private let maxEvents = 100

    public static let defaultHTTPPort: Int = 6152

    public init(mihomoManager: any MihomoRuntimeManaging, systemProxyController: (any SystemProxyControlling)? = nil) {
        self.mihomoManager = mihomoManager
        self.systemProxyController = systemProxyController
        self.activeMode = .systemProxy
        self.eventBuffer = []
    }

    public func start(mode: RuntimeMode, profile: TunnelProfile?) async throws {
        guard let profile else {
            let msg = "Mode requires a profile"
            emit(.degraded(mode, msg))
            emit(.error(RuntimeErrorSnapshot(code: "E_NO_PROFILE", message: msg)))
            throw SystemProxyError.unknown("no profile for mode")
        }

        // Wire event handler so mihomoRuntime can emit events to this coordinator
        await mihomoManager.setEventHandler({ [weak self] event in
            Task { await self?.emit(event) }
        })

        do {
            try await mihomoManager.start(mode: mode, profile: profile)
            activeMode = mode
            emit(.modeChanged(mode))
            emit(.stateChanged(.running))

            // Start system proxy guard if in system proxy mode
            if mode == .systemProxy {
                await startSystemProxyGuard()
            }

            // Start periodic health checks for proxies
            startHealthChecks(proxies: profile.config.proxies)

            // Start sleep/wake observer for recovery after Mac sleep/wake cycles
            startSleepWakeObserver()

            // Start network path monitoring for WiFi/Ethernet change recovery
            startNetworkMonitoring()

            // Initialize Provider scheduler
            providerScheduler = ProviderUpdateScheduler { [weak self] providerID in
                await self?.updateProvider(id: providerID)
            }

            // Register and schedule proxy providers from profile config
            await registerProviders(from: profile)
        } catch {
            emit(.degraded(mode, "\(mode) start failed: \(String(describing: error))"))
            emit(.error(RuntimeErrorSnapshot(
                code: "E_MODE_FAILED",
                message: String(describing: error)
            )))
            throw error
        }
    }

    public func stop() async throws {
        // Stop sleep/wake observer
        stopSleepWakeObserver()

        // Stop network path monitoring
        stopNetworkMonitoring()

        // Stop health checks
        stopHealthChecks()

        // Stop system proxy guard first
        await stopSystemProxyGuard()

        // Stop Provider scheduler
        await providerScheduler?.stopAll()
        providerScheduler = nil
        registeredProviders.removeAll()

        do {
            try await mihomoManager.stop()
            emit(.stateChanged(.stopped))
        } catch {
            emit(.error(RuntimeErrorSnapshot(
                code: "E_STOP_FAILED",
                message: String(describing: error)
            )))
            throw error
        }
    }

    /// Atomically switches from the current mode to a new mode.
    /// Ensures the previous mode is fully stopped before starting the new one.
    public func switchMode(to newMode: RuntimeMode, profile: TunnelProfile?) async throws {
        // 1. Stop current mode completely
        if await mihomoManager.isRunning {
            try await stop()
        }

        // 2. Brief pause to let OS clean up network interfaces
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // 3. Start new mode
        try await start(mode: newMode, profile: profile)
    }

    /// The current runtime mode.
    public func currentMode() -> RuntimeMode {
        activeMode
    }

    /// Recent runtime events emitted by this coordinator.
    public func recentEvents() -> [RuntimeEvent] {
        eventBuffer
    }

    /// Whether the helper tool is installed (required for both modes with mihomo).
    public func isHelperInstalled() async -> Bool {
        await mihomoManager.helperConnection.isHelperInstalled()
    }

    /// Generates a structured diagnostic report collecting state from all runtime
    /// subcomponents. Useful for debugging user-reported issues — the report can
    /// be serialized as JSON and shared.
    public func generateDiagnosticReport() async -> DiagnosticReport {
        let helperInstalled = await mihomoManager.helperConnection.isHelperInstalled()
        let mihomoRunning = await mihomoManager.isRunning

        // Mihomo version (best-effort, uses standard install paths)
        let mihomoVersion: String? = {
            let path = MihomoPaths().executable
            let version = getCurrentMihomoVersion(executablePath: path)
            return version != "unknown" ? version : nil
        }()

        // System proxy state
        let systemProxyReport: DiagnosticReport.SystemProxyReport?
        if activeMode == .systemProxy {
            systemProxyReport = DiagnosticReport.SystemProxyReport(
                enabled: systemProxyGuard != nil,
                httpPort: ModeCoordinator.defaultHTTPPort,
                socksPort: nil,
                guarded: systemProxyGuard != nil
            )
        } else {
            systemProxyReport = nil
        }

        // DNS config from current profile
        let dnsReport: DiagnosticReport.DNSReport?
        if let profile = await mihomoManager.currentProfile {
            let policy = profile.config.dnsPolicy
            dnsReport = DiagnosticReport.DNSReport(
                mode: policy.fakeIPEnabled ? "fakeIP" : "realIP",
                fakeIPCIDR: policy.fakeIPEnabled ? policy.fakeIPCIDR : nil,
                remoteServers: policy.primaryResolvers.map(\.address),
                doHEndpoints: policy.primaryResolvers.compactMap { $0.kind == .doh ? $0.dohURL : nil },
                cacheEnabled: true
            )
        } else {
            dnsReport = nil
        }

        // Recent errors from event buffer
        let recentErrors: [DiagnosticReport.DiagnosticErrorEntry] = eventBuffer.compactMap { event in
            if case .error(let snapshot) = event {
                return DiagnosticReport.DiagnosticErrorEntry(
                    code: snapshot.code,
                    message: snapshot.message,
                    timestamp: snapshot.timestamp
                )
            }
            return nil
        }

        // Active connections
        let activeConnections = (try? await mihomoManager.getConnections().count) ?? 0

        // Traffic
        let traffic = (try? await mihomoManager.getTraffic()) ?? (up: 0, down: 0)

        // VPN status (TUN mode only)
        let vpnStatus: String? = activeMode == .tun ? (mihomoRunning ? "connected" : "disconnected") : nil

        let collector = DiagnosticCollector()
        return collector.buildReport(
            mode: activeMode,
            mihomoRunning: mihomoRunning,
            mihomoVersion: mihomoVersion != "unknown" ? mihomoVersion : nil,
            vpnStatus: vpnStatus,
            systemProxy: systemProxyReport,
            dnsConfig: dnsReport,
            recentErrors: recentErrors,
            activeConnections: activeConnections,
            bytesUp: UInt64(traffic.up),
            bytesDown: UInt64(traffic.down),
            uptimeSeconds: nil, // uptime tracking not yet implemented
            helperInstalled: helperInstalled
        )
    }

    /// Gets traffic statistics from the mihomo runtime.
    public func getTraffic() async -> (up: Int64, down: Int64) {
        do {
            let traffic = try await mihomoManager.getTraffic()
            return (Int64(traffic.up), Int64(traffic.down))
        } catch {
            return (0, 0)
        }
    }

    /// Gets active connections from the mihomo runtime.
    public func getConnections() async -> [(id: String, host: String, network: String, proxy: String, upload: Int, download: Int)] {
        do {
            let connections = try await mihomoManager.getConnections()
            return connections.map { conn in
                (
                    id: conn.id,
                    host: conn.metadata.host ?? conn.metadata.destinationIP ?? "unknown",
                    network: conn.metadata.network.uppercased(),
                    proxy: conn.chains.last ?? "Direct",
                    upload: conn.upload,
                    download: conn.download
                )
            }
        } catch {
            return []
        }
    }

    /// Selects a specific proxy in a proxy group.
    public func selectProxy(groupID: String, nodeName: String) async {
        do {
            try await mihomoManager.switchProxy(to: nodeName)
        } catch {
            // Silently fail — the mihomo API may not support named groups
        }
    }

    /// Closes a specific connection.
    public func closeConnection(id: String) async {
        try? await mihomoManager.closeConnection(id: id)
    }

    /// Closes all connections.
    public func closeAllConnections() async {
        try? await mihomoManager.closeAllConnections()
    }

    /// Gets recent log entries.
    public func getLogs(level: String = "debug", lines: Int = 200) async -> [String] {
        do {
            return try await mihomoManager.getLogs(level: level, lines: lines)
        } catch {
            return []
        }
    }

    /// Tests the delay of a proxy.
    /// - Parameters:
    ///   - proxyName: The name of the proxy to test
    ///   - url: Optional test URL
    ///   - timeout: Timeout in milliseconds
    /// - Returns: The measured delay in milliseconds, or nil if test failed
    public func testProxyDelay(proxyName: String, url: String? = nil, timeout: Int = 5000) async -> Int? {
        do {
            let delay = try await mihomoManager.testProxyDelay(name: proxyName, url: url, timeout: timeout)
            return delay
        } catch {
            return nil
        }
    }

    // MARK: - Provider Management

    /// Registers proxy providers from the tunnel profile and schedules updates.
    private func registerProviders(from profile: TunnelProfile) async {
        guard let scheduler = providerScheduler else { return }

        for (name, config) in profile.config.proxyProviders {
            let id = UUID(uuidString: name.hashValue.description) ?? UUID()
            registeredProviders[id] = config

            // Schedule updates if interval is specified
            if let interval = config.interval, interval > 0 {
                await scheduler.schedule(providerID: id, interval: TimeInterval(interval))
            }
        }
    }

    /// Updates a specific provider by ID.
    private func updateProvider(id: UUID) async {
        guard providerScheduler != nil,
              let config = registeredProviders[id] else { return }

        // Create a temporary provider to refresh
        let provider = ProxyProvider(config: config)
        try? await provider.refresh()
    }

    // MARK: - System Proxy Guard

    /// Whether the system proxy guard is currently active.
    public func isSystemProxyGuarded() -> Bool {
        systemProxyGuard != nil
    }

    /// Starts the system proxy guard and monitor for system proxy mode.
    private func startSystemProxyGuard() async {
        guard let controller = await resolveSystemProxyController() else {
            emit(.guardUnavailable(reason:
                "System proxy guard unavailable: privileged helper not installed. "
                + "Your proxy settings will not auto-restore if changed externally. "
                + "Consider switching to TUN mode for full traffic interception."
            ))
            return
        }
        let proxyGuard = SystemProxyGuard(controller: controller)
        do {
            try await proxyGuard.enable(expectedHTTPPort: ModeCoordinator.defaultHTTPPort, expectedSOCKSPort: nil)
            let monitor = SystemProxyMonitor(controller: controller)
            await monitor.start(interval: 5.0, guard: proxyGuard)
            self.systemProxyGuard = proxyGuard
            self.systemProxyMonitor = monitor
        } catch {
            // Guard setup failure is non-fatal — log and continue
            emit(.error(RuntimeErrorSnapshot(
                code: "E_GUARD_FAILED",
                message: "System proxy guard setup failed: \(error.localizedDescription)"
            )))
        }
    }

    /// Stops the system proxy guard and monitor.
    private func stopSystemProxyGuard() async {
        await systemProxyMonitor?.stop()
        systemProxyMonitor = nil
        await systemProxyGuard?.disable()
        systemProxyGuard = nil
    }

    // MARK: - Sleep/Wake Recovery

    /// Starts the sleep/wake observer to handle macOS sleep/wake cycles.
    /// On wake, triggers recovery: verify mihomo sidecar health, flush DNS cache,
    /// and emit a state change event so the UI can reflect recovery status.
    private func startSleepWakeObserver() {
        let observer = SleepWakeObserver()
        observer.start(
            onSleep: { [weak self] in
                Task { await self?.prepareForSleep() }
            },
            onWake: { [weak self] in
                Task { await self?.recoverFromWake() }
            }
        )
        sleepWakeObserver = observer
    }

    /// Stops the sleep/wake observer and releases its resources.
    private func stopSleepWakeObserver() {
        sleepWakeObserver?.stop()
        sleepWakeObserver = nil
    }

    /// Called when the system is about to sleep.
    /// Emits a state change event so the UI can reflect that the runtime
    /// will be suspended. No aggressive teardown is performed — mihomo
    /// connections will naturally time out during sleep and be re-established on wake.
    private func prepareForSleep() async {
        emit(.degraded(activeMode, "system_sleep"))
    }

    /// Called when the system wakes from sleep.
    /// Performs a multi-step recovery to restore the runtime:
    /// 1. Verify mihomo sidecar is still alive via health check
    /// 2. Flush DNS cache to clear stale entries accumulated during sleep
    /// 3. Emit recovery status events for UI feedback
    ///
    /// If the sidecar has crashed during sleep, the existing TUN monitoring
    /// in MihomoRuntimeManager will detect this independently and trigger
    /// its own recovery cycle (up to 3 retries).
    private func recoverFromWake() async {
        guard await mihomoManager.isRunning else {
            // Runtime was stopped while sleeping — nothing to recover
            return
        }

        emit(.degraded(activeMode, "wake_recovery_started"))

        // 1. Health check — verify mihomo API is responsive
        let healthy: Bool
        do {
            _ = try await mihomoManager.getTraffic()
            healthy = true
        } catch {
            healthy = false
        }

        if healthy {
            // DNS cache flush is handled internally by MihomoRuntimeManager
            // during its TUN monitoring cycle (dscacheutil + DNSResponder restart).
            // Stale cache entries will also expire on their own TTL.

            emit(.stateChanged(.running))
        } else {
            // Sidecar is unresponsive — the TUN monitor will attempt recovery.
            // Emit a degraded event so the UI can show a warning.
            emit(.degraded(activeMode, "wake_recovery_sidecar_unresponsive"))
        }
    }

    // MARK: - Network Path Monitoring

    /// Starts NWPathMonitor to detect network interface changes (WiFi ↔ Ethernet,
    /// VPN interface up/down, etc.). When a change is detected, triggers a
    /// lightweight recovery: verifies mihomo sidecar health and emits status events.
    ///
    /// This works alongside the existing TUN monitoring in MihomoRuntimeManager:
    /// - NWPathMonitor detects interface-level changes (instant)
    /// - TUN monitor polls the mihomo API every 10s (periodic safety net)
    private func startNetworkMonitoring() {
        let queue = DispatchQueue(label: "com.riptide.network-monitor")
        pathMonitorQueue = queue
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.handleNetworkPathChange(path) }
        }
        pathMonitor.start(queue: queue)
    }

    /// Stops network path monitoring.
    private func stopNetworkMonitoring() {
        pathMonitor.cancel()
        pathMonitorQueue = nil
    }

    /// Called when the network path changes (interface up/down, route change).
    /// On recovery (status becomes satisfied after being unsatisfied), performs
    /// a health check against the mihomo API to ensure the sidecar is responsive.
    ///
    /// Debounce: if the path flip-flops rapidly, each change is handled independently
    /// but the health check is a lightweight operation (~HTTP GET to localhost).
    private func handleNetworkPathChange(_ path: NWPath) async {
        guard await mihomoManager.isRunning else { return }

        if path.status == .satisfied {
            // Network is available — verify sidecar health
            let healthy: Bool
            do {
                _ = try await mihomoManager.getTraffic()
                healthy = true
            } catch {
                healthy = false
            }

            if healthy {
                emit(.stateChanged(.running))
            } else {
                // Sidecar unresponsive — TUN monitor will attempt recovery
                emit(.degraded(activeMode, "network_change_sidecar_unresponsive"))
            }
        } else {
            // Network is unavailable — emit degraded status
            emit(.degraded(activeMode, "network_unavailable"))
        }
    }

    /// Resolves the system proxy controller, using the injected one or creating a default.
    /// Returns nil if no controller is available (e.g., in test environments without a helper).
    private func resolveSystemProxyController() async -> (any SystemProxyControlling)? {
        if let controller = systemProxyController {
            return controller
        }
        // Only create a real controller if the helper is installed
        let helperInstalled = await mihomoManager.helperConnection.isHelperInstalled()
        guard helperInstalled else { return nil }
        return MacOSSystemProxyController(helperConnection: await mihomoManager.helperConnection)
    }

    // MARK: - Health Checks

    /// Periodically tests proxy delays via the mihomo API.
    /// Runs every 5 minutes for all proxies in the current profile.
    private func startHealthChecks(proxies: [ProxyNode], interval: Duration = .seconds(300)) {
        guard !proxies.isEmpty else { return }
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.testAllProxies(proxies: proxies)
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func stopHealthChecks() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        healthResults.removeAll()
    }

    /// Tests delay for all proxies and stores results.
    public func testAllProxies(proxies: [ProxyNode]) async {
        await withTaskGroup(of: Void.self) { group in
            for proxy in proxies {
                group.addTask { [weak self] in
                    guard let self else { return }
                    let delay = await self.testProxyDelay(proxyName: proxy.name)
                    let result = HealthResult(
                        nodeName: proxy.name,
                        latency: delay,
                        alive: delay != nil
                    )
                    await self.storeHealthResult(result)
                }
            }
        }
    }

    /// Stores a health check result.
    private func storeHealthResult(_ result: HealthResult) {
        healthResults[result.nodeName] = result
    }

    /// Returns the health result for a specific proxy.
    public func healthResult(for name: String) -> HealthResult? {
        healthResults[name]
    }

    /// Returns all health check results.
    public func allHealthResults() -> [String: HealthResult] {
        healthResults
    }

    private func emit(_ event: RuntimeEvent) {
        eventBuffer.append(event)
        if eventBuffer.count > maxEvents {
            eventBuffer.removeFirst()
        }
    }
}
