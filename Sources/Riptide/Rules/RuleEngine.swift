import Foundation

public struct RuleTarget: Equatable, Sendable {
    public let domain: String?
    public let ipAddress: String?

    public init(domain: String?, ipAddress: String?) {
        self.domain = domain
        self.ipAddress = ipAddress
    }
}

public struct RuleEngine: Sendable {
    private let rules: [ProxyRule]

    public init(rules: [ProxyRule]) {
        self.rules = rules
    }

    public func resolve(target: RuleTarget) -> RoutingPolicy {
        for rule in rules {
            if let policy = matchedPolicy(for: rule, target: target) {
                return policy
            }
        }
        return .reject
    }

    private func matchedPolicy(for rule: ProxyRule, target: RuleTarget) -> RoutingPolicy? {
        switch rule {
        case .domain(let domain, let policy):
            guard let host = normalizedDomain(target.domain), host == normalizedDomain(domain) else {
                return nil
            }
            return policy

        case .domainSuffix(let suffix, let policy):
            guard
                let host = normalizedDomain(target.domain),
                let normalizedSuffix = normalizedDomain(suffix)
            else {
                return nil
            }
            if host == normalizedSuffix || host.hasSuffix(".\(normalizedSuffix)") {
                return policy
            }
            return nil

        case .domainKeyword(let keyword, let policy):
            guard
                let host = normalizedDomain(target.domain),
                !keyword.isEmpty
            else {
                return nil
            }
            return host.contains(keyword.lowercased()) ? policy : nil

        case .ipCIDR(let cidr, let policy):
            guard
                let ipAddress = target.ipAddress,
                let network = IPv4CIDR(cidr),
                let ipValue = IPv4AddressParser.parse(ipAddress)
            else {
                return nil
            }
            return network.contains(ipValue) ? policy : nil

        case .geoIP:
            return nil

        case .final(let policy):
            return policy
        }
    }

    private func normalizedDomain(_ domain: String?) -> String? {
        guard let domain else { return nil }
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct IPv4CIDR: Sendable {
    let networkAddress: UInt32
    let mask: UInt32

    init?(_ cidr: String) {
        let parts = cidr.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        guard let ipValue = IPv4AddressParser.parse(String(parts[0])) else { return nil }
        guard let prefix = Int(parts[1]), (0...32).contains(prefix) else { return nil }

        if prefix == 0 {
            self.mask = 0
            self.networkAddress = 0
            return
        }

        let shift = UInt32(32 - prefix)
        let mask = UInt32.max << shift
        self.mask = mask
        self.networkAddress = ipValue & mask
    }

    func contains(_ ip: UInt32) -> Bool {
        (ip & mask) == networkAddress
    }
}

enum IPv4AddressParser {
    static func parse(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(part) else { return nil }
            value = (value << 8) | UInt32(octet)
        }
        return value
    }
}
