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

public actor HealthChecker {
    private var results: [String: HealthResult]
    private var running: Bool = false

    public init() {
        self.results = [:]
    }

    /// Check the reachability of testURL and record the result under `node.name`.
    ///
    /// **Note:** The current implementation performs a direct `URLSession` HEAD request
    /// and does **not** route traffic through the provided `ProxyNode`. The `node` parameter
    /// is used only to label the result. A future iteration should route the probe through
    /// the proxy dialer so that latency reflects the actual proxy path.
    public func check(node: ProxyNode, testURL: URL = URL(string: "http://www.gstatic.com/generate_204")!,
                      timeout: Duration = .seconds(5)) async -> HealthResult {
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

public actor GroupSelector {
    private let healthChecker: HealthChecker

    public init(healthChecker: HealthChecker) {
        self.healthChecker = healthChecker
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
            return available.randomElement()
        }
    }
}
