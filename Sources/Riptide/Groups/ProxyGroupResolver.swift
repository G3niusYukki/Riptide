import Foundation

/// Errors from proxy group resolution.
public enum ProxyGroupResolverError: Error, Equatable, Sendable {
    case groupNotFound(String)
    case noHealthyNode(String)
    case unknownNode(String)
    case wrongGroupKind(String)
}

/// Actor that resolves proxy group policies to concrete proxy node names.
/// Integrates with `GroupSelector` (health-aware selection) and persists
/// user `Select` choices across runtime restarts.
public actor ProxyGroupResolver {
    private let healthChecker: HealthChecker
    private let selector: GroupSelector
    private var selectChoices: [String: String] // group id → chosen proxy name
    private var config: RiptideConfig

    public init(healthChecker: HealthChecker, config: RiptideConfig = RiptideConfig(mode: .rule, proxies: [], rules: [])) {
        self.healthChecker = healthChecker
        self.selector = GroupSelector(healthChecker: healthChecker)
        self.config = config
        self.selectChoices = [:]
    }

    /// Update the active configuration with proxy groups.
    public func updateConfig(_ config: RiptideConfig) {
        self.config = config
    }

    /// Set the user-selected proxy for a `select` group.
    public func setSelectedProxy(forGroup groupID: String, proxyName: String) throws {
        guard let group = config.proxyGroups.first(where: { $0.id == groupID }) else {
            throw ProxyGroupResolverError.groupNotFound(groupID)
        }
        guard group.kind == .select else {
            throw ProxyGroupResolverError.wrongGroupKind(groupID)
        }
        guard group.proxies.contains(proxyName) else {
            throw ProxyGroupResolverError.unknownNode(proxyName)
        }
        selectChoices[groupID] = proxyName
    }

    /// Resolve a group by ID to a concrete proxy node name, using health-aware
    /// selection for URL-Test/Fallback/LoadBalance, and persisted choice for Select.
    public func resolve(groupID: String) async throws -> String {
        guard let group = config.proxyGroups.first(where: { $0.id == groupID }) else {
            throw ProxyGroupResolverError.groupNotFound(groupID)
        }

        let nodeProxies = group.proxies.compactMap { name in
            config.proxies.first { $0.name == name }
        }

        switch group.kind {
        case .select:
            // Use persisted choice, or fall back to first available
            if let choice = selectChoices[groupID],
               nodeProxies.contains(where: { $0.name == choice }) {
                return choice
            }
            // Pick the first alive proxy, or first configured proxy
            for node in nodeProxies {
                if let result = await healthChecker.result(for: node.name), result.alive {
                    return node.name
                }
            }
            if let firstNode = nodeProxies.first {
                return firstNode.name
            }
            if let unknownProxy = group.proxies.first {
                throw ProxyGroupResolverError.unknownNode(unknownProxy)
            }
            throw ProxyGroupResolverError.noHealthyNode(groupID)

        case .urlTest:
            guard let best = await selector.select(group: group, proxies: nodeProxies) else {
                throw ProxyGroupResolverError.noHealthyNode(groupID)
            }
            return best.name

        case .fallback:
            guard let chosen = await selector.select(group: group, proxies: nodeProxies) else {
                throw ProxyGroupResolverError.noHealthyNode(groupID)
            }
            return chosen.name

        case .loadBalance:
            guard let chosen = await selector.select(group: group, proxies: nodeProxies) else {
                throw ProxyGroupResolverError.noHealthyNode(groupID)
            }
            return chosen.name
        }
    }

    /// Resolve a policy that might be a proxy node referencing a group.
    public func resolvePolicy(_ policy: RoutingPolicy) async throws -> RoutingPolicy {
        switch policy {
        case .proxyNode(let name):
            // Check if this name refers to a group
            if config.proxyGroups.contains(where: { $0.id == name }) {
                let resolved = try await resolve(groupID: name)
                return .proxyNode(name: resolved)
            }
            return .proxyNode(name: name)

        default:
            return policy
        }
    }
}
