import Foundation

/// Load-balancing strategies for proxy groups.
public enum LoadBalanceStrategy: String, Sendable {
    /// Round-robin: cycles through proxies sequentially
    case roundRobin = "round-robin"
    /// Consistent hash: maps each target host to the same proxy
    case consistentHash = "consistent-hash"
}

/// Stateful load balancer for a single load-balance group.
/// Thread-safe via actor isolation.
public actor LoadBalancer {
    private let strategy: LoadBalanceStrategy
    private var proxies: [String]  // proxy names in order
    private var roundRobinIndex: Int = 0
    private var hashSeed: UInt64 = 0

    public init(strategy: LoadBalanceStrategy = .consistentHash) {
        self.strategy = strategy
        self.proxies = []
    }

    /// Updates the available proxy list.
    public func updateProxies(_ names: [String]) {
        self.proxies = names
        if roundRobinIndex >= names.count {
            roundRobinIndex = 0
        }
        // Re-seed hash when proxy list changes
        hashSeed = UInt64(Date().timeIntervalSince1970 * 1000)
    }

    /// Selects a proxy for the given target host.
    /// - Parameter host: The destination host (used for consistent hashing)
    /// - Returns: The selected proxy name, or nil if no proxies available
    public func select(forHost host: String? = nil) -> String? {
        guard !proxies.isEmpty else { return nil }

        switch strategy {
        case .roundRobin:
            return selectRoundRobin()
        case .consistentHash:
            return selectConsistentHash(host: host)
        }
    }

    /// Simple round-robin selection.
    private func selectRoundRobin() -> String? {
        guard !proxies.isEmpty else { return nil }
        let proxy = proxies[roundRobinIndex % proxies.count]
        roundRobinIndex = (roundRobinIndex + 1) % proxies.count
        return proxy
    }

    /// Consistent hash: same host always maps to same proxy.
    /// Uses FNV-1a hash for deterministic mapping.
    private func selectConsistentHash(host: String?) -> String? {
        guard !proxies.isEmpty else { return nil }
        let key: String
        if let host = host, !host.isEmpty {
            key = host
        } else {
            // Fallback to time-based for unknown hosts
            key = "\(Date().timeIntervalSince1970)"
        }
        let hash = fnv1a(key)
        let index = Int(hash % UInt64(proxies.count))
        return proxies[index]
    }

    /// FNV-1a 64-bit hash.
    private func fnv1a(_ string: String) -> UInt64 {
        let data = string.data(using: .utf8) ?? Data()
        var hash: UInt64 = 14695981039346656037 // FNV offset basis
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211 // FNV prime
        }
        return hash ^ hashSeed
    }
}
