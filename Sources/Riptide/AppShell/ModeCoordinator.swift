import Foundation

/// Coordinates runtime mode transitions between system proxy and TUN,
/// using MihomoRuntimeManager as the underlying runtime.
/// Surfaces degraded-state recommendations when a mode fails to start.
public actor ModeCoordinator {
    private let mihomoManager: any MihomoRuntimeManaging
    private var activeMode: RuntimeMode
    private var eventBuffer: [RuntimeEvent]
    private var providerScheduler: ProviderUpdateScheduler?
    private var registeredProviders: [UUID: ProxyProviderConfig] = [:]

    private let maxEvents = 100

    public static let defaultHTTPPort: Int = 6152

    public init(mihomoManager: any MihomoRuntimeManaging) {
        self.mihomoManager = mihomoManager
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

        do {
            try await mihomoManager.start(mode: mode, profile: profile)
            activeMode = mode
            emit(.modeChanged(mode))
            emit(.stateChanged(.running))

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
        guard let scheduler = providerScheduler,
              let config = registeredProviders[id] else { return }

        // Create a temporary provider to refresh
        let provider = ProxyProvider(config: config)
        try? await provider.refresh()
    }

    private func emit(_ event: RuntimeEvent) {
        eventBuffer.append(event)
        if eventBuffer.count > maxEvents {
            eventBuffer.removeFirst()
        }
    }
}
