import Foundation

public struct ProviderHealth: Sendable, Equatable {
    public let status: Status
    public let lastChecked: Date
    public let latency: TimeInterval?
    public let errorMessage: String?
    
    public enum Status: Sendable {
        case healthy
        case degraded
        case unhealthy
        case unknown
    }
    
    public init(status: Status, lastChecked: Date, latency: TimeInterval?, errorMessage: String?) {
        self.status = status
        self.lastChecked = lastChecked
        self.latency = latency
        self.errorMessage = errorMessage
    }
}

public actor ProxyProviderHealthChecker {
    private var monitoringTasks: [UUID: Task<Void, Never>] = [:]
    private var healthStatus: [UUID: ProviderHealth] = [:]
    
    public init() {}
    
    public func checkProvider(_ provider: ProxyProvider) async -> ProviderHealth {
        let start = Date()
        do {
            // Attempt HTTP HEAD request to provider URL for reachability check
            let config = provider.config
            if config.type.lowercased() == "http", let urlString = config.url, let url = URL(string: urlString) {
                var request = URLRequest(url: url)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 10
                
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if (200...299).contains(httpResponse.statusCode) {
                        let latency = Date().timeIntervalSince(start)
                        let health = ProviderHealth(
                            status: .healthy,
                            lastChecked: Date(),
                            latency: latency,
                            errorMessage: nil
                        )
                        healthStatus[provider.id] = health
                        return health
                    } else {
                        let health = ProviderHealth(
                            status: .degraded,
                            lastChecked: Date(),
                            latency: nil,
                            errorMessage: "HTTP \(httpResponse.statusCode)"
                        )
                        healthStatus[provider.id] = health
                        return health
                    }
                }
            }
            
            // For file-based providers or other types, just verify nodes are available
            let nodes = await provider.nodes()
            if !nodes.isEmpty {
                let latency = Date().timeIntervalSince(start)
                let health = ProviderHealth(
                    status: .healthy,
                    lastChecked: Date(),
                    latency: latency,
                    errorMessage: nil
                )
                healthStatus[provider.id] = health
                return health
            } else {
                let health = ProviderHealth(
                    status: .unhealthy,
                    lastChecked: Date(),
                    latency: nil,
                    errorMessage: "No nodes available"
                )
                healthStatus[provider.id] = health
                return health
            }
        } catch {
            let health = ProviderHealth(
                status: .unhealthy,
                lastChecked: Date(),
                latency: nil,
                errorMessage: error.localizedDescription
            )
            healthStatus[provider.id] = health
            return health
        }
    }
    
    public func startMonitoring(provider: ProxyProvider, interval: TimeInterval = 300) {
        guard monitoringTasks[provider.id] == nil else { return }
        
        monitoringTasks[provider.id] = Task {
            while !Task.isCancelled {
                _ = await checkProvider(provider)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }
    
    public func stopMonitoring(providerID: UUID) {
        monitoringTasks[providerID]?.cancel()
        monitoringTasks.removeValue(forKey: providerID)
    }
    
    public func getHealth(for providerID: UUID) -> ProviderHealth? {
        healthStatus[providerID]
    }
}
