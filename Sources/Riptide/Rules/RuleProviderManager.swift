import Foundation

public actor RuleProviderManager {
    private var providers: [UUID: RuleProvider] = [:]
    private var scheduler: ProviderUpdateScheduler?
    
    public init() {}
    
    public func addProvider(_ config: RuleProviderConfig) async -> RuleProvider {
        let provider = RuleProvider(config: config)
        providers[provider.id] = provider
        
        if let interval = config.updateInterval {
            await scheduler?.schedule(providerID: provider.id, interval: TimeInterval(interval))
        }
        
        return provider
    }
    
    public func removeProvider(id: UUID) async {
        await scheduler?.cancel(providerID: id)
        providers.removeValue(forKey: id)
    }
    
    public func updateProvider(id: UUID) async throws {
        guard let provider = providers[id] else { return }
        try await provider.update()
    }
    
    public func getProvider(id: UUID) -> RuleProvider? {
        providers[id]
    }
    
    public func getAllProviders() -> [RuleProvider] {
        Array(providers.values)
    }
    
    public func startScheduler(updateHandler: @Sendable @escaping (UUID) async -> Void) {
        scheduler = ProviderUpdateScheduler(updateHandler: updateHandler)
    }
    
    public func stopAll() async {
        await scheduler?.stopAll()
    }
}
