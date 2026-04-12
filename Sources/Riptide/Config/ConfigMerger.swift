import Foundation
import Yams

/// Merges a "merge" YAML file into an existing `RiptideConfig`.
/// Supports deep merge of: proxies, proxy-groups, rules, dns, rule-providers, proxy-providers.
public struct ConfigMerger: Sendable {

    public enum MergeError: Error, Equatable, Sendable {
        case invalidYAML(String)
        case parseFailed(String)

        public var localizedDescription: String {
            switch self {
            case .invalidYAML(let msg): return "Invalid merge YAML: \(msg)"
            case .parseFailed(let msg): return "Merge parse failed: \(msg)"
            }
        }
    }

    // MARK: - Single Merge

    public static func merge(base: RiptideConfig, mergeYAML: String) throws -> RiptideConfig {
        guard let raw = try Yams.load(yaml: mergeYAML) as? [String: Any] else {
            throw MergeError.invalidYAML("failed to parse merge YAML")
        }
        return try deepMerge(base: base, merge: raw)
    }

    // MARK: - Multiple Merges

    /// Applies multiple merge YAML files in order.
    public static func merge(base: RiptideConfig, mergeYAMLs: [String]) throws -> RiptideConfig {
        try mergeYAMLs.reduce(base) { config, yaml in
            try merge(base: config, mergeYAML: yaml)
        }
    }

    // MARK: - Deep Merge Implementation

    private static func deepMerge(base: RiptideConfig, merge: [String: Any]) throws -> RiptideConfig {
        var result = base

        // Merge proxies (append new, replace existing by name)
        if let rawProxies = merge["proxies"] as? [[String: Any]] {
            var mergedProxies = base.proxies
            for rawProxy in rawProxies {
                if let name = rawProxy["name"] as? String,
                   let parsed = try? parseRawProxy(rawProxy) {
                    if let idx = mergedProxies.firstIndex(where: { $0.name == name }) {
                        mergedProxies[idx] = parsed
                    } else {
                        mergedProxies.append(parsed)
                    }
                }
            }
            result = RiptideConfig(
                mode: result.mode, proxies: mergedProxies, rules: result.rules,
                proxyGroups: result.proxyGroups, dnsPolicy: result.dnsPolicy,
                ruleProviders: result.ruleProviders, proxyProviders: result.proxyProviders
            )
        }

        // Merge proxy-groups (append new, replace existing by id)
        if let rawGroups = merge["proxy-groups"] as? [[String: Any]] {
            var mergedGroups = base.proxyGroups
            for rawGroup in rawGroups {
                if let name = rawGroup["name"] as? String,
                   let parsed = parseRawProxyGroup(rawGroup) {
                    if let idx = mergedGroups.firstIndex(where: { $0.id == name }) {
                        mergedGroups[idx] = parsed
                    } else {
                        mergedGroups.append(parsed)
                    }
                }
            }
            result = RiptideConfig(
                mode: result.mode, proxies: result.proxies, rules: result.rules,
                proxyGroups: mergedGroups, dnsPolicy: result.dnsPolicy,
                ruleProviders: result.ruleProviders, proxyProviders: result.proxyProviders
            )
        }

        // Merge rules (append)
        if let rawRules = merge["rules"] as? [String] {
            var mergedRules = base.rules
            for ruleStr in rawRules {
                let parts = ruleStr.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let rule = parseRule(parts: parts) {
                    mergedRules.append(rule)
                }
            }
            result = RiptideConfig(
                mode: result.mode, proxies: result.proxies, rules: mergedRules,
                proxyGroups: result.proxyGroups, dnsPolicy: result.dnsPolicy,
                ruleProviders: result.ruleProviders, proxyProviders: result.proxyProviders
            )
        }

        // Merge DNS policy (basic fields — DNSPolicy uses DNSResolverEndpoint structs)
        if let rawDNS = merge["dns"] as? [String: Any] {
            let basePolicy = base.dnsPolicy ?? DNSPolicy()
            var fakeIPEnabled = basePolicy.fakeIPEnabled
            var fakeIPCIDR = basePolicy.fakeIPCIDR
            var respectRules = basePolicy.respectRules
            var hosts = basePolicy.hosts

            if let enable = rawDNS["enable"] as? Bool { fakeIPEnabled = enable }
            if let fakeRange = rawDNS["fake-ip-range"] as? String { fakeIPCIDR = fakeRange }
            if let enhancedMode = rawDNS["enhanced-mode"] as? String {
                if enhancedMode == "redir-host" { fakeIPEnabled = false }
            }
            if let rawHosts = rawDNS["hosts"] as? [String: String] {
                hosts = hosts.merging(rawHosts) { _, new in new }
            }

            let dnsPolicy = DNSPolicy(
                primaryResolvers: basePolicy.primaryResolvers,
                fallbackResolvers: basePolicy.fallbackResolvers,
                domainPolicies: basePolicy.domainPolicies,
                respectRules: respectRules,
                fakeIPEnabled: fakeIPEnabled,
                fakeIPCIDR: fakeIPCIDR,
                hosts: hosts
            )
            result = RiptideConfig(
                mode: result.mode, proxies: result.proxies, rules: result.rules,
                proxyGroups: result.proxyGroups, dnsPolicy: dnsPolicy,
                ruleProviders: result.ruleProviders, proxyProviders: result.proxyProviders
            )
        }

        return result
    }

