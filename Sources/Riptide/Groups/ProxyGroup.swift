import Foundation

public enum ProxyGroupKind: String, Equatable, Sendable, Codable {
    case select
    case urlTest = "url-test"
    case fallback
    case loadBalance = "load-balance"
}

public enum LBStrategy: String, Equatable, Sendable, Codable {
    case consistentHashing = "consistent-hashing"
    case roundRobin = "round-robin"
}

public struct ProxyGroup: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let kind: ProxyGroupKind
    public let proxies: [String]
    public let interval: Int?
    public let tolerance: Int?
    public let strategy: LBStrategy?

    public init(id: String, kind: ProxyGroupKind, proxies: [String],
                interval: Int? = nil, tolerance: Int? = nil, strategy: LBStrategy? = nil) {
        self.id = id
        self.kind = kind
        self.proxies = proxies
        self.interval = interval
        self.tolerance = tolerance
        self.strategy = strategy
    }
}
