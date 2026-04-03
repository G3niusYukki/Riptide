import Foundation

public actor ProxyGroupResolver {
    /// Persisted selections: groupID -> selected node name
    private var selections: [String: String] = [:]

    public init() {}

    /// Resolve a group reference to a concrete proxy node name.
    /// Returns nil if the group has no proxies.
    public func resolve(
        groupID: String,
        group: ProxyGroup,
        allProxies: [ProxyNode]
    ) -> String? {
        switch group.kind {
        case .select:
            if let saved = selections[groupID] {
                return saved
            }
            return group.proxies.first
        case .urlTest:
            // Phase 1: return first proxy; latency-based selection is Phase 2
            return group.proxies.first
        case .fallback:
            // Phase 1: return first proxy; failover to next on failure is Phase 2
            return group.proxies.first
        case .loadBalance:
            return group.proxies.randomElement()
        }
    }

    /// Persist a user's manual selection for a select-type group.
    public func setSelection(groupID: String, nodeName: String) {
        selections[groupID] = nodeName
    }

    /// Get the persisted selection for a group.
    public func getSelection(groupID: String) -> String? {
        selections[groupID]
    }

    /// Clear all persisted selections.
    public func reset() {
        selections.removeAll()
    }
}
