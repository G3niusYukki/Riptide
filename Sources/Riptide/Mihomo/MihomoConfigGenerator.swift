import Foundation

/// Generates mihomo-compatible YAML configuration from Riptide internal models.
public enum MihomoConfigGenerator {

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
            lines.append("  - name: \(proxy.name)")
            lines.append("    type: \(mihomoProxyType(for: proxy.kind))")
            lines.append("    server: \(proxy.server)")
            lines.append("    port: \(proxy.port)")

            // Add proxy-specific fields
            appendProxyFields(proxy: proxy, to: &lines)
        }
        lines.append("")

        // Proxy groups section
        if !config.proxyGroups.isEmpty {
            lines.append("proxy-groups:")
            for group in config.proxyGroups {
                lines.append("  - name: \(group.id)")
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
                    lines.append("      - \(proxyName)")
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
        case .http:
            return "http"
        case .socks5:
            return "socks5"
        }
    }

    /// Appends proxy-specific fields based on the proxy type.
    private static func appendProxyFields(proxy: ProxyNode, to lines: inout [String]) {
        switch proxy.kind {
        case .shadowsocks:
            if let cipher = proxy.cipher {
                lines.append("    cipher: \(cipher)")
            }
            if let password = proxy.password {
                lines.append("    password: \(password)")
            }

        case .vmess:
            if let uuid = proxy.uuid {
                lines.append("    uuid: \(uuid)")
            }
            if let alterId = proxy.alterId {
                lines.append("    alterId: \(alterId)")
            }
            // security becomes cipher in mihomo
            if let security = proxy.security {
                lines.append("    cipher: \(security)")
            } else if proxy.security == nil && proxy.uuid != nil {
                // Default cipher for VMess
                lines.append("    cipher: auto")
            }
            if let network = proxy.network {
                lines.append("    network: \(network)")
            }
            if let sni = proxy.sni {
                lines.append("    servername: \(sni)")
            }
            if let skipCertVerify = proxy.skipCertVerify {
                lines.append("    skip-cert-verify: \(skipCertVerify)")
            }
            if let wsPath = proxy.wsPath {
                lines.append("    ws-path: \(wsPath)")
            }
            if let wsHost = proxy.wsHost {
                lines.append("    ws-headers:")
                lines.append("      Host: \(wsHost)")
            }

        case .vless:
            if let uuid = proxy.uuid {
                lines.append("    uuid: \(uuid)")
            }
            if let flow = proxy.flow {
                lines.append("    flow: \(flow)")
            }
            // sni becomes servername in mihomo
            if let sni = proxy.sni {
                lines.append("    servername: \(sni)")
            }
            if let network = proxy.network {
                lines.append("    network: \(network)")
            }
            if let skipCertVerify = proxy.skipCertVerify {
                lines.append("    skip-cert-verify: \(skipCertVerify)")
            }

        case .trojan:
            if let password = proxy.password {
                lines.append("    password: \(password)")
            }
            if let sni = proxy.sni {
                lines.append("    sni: \(sni)")
            }
            if let skipCertVerify = proxy.skipCertVerify {
                lines.append("    skip-cert-verify: \(skipCertVerify)")
            }
            if let network = proxy.network {
                lines.append("    network: \(network)")
            }

        case .hysteria2:
            if let password = proxy.password {
                lines.append("    password: \(password)")
            }
            if let sni = proxy.sni {
                lines.append("    sni: \(sni)")
            }
            if let skipCertVerify = proxy.skipCertVerify {
                lines.append("    skip-cert-verify: \(skipCertVerify)")
            }

        case .http, .socks5:
            // For HTTP/SOCKS5, cipher is used as username
            if let cipher = proxy.cipher {
                lines.append("    username: \(cipher)")
            }
            if let password = proxy.password {
                lines.append("    password: \(password)")
            }
        }
    }

    /// Converts a Riptide ProxyRule to a mihomo rule string.
    private static func mihomoRuleString(for rule: ProxyRule) -> String? {
        switch rule {
        case .domain(let domain, let policy):
            return "DOMAIN,\(domain),\(mihomoPolicyString(for: policy))"

        case .domainSuffix(let suffix, let policy):
            return "DOMAIN-SUFFIX,\(suffix),\(mihomoPolicyString(for: policy))"

        case .domainKeyword(let keyword, let policy):
            return "DOMAIN-KEYWORD,\(keyword),\(mihomoPolicyString(for: policy))"

        case .ipCIDR(let cidr, let policy):
            return "IP-CIDR,\(cidr),\(mihomoPolicyString(for: policy))"

        case .ipCIDR6(let cidr, let policy):
            return "IP-CIDR6,\(cidr),\(mihomoPolicyString(for: policy))"

        case .srcIPCIDR(let cidr, let policy):
            return "SRC-IP-CIDR,\(cidr),\(mihomoPolicyString(for: policy))"

        case .srcPort(let port, let policy):
            return "SRC-PORT,\(port),\(mihomoPolicyString(for: policy))"

        case .dstPort(let port, let policy):
            return "DST-PORT,\(port),\(mihomoPolicyString(for: policy))"

        case .processName(let name, let policy):
            return "PROCESS-NAME,\(name),\(mihomoPolicyString(for: policy))"

        case .geoIP(let countryCode, let policy):
            return "GEOIP,\(countryCode),\(mihomoPolicyString(for: policy))"

        case .ipASN(let asn, let policy):
            return "IP-ASN,\(asn),\(mihomoPolicyString(for: policy))"

        case .geoSite(let code, let category, let policy):
            return "GEOSITE,\(code),\(mihomoPolicyString(for: policy))"

        case .ruleSet(let name, let policy):
            return "RULE-SET,\(name),\(mihomoPolicyString(for: policy))"

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
            return name
        }
    }
}
