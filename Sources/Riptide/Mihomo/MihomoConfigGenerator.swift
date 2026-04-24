import Foundation

/// Generates mihomo-compatible YAML configuration from Riptide internal models.
public enum MihomoConfigGenerator {

    /// Escapes a string for safe inclusion in YAML output.
    /// - Wraps strings in double quotes if they contain special characters
    /// - Escapes backslashes and double quotes inside the string
    /// - Returns plain string if no special characters
    /// - Note: Colons are NOT escaped as they are common in IPv6 addresses and
    ///   don't cause issues in list item contexts (not key-value contexts)
    private static func yamlEscape(_ string: String) -> String {
        let specialChars = CharacterSet(charactersIn: "#\"'{}[]\n,&*?|<>!=%@")
        if string.rangeOfCharacter(from: specialChars) == nil && !string.hasPrefix("-") && !string.hasPrefix("[") {
            return string
        }
        // Escape backslashes and quotes, then wrap in quotes
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Options for configuration generation.
    public struct GenerationOptions: Sendable {
        /// The runtime mode (system proxy or TUN).
        public let mode: RuntimeMode
        /// The mixed port for HTTP/SOCKS5 proxy (default: 6152).
        public let mixedPort: Int
        /// The external controller API port (default: 9090).
        public let apiPort: Int
        /// Log level (default: info).
        public let logLevel: String
        /// Allow LAN connections (default: false).
        public let allowLAN: Bool
        /// Enable IPv6 (default: true).
        public let ipv6: Bool

        public init(
            mode: RuntimeMode,
            mixedPort: Int = 6152,
            apiPort: Int = 9090,
            logLevel: String = "info",
            allowLAN: Bool = false,
            ipv6: Bool = true
        ) {
            self.mode = mode
            self.mixedPort = mixedPort
            self.apiPort = apiPort
            self.logLevel = logLevel
            self.allowLAN = allowLAN
            self.ipv6 = ipv6
        }
    }

    /// Generates a mihomo-compatible YAML configuration.
    /// - Parameters:
    ///   - config: The Riptide configuration to convert.
    ///   - options: Generation options controlling output format.
    /// - Returns: A YAML string suitable for mihomo core.
    public static func generate(config: RiptideConfig, options: GenerationOptions) -> String {
        var lines: [String] = []

        // Port settings
        lines.append("mixed-port: \(options.mixedPort)")
        lines.append("allow-lan: \(options.allowLAN)")
        lines.append("mode: \(config.mode.rawValue)")
        lines.append("log-level: \(options.logLevel)")
        lines.append("ipv6: \(options.ipv6)")
        lines.append("external-controller: 127.0.0.1:\(options.apiPort)")
        lines.append("")

        // TUN section
        lines.append("tun:")
        lines.append("  enable: \(options.mode == .tun)")
        lines.append("  stack: gvisor")
        lines.append("  dns-hijack:")
        lines.append("    - 0.0.0.0:53")
        lines.append("  auto-route: \(options.mode == .tun)")
        lines.append("  strict-route: \(options.mode == .tun)")
        lines.append("")

        // Proxies section
        lines.append("proxies:")
        for proxy in config.proxies {
            lines.append("  - name: \(yamlEscape(proxy.name))")
            lines.append("    type: \(mihomoProxyType(for: proxy.kind))")
            lines.append("    server: \(yamlEscape(proxy.server))")
            lines.append("    port: \(proxy.port)")

            // Add proxy-specific fields
            appendProxyFields(proxy: proxy, to: &lines)
        }
        lines.append("")

        // Proxy groups section
        if !config.proxyGroups.isEmpty {
            lines.append("proxy-groups:")
            for group in config.proxyGroups {
                lines.append("  - name: \(yamlEscape(group.id))")
                lines.append("    type: \(group.kind.rawValue)")

                if let interval = group.interval {
                    lines.append("    interval: \(interval)")
                }
                if let tolerance = group.tolerance {
                    lines.append("    tolerance: \(tolerance)")
                }
                if let strategy = group.strategy {
                    lines.append("    strategy: \(strategy.rawValue)")
                }

                lines.append("    proxies:")
                for proxyName in group.proxies {
                    lines.append("      - \(yamlEscape(proxyName))")
                }
            }
            lines.append("")
        }

        // Rules section
        lines.append("rules:")
        for rule in config.rules {
            if let ruleString = mihomoRuleString(for: rule) {
                lines.append("  - \(ruleString)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Maps Riptide ProxyKind to mihomo type string.
    private static func mihomoProxyType(for kind: ProxyKind) -> String {
        switch kind {
        case .shadowsocks:
            return "ss"
        case .vmess:
            return "vmess"
        case .vless:
            return "vless"
        case .trojan:
            return "trojan"
        case .hysteria2:
            return "hysteria2"
        case .snell:
            return "snell"
        case .http:
            return "http"
        case .socks5:
            return "socks5"
        case .relay:
            return "relay"
        case .tuic:
            return "tuic"
        }
    }

    /// Appends proxy-specific fields based on the proxy type.
    private static func appendProxyFields(proxy: ProxyNode, to lines: inout [String]) {
        switch proxy.kind {
        case .shadowsocks:
            if let cipher = proxy.cipher {
                lines.append("    cipher: \(yamlEscape(cipher))")
            }
            if let password = proxy.password {
                lines.append("    password: \(yamlEscape(password))")
            }

        case .vmess:
            if let uuid = proxy.uuid {
                lines.append("    uuid: \(yamlEscape(uuid))")
            }
            if let alterId = proxy.alterId {
                lines.append("    alterId: \(alterId)")
            }
            // security becomes cipher in mihomo
            if let security = proxy.security {
                lines.append("    cipher: \(yamlEscape(security))")
            } else if proxy.security == nil && proxy.uuid != nil {
                // Default cipher for VMess
                lines.append("    cipher: auto")
            }
            if let network = proxy.network {
                lines.append("    network: \(yamlEscape(network))")
            }
            if let sni = proxy.sni {
                lines.append("    servername: \(yamlEscape(sni))")
            }
            if let skipCertVerify = proxy.skipCertVerify {
                lines.append("    skip-cert-verify: \(skipCertVerify)")
            }
            if let wsPath = proxy.wsPath {
                lines.append("    ws-path: \(yamlEscape(wsPath))")
            }
            if let wsHost = proxy.wsHost {
                lines.append("    ws-headers:")
                lines.append("      Host: \(yamlEscape(wsHost))")
            }

        case .vless:
            if let uuid = proxy.uuid {
                lines.append("    uuid: \(yamlEscape(uuid))")
            }
            if let flow = proxy.flow {
                lines.append("    flow: \(yamlEscape(flow))")
            }
            // sni becomes servername in mihomo
            if let sni = proxy.sni {
                lines.append("    servername: \(yamlEscape(sni))")
            }
            if let network = proxy.network {
                lines.append("    network: \(yamlEscape(network))")
            }
            if let skipCertVerify = proxy.skipCertVerify {
                lines.append("    skip-cert-verify: \(skipCertVerify)")
            }

        case .trojan:
            if let password = proxy.password {
                lines.append("    password: \(yamlEscape(password))")
            }
            if let sni = proxy.sni {
                lines.append("    sni: \(yamlEscape(sni))")
            }
            if let skipCertVerify = proxy.skipCertVerify {
                lines.append("    skip-cert-verify: \(skipCertVerify)")
            }
            if let network = proxy.network {
                lines.append("    network: \(yamlEscape(network))")
            }

        case .hysteria2:
            if let password = proxy.password {
                lines.append("    password: \(yamlEscape(password))")
            }
            if let sni = proxy.sni {
                lines.append("    sni: \(yamlEscape(sni))")
            }
            if let skipCertVerify = proxy.skipCertVerify {
                lines.append("    skip-cert-verify: \(skipCertVerify)")
            }

        case .snell:
            if let password = proxy.password {
                lines.append("    password: \(yamlEscape(password))")
            }
            if let version = proxy.snellVersion {
                lines.append("    version: \(version)")
            }

        case .relay:
            if let chainProxyName = proxy.chainProxyName {
                lines.append("    relay: \(yamlEscape(chainProxyName))")
            }

        case .tuic:
            if let password = proxy.password {
                lines.append("    password: \(yamlEscape(password))")
            }
            if let sni = proxy.sni {
                lines.append("    sni: \(yamlEscape(sni))")
            }
            if let skipCertVerify = proxy.skipCertVerify {
                lines.append("    skip-cert-verify: \(skipCertVerify)")
            }

        case .http, .socks5:
            // For HTTP/SOCKS5, cipher is used as username
            if let cipher = proxy.cipher {
                lines.append("    username: \(yamlEscape(cipher))")
            }
            if let password = proxy.password {
                lines.append("    password: \(yamlEscape(password))")
            }
        }
    }

    /// Converts a Riptide ProxyRule to a mihomo rule string.
    private static func mihomoRuleString(for rule: ProxyRule) -> String? {
        switch rule {
        case .domain(let domain, let policy):
            return "DOMAIN,\(yamlEscape(domain)),\(mihomoPolicyString(for: policy))"

        case .domainSuffix(let suffix, let policy):
            return "DOMAIN-SUFFIX,\(yamlEscape(suffix)),\(mihomoPolicyString(for: policy))"

        case .domainKeyword(let keyword, let policy):
            return "DOMAIN-KEYWORD,\(yamlEscape(keyword)),\(mihomoPolicyString(for: policy))"

        case .ipCIDR(let cidr, let policy):
            return "IP-CIDR,\(yamlEscape(cidr)),\(mihomoPolicyString(for: policy))"

        case .ipCIDR6(let cidr, let policy):
            return "IP-CIDR6,\(yamlEscape(cidr)),\(mihomoPolicyString(for: policy))"

        case .srcIPCIDR(let cidr, let policy):
            return "SRC-IP-CIDR,\(yamlEscape(cidr)),\(mihomoPolicyString(for: policy))"

        case .srcPort(let port, let policy):
            return "SRC-PORT,\(port),\(mihomoPolicyString(for: policy))"

        case .dstPort(let port, let policy):
            return "DST-PORT,\(port),\(mihomoPolicyString(for: policy))"

        case .processName(let name, let policy):
            return "PROCESS-NAME,\(yamlEscape(name)),\(mihomoPolicyString(for: policy))"

        case .geoIP(let countryCode, let policy):
            return "GEOIP,\(yamlEscape(countryCode)),\(mihomoPolicyString(for: policy))"

        case .ipASN(let asn, let policy):
            return "IP-ASN,\(asn),\(mihomoPolicyString(for: policy))"

        case .geoSite(let code, _, let policy):
            return "GEOSITE,\(yamlEscape(code)),\(mihomoPolicyString(for: policy))"

        case .script(_, let policy):
            // Script rules are handled by mihomo's script configuration, not inline
            return "SCRIPT,\(mihomoPolicyString(for: policy))"

        case .ruleSet(let name, let policy):
            return "RULE-SET,\(yamlEscape(name)),\(mihomoPolicyString(for: policy))"

        case .not(let ruleType, let value, let policy):
            return "NOT,\(ruleType),\(yamlEscape(value)),\(mihomoPolicyString(for: policy))"

        case .reject:
            return "REJECT"

        case .matchAll:
            // matchAll is typically rendered as MATCH,DIRECT by convention
            return "MATCH,DIRECT"

        case .final(let policy):
            return "MATCH,\(mihomoPolicyString(for: policy))"
        }
    }

    /// Converts a Riptide RoutingPolicy to a mihomo policy string.
    private static func mihomoPolicyString(for policy: RoutingPolicy) -> String {
        switch policy {
        case .direct:
            return "DIRECT"
        case .reject:
            return "REJECT"
        case .proxyNode(let name):
            return yamlEscape(name)
        }
    }
}
