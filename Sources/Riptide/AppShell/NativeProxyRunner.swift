import Foundation
import Network

/// NativeProxyRunner provides a complete, standalone native Swift proxy server
/// that operates independently of the mihomo sidecar.
///
/// It wires together the full Riptide library stack:
/// - `LiveTunnelRuntime` for connection lifecycle and rule-based routing
/// - `ProxyConnector` for protocol-level proxy handshakes
/// - `LocalHTTPConnectProxyServer` as the local ingress point
/// - `ExternalController` / `WebSocketExternalController` for REST + WS API
/// - `HealthChecker` for proxy latency measurement and group selection
///
/// This enables Riptide to function as a **pure Swift proxy client** without
/// requiring the Go-based mihomo binary.
public actor NativeProxyRunner {
    public enum State: Sendable {
        case stopped
        case starting
        case running(endpoint: LocalProxyEndpoint, apiEndpoint: String, wsEndpoint: String)
        case stopping
        case failed(String)
    }

    private let config: RiptideConfig
    private let geoIPResolver: GeoIPResolver
    private let geoSiteResolver: GeoSiteResolver?
    private let asnResolver: ASNResolver?

    private var runtime: LiveTunnelRuntime?
    private var localProxy: LocalHTTPConnectProxyServer?
    private var externalController: ExternalController?
    private var webSocketController: WebSocketExternalController?
    private var healthChecker: HealthChecker
    private var groupSelector: GroupSelector
    private var state: State = .stopped

    /// Callback for state changes
    public var onStateChanged: ((State) -> Void)?

    public init(
        config: RiptideConfig,
        geoIPResolver: GeoIPResolver = .none,
        geoSiteResolver: GeoSiteResolver? = nil,
        asnResolver: ASNResolver? = nil
    ) {
        self.config = config
        self.geoIPResolver = geoIPResolver
        self.geoSiteResolver = geoSiteResolver
        self.asnResolver = asnResolver

        // Initialize with default health checker (no connector yet)
        self.healthChecker = HealthChecker()
        self.groupSelector = GroupSelector(healthChecker: HealthChecker())
    }

    /// Start the native proxy stack.
    ///
    /// - Parameters:
    ///   - proxyPort: The local HTTP CONNECT proxy port (default 7890)
    ///   - apiPort: The REST API port (default 9090)
    ///   - wsPort: The WebSocket API port (default 9091)
    ///   - enableHealthCheck: Whether to enable periodic health checks
    ///   - healthCheckInterval: Interval between health checks (default 30 seconds)
    public func start(
        proxyPort: UInt16 = 7890,
        apiPort: UInt16 = 9090,
        wsPort: UInt16 = 9091,
        enableHealthCheck: Bool = true,
        healthCheckInterval: Duration = .seconds(30)
    ) async throws {
        guard case .stopped = state else {
            throw NativeProxyError.alreadyRunning
        }
        state = .starting

        do {
            // 1. Create the tunnel runtime with proxy connector
            let proxyDialer = TCPTransportDialer()
            let directDialer = DirectTransportDialer()
            let dnsPipeline = DNSPipeline(dnsPolicy: config.dnsPolicy)

            let runtime = LiveTunnelRuntime(
                proxyDialer: proxyDialer,
                directDialer: directDialer,
                geoIPResolver: geoIPResolver,
                geoSiteResolver: geoSiteResolver,
                asnResolver: asnResolver,
                dnsPipeline: dnsPipeline
            )
            self.runtime = runtime

            // 2. Start the runtime with the current profile
            let profile = TunnelProfile(name: "native-profile", config: config)
            try await runtime.start(profile: profile)

            // 3. Set up the health checker with a real connector
            let dialerSelector = DialerSelector.defaultSelector
            let connectionPool = TransportConnectionPool(dialer: proxyDialer, dialerSelector: dialerSelector)
            let connector = ProxyConnector(pool: connectionPool)
            let newHealthChecker = HealthChecker(connector: connector)
            self.healthChecker = newHealthChecker
            self.groupSelector = GroupSelector(healthChecker: newHealthChecker)

            // 4. Start periodic health checks for all proxy nodes
            if enableHealthCheck && !config.proxies.isEmpty {
                Task {
                    await newHealthChecker.startPeriodicCheck(nodes: config.proxies, interval: healthCheckInterval)
                }
            }

            // 5. Start the local HTTP CONNECT proxy server (local ingress)
            let localProxy = LocalHTTPConnectProxyServer(runtime: runtime)
            let endpoint = try await localProxy.start(host: "127.0.0.1", port: proxyPort)
            self.localProxy = localProxy

            // 6. Start the REST API controller
            let externalController = ExternalController(runtime: runtime, config: config)
            let apiEndpoint = try await externalController.start(host: "127.0.0.1", port: apiPort)
            self.externalController = externalController

            // 7. Start the WebSocket controller
            let wsController = WebSocketExternalController(
                runtime: runtime,
                config: config,
                healthChecker: newHealthChecker
            )
            let wsEndpoint = try await wsController.start(host: "127.0.0.1", port: wsPort)
            self.webSocketController = wsController

            // 8. Update state to running
            state = .running(endpoint: endpoint, apiEndpoint: apiEndpoint, wsEndpoint: wsEndpoint)
            onStateChanged?(state)

        } catch {
            state = .failed(String(describing: error))
            onStateChanged?(state)
            throw error
        }
    }

    /// Stop the native proxy stack.
    public func stop() async throws {
        guard case .running = state else { return }
        state = .stopping

        // Stop health checker
        await healthChecker.stop()

        // Stop local proxy server
        if let localProxy {
            await localProxy.stop()
        }

        // Stop external controllers
        if let ec = externalController {
            Task.detached { await ec.stop() }
        }
        if let wsc = webSocketController {
            await wsc.stop()
        }

        // Stop runtime
        if let runtime {
            try await runtime.stop()
        }

        state = .stopped
        onStateChanged?(state)
    }

    /// Get the current state of the runner.
    public func currentState() -> State {
        state
    }

    /// Get the current health checker.
    public func getHealthChecker() -> HealthChecker {
        healthChecker
    }

    /// Get the current group selector.
    public func getGroupSelector() -> GroupSelector {
        groupSelector
    }

    /// Get the current runtime status.
    public func getStatus() async -> TunnelRuntimeStatus? {
        guard let runtime else { return nil }
        return await runtime.status()
    }

    /// Test the delay of a specific proxy node.
    public func testProxyDelay(node: ProxyNode, testURL: URL = URL(string: "http://www.gstatic.com/generate_204")!, timeout: Duration = .seconds(5)) async -> HealthResult {
        await healthChecker.check(node: node, testURL: testURL, timeout: timeout)
    }

    /// Get all current health results.
    public func getAllHealthResults() async -> [String: HealthResult] {
        await healthChecker.allResults()
    }

    /// Get the best proxy for a group based on health checks.
    public func getBestProxy(for group: String) async -> String? {
        guard let groupConfig = config.proxyGroups.first(where: { $0.id == group }) else {
            return nil
        }

        let proxies = config.proxies.filter { groupConfig.proxies.contains($0.name) }
        let proxyGroup = ProxyGroup(id: group, kind: groupConfig.kind, proxies: groupConfig.proxies)
        let selected = await groupSelector.select(group: proxyGroup, proxies: proxies)
        return selected?.name
    }
}

// MARK: - Errors

public enum NativeProxyError: Error, Equatable, Sendable {
    case alreadyRunning
    case groupNotFound(String)
    case unsupportedGroupKind(ProxyGroupKind)
    case proxyNotInGroup(String, String)
}
