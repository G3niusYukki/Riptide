import Foundation

private enum SingBoxRouteAction {
    case append([String: Any])
    case updateFinal(String)
}

public enum SingBoxConfigGeneratorError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingRequiredField(proxyName: String, field: String)
    case unsupportedProxyKind(proxyName: String, kind: ProxyKind)
    case unsupportedRule(String)
    case invalidJSONObject(String)

    public var description: String {
        switch self {
        case .missingRequiredField(let proxyName, let field):
            return "Proxy '\(proxyName)' is missing required field '\(field)'"
        case .unsupportedProxyKind(let proxyName, let kind):
            return "Proxy '\(proxyName)' uses unsupported sing-box kind '\(kind)'"
        case .unsupportedRule(let rule):
            return "Rule '\(rule)' is not supported by the sing-box generator"
        case .invalidJSONObject(let reason):
            return "Invalid sing-box JSON object: \(reason)"
        }
    }
}

/// Generates sing-box JSON for the embedded GoCore runtime.
public enum SingBoxConfigGenerator {
    public struct GenerationOptions: Sendable, Equatable {
        public let mode: RuntimeMode
        public let mixedPort: Int
        public let logLevel: String
        public let tunDeviceName: String

        public init(
            mode: RuntimeMode,
            mixedPort: Int = 6152,
            logLevel: String = "info",
            tunDeviceName: String = "utun120"
        ) {
            self.mode = mode
            self.mixedPort = mixedPort
            self.logLevel = logLevel
            self.tunDeviceName = tunDeviceName
        }
    }