    // MARK: - Raw Parsing Helpers
    private static func parseRawProxy(_ raw: [String: Any]) throws -> ProxyNode {
        guard let name = raw["name"] as? String,
              let type = raw["type"] as? String,
              let server = raw["server"] as? String,
              let port = raw["port"] as? Int else {
            throw MergeError.parseFailed("missing required proxy fields")
        }
        let kind: ProxyKind
        switch type.lowercased() {
        case "ss", "shadowsocks": kind = .shadowsocks
        case "vmess": kind = .vmess
        case "vless": kind = .vless
        case "trojan": kind = .trojan
        case "hysteria2", "hy2": kind = .hysteria2
        case "snell": kind = .snell
        case "socks5": kind = .socks5
        case "http", "https": kind = .http
        case "relay": kind = .relay
        default: kind = .http
        }
        return ProxyNode(
            name: name, kind: kind, server: server, port: port,
            cipher: raw["cipher"] as? String, password: raw["password"] as? String,
            uuid: raw["uuid"] as? String, flow: raw["flow"] as? String,
            alterId: raw["alterId"] as? Int, security: raw["cipher"] as? String,
            sni: raw["sni"] as? String, alpn: raw["alpn"] as? [String],
            skipCertVerify: raw["skip-cert-verify"] as? Bool,
            network: raw["network"] as? String,
            wsPath: raw["ws-path"] as? String, wsHost: raw["ws-headers"] as? String,
            grpcServiceName: raw["grpc-service-name"] as? String,
            snellVersion: raw["version"] as? Int
        )
    }

    private static func parseRawProxyGroup(_ raw: [String: Any]) -> ProxyGroup? {
        guard let name = raw["name"] as? String,
              let type = raw["type"] as? String else { return nil }
        let kind = ProxyGroupKind(rawValue: type.lowercased()) ?? .select
        let proxies = (raw["proxies"] as? [String]) ?? []
        let interval = raw["interval"] as? Int
        let tolerance = raw["tolerance"] as? Int
        let strategy: LBStrategy? = {
            guard let s = raw["strategy"] as? String else { return nil }
            return LBStrategy(rawValue: s.lowercased())
        }()
        return ProxyGroup(
            id: name, kind: kind, proxies: proxies,
            interval: interval, tolerance: tolerance, strategy: strategy
        )
    }

    // MARK: - Rule Parsing (existing)

>>>>>>> origin/main
    private static func parseRule(parts: [String]) -> ProxyRule? {
        guard parts.count >= 3 else { return nil }
        let ruleType = parts[0].uppercased()
        let policyName = parts[2]
        let policy = parsePolicy(policyName)

        switch ruleType {
        case "DOMAIN":
            return .domain(domain: parts[1], policy: policy)
        case "DOMAIN-SUFFIX":
            return .domainSuffix(suffix: parts[1], policy: policy)
        case "DOMAIN-KEYWORD":
            return .domainKeyword(keyword: parts[1], policy: policy)
        case "IP-CIDR":
            return .ipCIDR(cidr: parts[1], policy: policy)
        case "IP-CIDR6":
            return .ipCIDR6(cidr: parts[1], policy: policy)
        case "SRC-IP-CIDR":
            return .srcIPCIDR(cidr: parts[1], policy: policy)
        case "SRC-PORT":
            if let portVal = Int(parts[1]) {
                return .srcPort(port: portVal, policy: policy)
            }
            return nil
        case "DST-PORT":
            if let portVal = Int(parts[1]) {
                return .dstPort(port: portVal, policy: policy)
            }
            return nil
        case "PROCESS-NAME":
            return .processName(name: parts[1], policy: policy)
        case "GEOIP":
            return .geoIP(countryCode: parts[1], policy: policy)
        case "GEOSITE":
            let category = parts.count > 3 ? parts[2] : "geolocation-cn"
            return .geoSite(code: parts[1], category: category, policy: policy)
        case "RULE-SET":
            return .ruleSet(name: parts[1], policy: policy)
        case "SCRIPT":
            return .script(code: parts[1], policy: policy)
        case "NOT":
            return .not(ruleType: parts[1], value: parts[2], policy: policy)
        case "REJECT":
            return .reject
        case "MATCH", "FINAL":
            return .final(policy: policy)
        default:
            return nil
        }
    }

    private static func parsePolicy(_ name: String) -> RoutingPolicy {
        switch name.uppercased() {
        case "DIRECT": return .direct
        case "PROXY": return .proxyNode(name: "PROXY")
        case "REJECT": return .reject
        default: return .proxyNode(name: name)
        }
    }
}
