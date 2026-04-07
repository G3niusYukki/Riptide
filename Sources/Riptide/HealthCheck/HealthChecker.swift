import Foundation

public struct HealthResult: Sendable, Equatable {
    public let nodeName: String
    public let latency: Int?
    public let alive: Bool
    public let error: String?

    public init(nodeName: String, latency: Int? = nil, alive: Bool, error: String? = nil) {
        self.nodeName = nodeName
        self.latency = latency
        self.alive = alive
        self.error = error
    }
}

// MARK: - HTTP helpers for building requests through a proxy tunnel

private func buildHTTPRequest(targetHost: String, targetPort: Int, testPath: String, timeout: TimeInterval) -> Data {
    let hostHeader = targetPort == 80 || targetPort == 443 ? targetHost : "\(targetHost):\(targetPort)"
    let request = "HEAD \(testPath) HTTP/1.1\r\n"
        + "Host: \(hostHeader)\r\n"
        + "Connection: close\r\n"
        + "User-Agent: Riptide/1.0\r\n"
        + "\r\n"
    return Data(request.utf8)
}

private func parseHTTPStatus(_ data: Data) -> Int? {
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    // Expect "HTTP/1.x STATUS_CODE ..."
    let parts = text.split(separator: " ", maxSplits: 2)
    guard parts.count >= 2 else { return nil }
    return Int(parts[1])
}

/// A transport dialer that connects directly to a target server without proxy.
/// Used for health-check probes that need to reach a test URL directly.
private struct DirectToTargetDialer: TransportDialer {
    private let dialerSelector: DialerSelector

    init(dialerSelector: DialerSelector) {
        self.dialerSelector = dialerSelector
    }

    func openSession(to node: ProxyNode) async throws -> any TransportSession {
        // Create a synthetic node that points to the test URL's server
        // so the dialer selector picks the right transport (TCP/TLS/WS).
        let directNode = ProxyNode(
            name: "direct-probe",
            kind: node.kind, // keep kind for dialer selection hints (port, SNI, etc.)
            server: node.server,
            port: node.port,
            sni: node.sni,
            skipCertVerify: node.skipCertVerify,
            network: node.network,
            wsPath: node.wsPath,
            wsHost: node.wsHost
        )
        let dialer = dialerSelector.select(for: directNode)
        return try await dialer.openSession(to: directNode)
    }
}

