import Foundation

/// Behavior hint for a remote rule set.
public enum RuleSetBehavior: Sendable, Equatable {
    /// Rule set contains only DOMAIN rules.
    case domain
    /// Rule set contains only IP-CIDR rules.
    case ipcidr
    /// Rule set contains a mix of domain and IP-CIDR rules.
    case classical
}

/// A downloaded and parsed rule set.
public struct RuleSet: Sendable {
    public let name: String
    public let behavior: RuleSetBehavior
    public let rules: [ProxyRule]
    public let updatedAt: Date

    public init(name: String, behavior: RuleSetBehavior, rules: [ProxyRule], updatedAt: Date) {
        self.name = name
        self.behavior = behavior
        self.rules = rules
        self.updatedAt = updatedAt
    }
}

/// Provider configuration for a remote rule set.
public struct RuleSetProviderConfig: Sendable, Equatable {
    public let name: String
    public let type: String
    public let url: String
    public let interval: Int
    public let behavior: RuleSetBehavior

    public init(name: String, type: String, url: String, interval: Int, behavior: RuleSetBehavior) {
        self.name = name
        self.type = type
        self.url = url
        self.interval = interval
        self.behavior = behavior
    }
}
