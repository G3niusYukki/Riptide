import Foundation
import Yams

/// Merges a "merge" YAML file into an existing `RiptideConfig`.
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

    public static func merge(base: RiptideConfig, mergeYAML: String) throws -> RiptideConfig {
        guard let raw = try Yams.load(yaml: mergeYAML) as? [String: Any] else {
            throw MergeError.invalidYAML("failed to parse merge YAML")
        }

        var mergedRules = base.rules

        if let rawRules = raw["rules"] as? [String] {
            for ruleStr in rawRules {
                let parts = ruleStr.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let rule = parseRule(parts: parts) {
                    mergedRules.append(rule)
                }
            }
        }

        return RiptideConfig(
            mode: base.mode,
            proxies: base.proxies,
            rules: mergedRules,
            proxyGroups: base.proxyGroups,
            dnsPolicy: base.dnsPolicy,
            ruleProviders: base.ruleProviders,
            proxyProviders: base.proxyProviders
        )
    }

    private static func parseRule(parts: [String]) -> ProxyRule? {
        guard parts.count >= 3 else { return nil }
        let ruleType = parts[0].uppercased()

        switch ruleType {
        case "DOMAIN":
            return .domain(domain: parts[1], policy: .direct)
        case "DOMAIN-SUFFIX":
            return .domainSuffix(suffix: parts[1], policy: .direct)
        case "DOMAIN-KEYWORD":
            return .domainKeyword(keyword: parts[1], policy: .direct)
        case "REJECT":
            return .reject
        case "MATCH", "FINAL":
            return .final(policy: .direct)
        default:
            return nil
        }
    }
}
