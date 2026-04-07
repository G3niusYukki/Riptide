import Foundation

/// Actor that manages multiple rule providers with CRUD operations.
public actor RuleProviderManager {
    private var providers: [UUID: RuleProvider] = [:]
    private var scheduler: ProviderUpdateScheduler?

    public init() {}

    /// Add a new rule provider from configuration and returns its ID.
    public func addProvider(_ config: RuleProviderConfig) -> UUID {
        let provider = RuleProvider(config: config)
        providers[provider.id] = provider

        if let interval = config.updateInterval, interval > 0 {
            Task { [providerID = provider.id] in
                await scheduler?.schedule(providerID: providerID, interval: TimeInterval(interval))
            }
        }

        return provider.id
    }

    /// Add a new rule provider from configuration.
    public func addProviderAndReturnProvider(_ config: RuleProviderConfig) -> RuleProvider {
        let provider = RuleProvider(config: config)
        providers[provider.id] = provider

        if let interval = config.updateInterval, interval > 0 {
            Task { [providerID = provider.id] in
                await scheduler?.schedule(providerID: providerID, interval: TimeInterval(interval))
            }
        }

        return provider
    }

    /// Remove a rule provider by ID.
    public func removeProvider(id: UUID) async {
        await scheduler?.cancel(providerID: id)
        providers.removeValue(forKey: id)
    }

    /// Update a specific provider by triggering a refresh.
    public func updateProvider(id: UUID) async throws {
        guard let provider = providers[id] else { return }
        try await provider.refresh()
    }

    /// Get a provider by ID.
    public func getProvider(id: UUID) -> RuleProvider? {
        providers[id]
    }

    /// Get all providers.
    public func getAllProviders() -> [RuleProvider] {
        Array(providers.values)
    }

    /// Get all current rules from all providers.
    public func getAllRules() async -> [ProxyRule] {
        var allRules: [ProxyRule] = []
        for provider in providers.values {
            allRules.append(contentsOf: await provider.getRules())
        }
        return allRules
    }

    /// Start the scheduler for automatic updates.
    public func startScheduler(updateHandler: @escaping @Sendable (UUID) async -> Void) {
        scheduler = ProviderUpdateScheduler(updateHandler: updateHandler)
    }

    /// Stop all providers and the scheduler.
    public func stopAll() async {
        await scheduler?.stopAll()
        scheduler = nil

        for provider in providers.values {
            await provider.stop()
        }
    }

    /// Start all providers.
    public func startAll() async {
        for provider in providers.values {
            await provider.start()
        }
    }
}
