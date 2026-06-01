import Foundation
import Yams

/// Parses a Clash-style YAML configuration file into the lightweight
/// `YAMLPreviewStats` summary used by the Finder Quick Look preview.
///
/// The parser is deliberately **lenient**: it returns a zero-value
/// `YAMLPreviewStats` instead of throwing when the YAML is invalid or
/// missing the expected top-level keys. The reason is that Quick Look
/// previews are short-lived, off the main thread, and must never crash
/// Finder — degrading to an empty preview is the safe behaviour.
public enum YAMLPreviewParser {

    /// How many proxy nodes to surface in the preview. Showing every
    /// node in a 200-node subscription would dwarf the preview pane and
    /// make it hard to read.
    public static let previewNodeLimit = 12

    /// Parse a YAML string into preview statistics. Never throws — an
    /// invalid YAML document degrades to `YAMLPreviewStats.empty`.
    public static func parse(yaml: String) -> YAMLPreviewStats {
        guard let root = try? Yams.load(yaml: yaml) as? [String: Any] else {
            return .empty
        }
        return stats(fromRoot: root, rawYAML: yaml)
    }

    /// Parse a YAML file at the given URL into preview statistics.
    /// Throws when the file cannot be read (file not found, permission
    /// denied, …) so the Quick Look extension can surface a real
    /// error in the preview pane.
    public static func parse(fileURL: URL) throws -> YAMLPreviewStats {
        let data = try Data(contentsOf: fileURL)
        let yaml = String(data: data, encoding: .utf8) ?? ""
        var stats = parse(yaml: yaml)
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        stats.updatedAt = attributes?[.modificationDate] as? Date
        return stats
    }

    // MARK: - Building stats from the raw mapping

    private static func stats(fromRoot root: [String: Any], rawYAML: String) -> YAMLPreviewStats {
        let rawProxies = root["proxies"] as? [[String: Any]] ?? []
        let rawGroups = root["proxy-groups"] as? [[String: Any]] ?? []
        let rawRules = root["rules"] as? [Any] ?? []

        let breakdown = protocolBreakdown(from: rawProxies)
        let nodes = firstNodes(from: rawProxies, limit: previewNodeLimit)

        let subscriptionInfo = detectSubscription(rawYAML: rawYAML, root: root)

        return YAMLPreviewStats(
            proxyCount: rawProxies.count,
            groupCount: rawGroups.count,
            ruleCount: rawRules.count,
            protocolBreakdown: breakdown,
            firstNodes: nodes,
            sanitizedSubscriptionURL: subscriptionInfo?.sanitized,
            updatedAt: nil,
            isSubscription: subscriptionInfo != nil
        )
    }

    private static func protocolBreakdown(from proxies: [[String: Any]]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for proxy in proxies {
            guard let type = proxy["type"] as? String, !type.isEmpty else { continue }
            counts[type, default: 0] += 1
        }
        return counts
    }

    private static func firstNodes(
        from proxies: [[String: Any]],
        limit: Int
    ) -> [YAMLPreviewNode] {
        let trimmed = proxies.prefix(limit)
        return trimmed.compactMap { dict in
            guard let name = dict["name"] as? String,
                  let server = dict["server"] as? String else { return nil }
            let type = (dict["type"] as? String) ?? "unknown"
            return YAMLPreviewNode(name: name, type: type, server: server)
        }
    }

    // MARK: - Subscription detection

    private struct SubscriptionInfo {
        let sanitized: String
    }

    private static func detectSubscription(
        rawYAML: String,
        root: [String: Any]
    ) -> SubscriptionInfo? {
        // 1. Inline `# subscription: <url>` comment, which our SubscriptionManager
        //    writes when it round-trips a config fetched from a provider.
        if let url = subscriptionURLFromComment(rawYAML) {
            return SubscriptionInfo(sanitized: sanitizeSubscriptionURL(url))
        }
        // 2. Explicit `subscription-url` key in the root mapping (a Clash Premium
        //    convention; the spec is unofficial but widely used).
        if let url = root["subscription-url"] as? String, !url.isEmpty {
            return SubscriptionInfo(sanitized: sanitizeSubscriptionURL(url))
        }
        return nil
    }

    private static func subscriptionURLFromComment(_ yaml: String) -> String? {
        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#") else { continue }
            let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
            let lower = body.lowercased()
            guard lower.hasPrefix("subscription:") || lower.hasPrefix("subscription-url:") else {
                continue
            }
            if let colon = body.firstIndex(of: ":") {
                let value = body[body.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    // MARK: - URL sanitization

    /// Strip credentials and sensitive query parameters from a subscription
    /// URL. Used to make the Quick Look preview safe to share in screenshots.
    public static func sanitizeSubscriptionURL(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else { return raw }
        components.user = nil
        components.password = nil
        if let items = components.queryItems {
            let redacted = items.compactMap { item -> URLQueryItem? in
                if Self.isSensitiveQueryKey(item.name) {
                    return URLQueryItem(name: item.name, value: "***")
                }
                return item
            }
            components.queryItems = redacted.isEmpty ? nil : redacted
        }
        return components.url?.absoluteString ?? raw
    }

    private static let sensitiveQueryKeys: Set<String> = [
        "token", "password", "pass", "secret", "key", "api_key", "apikey", "auth",
    ]

    private static func isSensitiveQueryKey(_ key: String) -> Bool {
        sensitiveQueryKeys.contains(key.lowercased())
    }

    // MARK: - Protocol type display

    /// Map a raw Clash protocol type string to a human-readable label.
    public static func displayType(forRawType raw: String) -> String {
        switch raw.lowercased() {
        case "ss", "ssm", "shadowsocks": return "Shadowsocks"
        case "vmess": return "VMess"
        case "vless": return "VLESS"
        case "trojan": return "Trojan"
        case "hysteria", "hysteria2", "hy2": return "Hysteria2"
        case "snell": return "Snell"
        case "tuic": return "TUIC"
        case "wireguard", "wg": return "WireGuard"
        case "http", "https": return "HTTP"
        case "socks5", "socks": return "SOCKS5"
        case "relay": return "Relay"
        default: return raw.uppercased()
        }
    }
}
