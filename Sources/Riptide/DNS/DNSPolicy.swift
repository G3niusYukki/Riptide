import Foundation

/// DNS enhanced mode (real-IP or fake-IP).
public enum DNSEnhancedMode: Equatable, Sendable {
    case realIP
    case fakeIP
}

/// A DNS resolver endpoint configuration.
public struct DNSResolverEndpoint: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case udp
        case tcp
        case doh
    }

    public let kind: Kind
    public let address: String
    public let dohURL: String?

    public init(kind: Kind, address: String, dohURL: String? = nil) {
        self.kind = kind
        self.address = address
        self.dohURL = dohURL
    }

    public static func udp(host: String, port: Int = 53) -> DNSResolverEndpoint {
        DNSResolverEndpoint(kind: .udp, address: "\(host):\(port)")
    }

    public static func doh(url: String) -> DNSResolverEndpoint {
        DNSResolverEndpoint(kind: .doh, address: url, dohURL: url)
    }
}

/// A per-domain DNS policy entry.
public struct DNSDomainPolicy: Sendable, Equatable, Codable {
    public enum Action: String, Sendable, Codable {
        case useRemote = "remote"
        case useDirect = "direct"
        case useGroup = "group"
    }

    public let pattern: String
    public let action: Action
    public let resolverGroup: String?

    public init(pattern: String, action: Action, resolverGroup: String? = nil) {
        self.pattern = pattern
        self.action = action
        self.resolverGroup = resolverGroup
    }
}

/// DNS policy describing how to resolve queries.
public struct DNSPolicy: Sendable, Equatable, Codable {
    /// Nameservers used for normal resolution.
    public let primaryResolvers: [DNSResolverEndpoint]
    /// Nameservers used when all primaries fail.
    public let fallbackResolvers: [DNSResolverEndpoint]
    /// Per-domain policy overrides.
    public let domainPolicies: [DNSDomainPolicy]
    /// If true, consult rule engine routing policy for DNS lookups.
    public let respectRules: Bool
    /// Fake-IP mode enabled.
    public let fakeIPEnabled: Bool
    /// CIDR for the fake IP pool.
    public let fakeIPCIDR: String

    public init(
        primaryResolvers: [DNSResolverEndpoint] = [],
        fallbackResolvers: [DNSResolverEndpoint] = [],
        domainPolicies: [DNSDomainPolicy] = [],
        respectRules: Bool = false,
        fakeIPEnabled: Bool = true,
        fakeIPCIDR: String = "198.18.0.0/16"
    ) {
        self.primaryResolvers = primaryResolvers
        self.fallbackResolvers = fallbackResolvers
        self.domainPolicies = domainPolicies
        self.respectRules = respectRules
        self.fakeIPEnabled = fakeIPEnabled
        self.fakeIPCIDR = fakeIPCIDR
    }

    /// Default DNS policy with public resolvers.
    public static var `default`: DNSPolicy {
        DNSPolicy(
            primaryResolvers: [
                .udp(host: "8.8.8.8", port: 53),
                .udp(host: "1.1.1.1", port: 53),
            ],
            fallbackResolvers: [
                .udp(host: "223.5.5.5", port: 53),
            ],
            fakeIPEnabled: true
        )
    }
}
