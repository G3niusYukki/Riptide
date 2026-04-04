import Foundation

public struct RuleTarget: Equatable, Sendable {
    public let domain: String?
    public let ipAddress: String?
    public let sourceIP: String?
    public let sourcePort: Int?
    public let destinationPort: Int?
    public let processName: String?

    public init(domain: String? = nil, ipAddress: String? = nil,
                sourceIP: String? = nil, sourcePort: Int? = nil,
                destinationPort: Int? = nil, processName: String? = nil) {
        self.domain = domain
        self.ipAddress = ipAddress
        self.sourceIP = sourceIP
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.processName = processName
    }
}

public struct RuleEngine: Sendable {
    /// The flat, fully-expanded rule list.
    private let expandedRules: [ProxyRule]
    private let geoIPResolver: GeoIPResolver

    /// Initialize a RuleEngine.
    /// - Parameters:
    ///   - rules: The top-level rules from the config. May contain `.ruleSet` entries.
    ///   - ruleSets: A mapping of rule-set provider name to its loaded rules.
    ///   - geoIPResolver: Optional GeoIP resolver for GEOIP rule matching.
    public init(
        rules: [ProxyRule],
        ruleSets: [String: [ProxyRule]] = [:],
        geoIPResolver: GeoIPResolver = .none
    ) {
        self.geoIPResolver = geoIPResolver
        // Expand all .ruleSet entries inline at init time.
        var expanded: [ProxyRule] = []
        for rule in rules {
            if case .ruleSet(let name, _) = rule {
                if let rsRules = ruleSets[name], !rsRules.isEmpty {
                    // Inject each rule from the set, preserving its own policy.
                    expanded.append(contentsOf: rsRules)
                }
                // If the set is not yet loaded or empty, skip it silently.
            } else {
                expanded.append(rule)
            }
        }
        self.expandedRules = expanded
    }

    public func resolve(target: RuleTarget) -> RoutingPolicy {
        for rule in expandedRules {
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

        case .ipCIDR6(let cidr, let policy):
            guard let ipAddress = target.ipAddress else { return nil }
            return IPv6CIDR(cidr)?.contains(ipAddress) == true ? policy : nil

        case .srcIPCIDR(let cidr, let policy):
            guard
                let sourceIP = target.sourceIP,
                let network = IPv4CIDR(cidr),
                let ipValue = IPv4AddressParser.parse(sourceIP)
            else {
                return nil
            }
            return network.contains(ipValue) ? policy : nil

        case .srcPort(let port, let policy):
            guard let srcPort = target.sourcePort else { return nil }
            return srcPort == port ? policy : nil

        case .dstPort(let port, let policy):
            guard let dstPort = target.destinationPort else { return nil }
            return dstPort == port ? policy : nil

        case .processName(let name, let policy):
            guard let proc = target.processName else { return nil }
            return proc == name ? policy : nil

        case .geoIP(let countryCode, let policy):
            guard
                let ipAddress = target.ipAddress,
                let resolvedCountryCode = geoIPResolver.resolveCountryCode(ipAddress)?.uppercased()
            else {
                return nil
            }
            return resolvedCountryCode == countryCode.uppercased() ? policy : nil

        case .ipASN(_, let policy):
            return policy

        case .geoSite(_, _, let policy):
            return policy

        case .ruleSet(_, let policy):
            return policy

        case .script(let code, let policy):
            let engine = RuleScriptEngine(code: code)
            return engine.evaluate(target: target) ? policy : nil

        case .matchAll:
            return .direct

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

struct IPv6CIDR: Sendable {
    let prefix: Int
    let addressData: [UInt8]

    init?(_ cidr: String) {
        let parts = cidr.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        guard let prefix = Int(parts[1]), (0...128).contains(prefix) else { return nil }

        var addr = in6_addr()
        let result = String(parts[0]).withCString { ptr in
            inet_pton(AF_INET6, ptr, &addr)
        }
        guard result == 1 else { return nil }

        self.prefix = prefix
        self.addressData = withUnsafeBytes(of: &addr) { Array($0) }
    }

    func contains(_ ip: String) -> Bool {
        var addr = in6_addr()
        let result = ip.withCString { ptr in
            inet_pton(AF_INET6, ptr, &addr)
        }
        guard result == 1 else { return false }

        let ipBytes = withUnsafeBytes(of: &addr) { Array($0) }
        guard ipBytes.count == addressData.count else { return false }

        let fullBytes = prefix / 8
        let remainingBits = prefix % 8

        for i in 0..<fullBytes {
            guard ipBytes[i] == addressData[i] else { return false }
        }

        if remainingBits > 0 && fullBytes < 16 {
            let mask = UInt8(0xFF << (8 - remainingBits))
            guard (ipBytes[fullBytes] & mask) == (addressData[fullBytes] & mask) else { return false }
        }

        return true
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