/// HealthChecker that routes probe requests **through** the provided proxy node,
/// so that latency reflects the full proxy path (transport + protocol handshake).
///
/// When a `ProxyConnector` is provided, the health check establishes a real
/// connection through the proxy, sends an HTTP HEAD request to the test URL,
/// and measures the round-trip time. This ensures that the reported latency
/// includes transport setup, protocol framing, and proxy server response time.
///
/// When no connector is available (backward compatibility), it falls back to
/// direct `URLSession` probes — these report latency for the direct path only.
public actor HealthChecker {
    private var results: [String: HealthResult]
    private var running: Bool = false
    private let connector: ProxyConnector?
    private let profileResolver: (@Sendable () async -> TunnelProfile)?

    /// Creates a HealthChecker that uses direct `URLSession` requests.
    /// This is the legacy behavior for backward compatibility.
    public init() {
        self.results = [:]
        self.connector = nil
        self.profileResolver = nil
    }

    /// Creates a HealthChecker that routes probes through a `ProxyConnector`,
    /// so that latency reflects the actual proxy path.
    ///
    /// - Parameters:
    ///   - connector: The proxy connector used to establish tunneled connections.
    ///   - profileResolver: Optional closure to resolve the current tunnel profile.
    ///     When provided, the checker uses the profile's proxy list to find the
    ///     actual `ProxyNode` by name during health checks.
    public init(connector: ProxyConnector, profileResolver: (@Sendable () async -> TunnelProfile)? = nil) {
        self.results = [:]
        self.connector = connector
        self.profileResolver = profileResolver
    }

    /// Check the reachability of testURL **through** the provided `ProxyNode`.
    ///
    /// When a `ProxyConnector` is available, this method:
    /// 1. Opens a transport session to the proxy server via the connector's pool
    /// 2. Completes the protocol handshake (SOCKS5, HTTP CONNECT, VMess, etc.)
    /// 3. Sends an HTTP HEAD request through the established proxy tunnel
    /// 4. Measures the full round-trip time through the proxy path
    ///
    /// Without a connector (legacy mode), it falls back to direct `URLSession` probes.
    public func check(node: ProxyNode, testURL: URL = URL(string: "http://www.gstatic.com/generate_204")!,
                      timeout: Duration = .seconds(5)) async -> HealthResult {
        // If we have a connector, route through the proxy
        if let connector {
            return await checkThroughProxy(connector: connector, node: node, testURL: testURL, timeout: timeout)
        }

        // Fallback: direct URLSession probe (legacy behavior)
        return await checkDirect(node: node, testURL: testURL, timeout: timeout)
    }

    /// Health check routed through the proxy connector.
    private func checkThroughProxy(
        connector: ProxyConnector,
        node: ProxyNode,
        testURL: URL,
        timeout: Duration
    ) async -> HealthResult {
        let start = ContinuousClock.now
        let timeoutInterval = timeout.components.seconds

        do {
            guard let host = testURL.host() else {
                let result = HealthResult(nodeName: node.name, alive: false, error: "Invalid test URL: missing host")
                results[node.name] = result
                return result
            }
            let port = testURL.port ?? 80

            let target = ConnectionTarget(host: host, port: port)
            let context = try await connector.connect(via: node, to: target)

            // Send HTTP HEAD request through the proxy tunnel
            let path = testURL.path.isEmpty ? "/" : testURL.path + (testURL.query.map { "?\($0)" } ?? "")
            let httpRequest = buildHTTPRequest(targetHost: host, targetPort: port, testPath: path, timeout: Double(timeoutInterval))

            // For Shadowsocks, use the encrypted stream; for others, use the raw session
            var statusCode: Int?
            if let ssStream = context.encryptedStream {
                try await ssStream.send(httpRequest)
                let responseData = try await ssStream.receive()
                statusCode = parseHTTPStatus(responseData)
            } else {
                try await context.connection.session.send(httpRequest)
                let responseData = try await context.connection.session.receive()
                statusCode = parseHTTPStatus(responseData)
            }
            let elapsed = ContinuousClock.now - start
            let ms = Int(elapsed.components.seconds * 1000)

            let alive = statusCode == 204 || (statusCode ?? 0) < 400

            // Close the probe connection (one-shot, not reusable)
            await connector.pool.discard(context.connection)

            let result = HealthResult(nodeName: node.name, latency: alive ? ms : nil, alive: alive,
                                      error: alive ? nil : "Unexpected status code: \(statusCode ?? -1)")
            results[node.name] = result
            return result
        } catch {
            let elapsed = ContinuousClock.now - start
            let ms = Int(elapsed.components.seconds * 1000)
            let result = HealthResult(nodeName: node.name, latency: nil, alive: false, error: String(describing: error))
            results[node.name] = result
            return result
        }
    }

    /// Direct health check without proxy routing (legacy fallback).
    private func checkDirect(node: ProxyNode, testURL: URL, timeout: Duration) async -> HealthResult {
        let start = ContinuousClock.now
        do {
            var request = URLRequest(url: testURL)
            request.httpMethod = "HEAD"
            request.timeoutInterval = Double(timeout.components.seconds)
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsed = ContinuousClock.now - start
            let ms = Int(elapsed.components.seconds * 1000)
            let alive = (response as? HTTPURLResponse)?.statusCode == 204

            let result = HealthResult(nodeName: node.name, latency: alive ? ms : nil, alive: alive)
            results[node.name] = result
            return result
        } catch {
            let result = HealthResult(nodeName: node.name, alive: false, error: String(describing: error))
            results[node.name] = result
            return result
        }
    }

    public func result(for name: String) -> HealthResult? {
        results[name]
    }

    public func allResults() -> [String: HealthResult] {
        results
    }

    public func startPeriodicCheck(nodes: [ProxyNode], interval: Duration) async {
        guard !running else { return }
        running = true
        while running {
            await withTaskGroup(of: Void.self) { group in
                for node in nodes {
                    group.addTask { _ = await self.check(node: node) }
                }
                _ = await group.next()
            }
            try? await Task.sleep(for: interval)
        }
    }

    public func stop() {
        running = false
    }
}

// MARK: - GroupSelector

public actor GroupSelector {
    private let healthChecker: HealthChecker
    private let loadBalancer: LoadBalancer

    public init(healthChecker: HealthChecker) {
        self.healthChecker = healthChecker
        self.loadBalancer = LoadBalancer(strategy: .consistentHash)
    }

    public func select(group: ProxyGroup, proxies: [ProxyNode]) async -> ProxyNode? {
        let available = proxies.filter { group.proxies.contains($0.name) }
        guard !available.isEmpty else { return nil }

        switch group.kind {
        case .select:
            var firstAlive: ProxyNode? = nil
            for node in available {
                if await healthChecker.result(for: node.name)?.alive ?? false {
                    firstAlive = node
                    break
                }
            }
            return firstAlive ?? available.first

        case .urlTest:
            var best: ProxyNode?
            var bestLatency = Int.max
            let _tolerance = group.tolerance ?? 0
            for node in available {
                if let result = await healthChecker.result(for: node.name), result.alive, let latency = result.latency {
                    if latency < bestLatency {
                        bestLatency = latency
                        best = node
                    }
                }
            }
            return best

        case .fallback:
            for node in available {
                if let result = await healthChecker.result(for: node.name), result.alive {
                    return node
                }
            }
            return available.first

        case .loadBalance:
            // Update load balancer with currently available proxies
            await loadBalancer.updateProxies(available.map { $0.name })
            // For load-balance, use the last target host hint from the group's policy
            // Since we don't have host context here, pass nil (consistent hash will still work)
            if let bestName = await loadBalancer.select(forHost: nil),
               let bestNode = available.first(where: { $0.name == bestName }) {
                return bestNode
            }
            return available.first
        }
    }
}