    public static func generate(config: RiptideConfig, options: GenerationOptions) throws -> String {
        var inbounds = [
            mixedInbound(port: options.mixedPort)
        ]
        if options.mode == .tun {
            inbounds.append(tunInbound(deviceName: options.tunDeviceName))
        }

        var root: [String: Any] = [
            "log": [
                "level": options.logLevel
            ],
            "inbounds": inbounds,
            "outbounds": try outbounds(for: config.proxies),
            "route": try route(for: config, options: options)
        ]

        if options.mode == .tun {
            root["experimental"] = [
                "cache_file": [
                    "enabled": true
                ]
            ]
        }

        guard JSONSerialization.isValidJSONObject(root) else {
            throw SingBoxConfigGeneratorError.invalidJSONObject("root contains non-JSON values")
        }

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw SingBoxConfigGeneratorError.invalidJSONObject("generated data is not UTF-8")
        }
        return json
    }

    private static func mixedInbound(port: Int) -> [String: Any] {
        [
            "type": "mixed",
            "tag": "mixed-in",
            "listen": "127.0.0.1",
            "listen_port": port
        ]
    }

    private static func tunInbound(deviceName: String) -> [String: Any] {
        [
            "type": "tun",
            "tag": "tun-in",
            "interface_name": deviceName,
            "inet4_address": "172.19.0.1/30",
            "auto_route": true,
            "strict_route": true,
            "stack": "gvisor",
            "mtu": 1500
        ]
    }

    private static func outbounds(for proxies: [ProxyNode]) throws -> [[String: Any]] {
        var result: [[String: Any]] = [
            [
                "type": "direct",
                "tag": "direct"
            ],
            [
                "type": "block",
                "tag": "block"
            ]
        ]

        for proxy in proxies {
            result.append(try outbound(for: proxy))
        }
        return result
    }

    private static func outbound(for proxy: ProxyNode) throws -> [String: Any] {
        switch proxy.kind {
        case .wireguard:
            return try wireGuardOutbound(for: proxy)
        case .shadowsocks:
            return try shadowsocksOutbound(for: proxy)
        case .socks5:
            return socksOutbound(for: proxy)
        case .http:
            return httpOutbound(for: proxy)
        case .trojan:
            return try trojanOutbound(for: proxy)
        case .vmess, .vless, .hysteria2, .relay, .snell, .tuic:
            throw SingBoxConfigGeneratorError.unsupportedProxyKind(proxyName: proxy.name, kind: proxy.kind)
        }
    }

    private static func shadowsocksOutbound(for proxy: ProxyNode) throws -> [String: Any] {
        guard let method = proxy.cipher, !method.isEmpty else {
            throw SingBoxConfigGeneratorError.missingRequiredField(proxyName: proxy.name, field: "cipher")
        }
        guard let password = proxy.password, !password.isEmpty else {
            throw SingBoxConfigGeneratorError.missingRequiredField(proxyName: proxy.name, field: "password")
        }

        return baseServerOutbound(proxy: proxy, type: "shadowsocks").merging([
            "method": method,
            "password": password
        ]) { _, new in new }
    }

    private static func socksOutbound(for proxy: ProxyNode) -> [String: Any] {
        var outbound = baseServerOutbound(proxy: proxy, type: "socks")
        if let username = proxy.cipher, !username.isEmpty {
            outbound["username"] = username
        }
        if let password = proxy.password, !password.isEmpty {
            outbound["password"] = password
        }
        outbound["version"] = "5"
        return outbound
    }

    private static func httpOutbound(for proxy: ProxyNode) -> [String: Any] {
        var outbound = baseServerOutbound(proxy: proxy, type: "http")
        if let username = proxy.cipher, !username.isEmpty {
            outbound["username"] = username
        }
        if let password = proxy.password, !password.isEmpty {
            outbound["password"] = password
        }
        return outbound
    }

    private static func trojanOutbound(for proxy: ProxyNode) throws -> [String: Any] {
        guard let password = proxy.password, !password.isEmpty else {
            throw SingBoxConfigGeneratorError.missingRequiredField(proxyName: proxy.name, field: "password")
        }

        var outbound = baseServerOutbound(proxy: proxy, type: "trojan")
        outbound["password"] = password
        if let sni = proxy.sni, !sni.isEmpty {
            outbound["tls"] = [
                "enabled": true,
                "server_name": sni
            ]
        }
        return outbound
    }

    private static func wireGuardOutbound(for proxy: ProxyNode) throws -> [String: Any] {
        guard let privateKey = proxy.password, !privateKey.isEmpty else {
            throw SingBoxConfigGeneratorError.missingRequiredField(proxyName: proxy.name, field: "private-key")
        }
        guard let publicKey = proxy.wireguardPublicKey, !publicKey.isEmpty else {
            throw SingBoxConfigGeneratorError.missingRequiredField(proxyName: proxy.name, field: "public-key")
        }
        guard let localAddress = proxy.wireguardIP, !localAddress.isEmpty else {
            throw SingBoxConfigGeneratorError.missingRequiredField(proxyName: proxy.name, field: "ip")
        }

        var outbound = baseServerOutbound(proxy: proxy, type: "wireguard")
        outbound["system_interface"] = false
        outbound["local_address"] = [localAddress]
        outbound["private_key"] = privateKey
        outbound["peer_public_key"] = publicKey
        if let psk = proxy.wireguardPreSharedKey, !psk.isEmpty {
            outbound["pre_shared_key"] = psk
        }
        if let reserved = proxy.wireguardReserved, !reserved.isEmpty {
            outbound["reserved"] = reserved.map(Int.init)
        }
        if let mtu = proxy.wireguardMTU {
            outbound["mtu"] = mtu
        }
        return outbound
    }

    private static func baseServerOutbound(proxy: ProxyNode, type: String) -> [String: Any] {
        [
            "type": type,
            "tag": proxy.name,
            "server": proxy.server,
            "server_port": proxy.port
        ]
    }

    private static func route(for config: RiptideConfig, options: GenerationOptions) throws -> [String: Any] {
        var rules: [[String: Any]] = []
        var final = defaultOutbound(for: config)

        for rule in config.rules {
            switch try routeAction(for: rule) {
            case .append(let routeRule):
                rules.append(routeRule)
            case .updateFinal(let outbound):
                final = outbound
            }
        }

        var route: [String: Any] = [
            "final": final
        ]
        if options.mode == .tun {
            route["auto_detect_interface"] = true
        }
        if !rules.isEmpty {
            route["rules"] = rules
        }
        return route
    }

    private static func defaultOutbound(for config: RiptideConfig) -> String {
        switch config.mode {
        case .direct:
            return "direct"
        case .global:
            return config.proxies.first?.name ?? "direct"
        case .rule:
            return "direct"
        }
    }

    private static func routeAction(for rule: ProxyRule) throws -> SingBoxRouteAction {
        if let routeRule = simpleRouteRule(for: rule) {
            return .append(routeRule)
        }

        switch rule {
        case .not(let ruleType, let value, let policy):
            guard let nested = invertedRule(ruleType: ruleType, value: value, outbound: outboundTag(for: policy)) else {
                throw SingBoxConfigGeneratorError.unsupportedRule("NOT,\(ruleType),\(value)")
            }
            return .append(nested)
        case .reject:
            return .updateFinal("block")
        case .matchAll:
            return .updateFinal("direct")
        case .final(let policy):
            return .updateFinal(outboundTag(for: policy))
        case .ipASN(let asn, _):
            throw SingBoxConfigGeneratorError.unsupportedRule("IP-ASN,\(asn)")
        case .script:
            throw SingBoxConfigGeneratorError.unsupportedRule("SCRIPT")
        case .domain,
             .domainSuffix,
             .domainKeyword,
             .ipCIDR,
             .ipCIDR6,
             .srcIPCIDR,
             .srcPort,
             .dstPort,
             .processName,
             .geoIP,
             .geoSite,
             .ruleSet:
            preconditionFailure("simple route rules are handled before routeAction switch")
        }
    }

    private static func simpleRouteRule(for rule: ProxyRule) -> [String: Any]? {
        switch rule {
        case .domain(let domain, let policy):
            return ["domain": [domain], "outbound": outboundTag(for: policy)]
        case .domainSuffix(let suffix, let policy):
            return ["domain_suffix": [suffix], "outbound": outboundTag(for: policy)]
        case .domainKeyword(let keyword, let policy):
            return ["domain_keyword": [keyword], "outbound": outboundTag(for: policy)]
        case .ipCIDR(let cidr, let policy), .ipCIDR6(let cidr, let policy):
            return ["ip_cidr": [cidr], "outbound": outboundTag(for: policy)]
        case .srcIPCIDR(let cidr, let policy):
            return ["source_ip_cidr": [cidr], "outbound": outboundTag(for: policy)]
        case .srcPort(let port, let policy):
            return ["source_port": [port], "outbound": outboundTag(for: policy)]
        case .dstPort(let port, let policy):
            return ["port": [port], "outbound": outboundTag(for: policy)]
        case .processName(let name, let policy):
            return ["process_name": [name], "outbound": outboundTag(for: policy)]
        case .geoIP(let countryCode, let policy):
            return ["geoip": [countryCode], "outbound": outboundTag(for: policy)]
        case .geoSite(let code, _, let policy):
            return ["geosite": [code], "outbound": outboundTag(for: policy)]
        case .ruleSet(let name, let policy):
            return ["rule_set": [name], "outbound": outboundTag(for: policy)]
        case .not, .reject, .matchAll, .final, .ipASN, .script:
            return nil
        }
    }

    private static func outboundTag(for policy: RoutingPolicy) -> String {
        switch policy {
        case .direct:
            return "direct"
        case .reject:
            return "block"
        case .proxyNode(let name):
            return name
        }
    }

    private static func invertedRule(ruleType: String, value: String, outbound: String) -> [String: Any]? {
        var rule: [String: Any]?
        switch ruleType.uppercased() {
        case "DOMAIN":
            rule = ["domain": [value]]
        case "DOMAIN-SUFFIX":
            rule = ["domain_suffix": [value]]
        case "DOMAIN-KEYWORD":
            rule = ["domain_keyword": [value]]
        case "IP-CIDR", "IP-CIDR6":
            rule = ["ip_cidr": [value]]
        default:
            return nil
        }
        rule?["invert"] = true
        rule?["outbound"] = outbound
        return rule
    }
}
