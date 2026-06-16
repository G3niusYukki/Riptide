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
        /// Whether the linked sing-box core was built with `-tags with_utls`.
        /// The shipped `libgocore.a` is NOT, so uTLS/REALITY would make the core
        /// reject the WHOLE config. When false, REALITY/uTLS fields are omitted
        /// (reality nodes degrade to plain VLESS+TLS) so the rest of the config
        /// still loads. Flip to true once the core is rebuilt with uTLS.
        public let supportsUTLS: Bool

        public init(
            mode: RuntimeMode,
            mixedPort: Int = 6152,
            logLevel: String = "info",
            tunDeviceName: String = "utun120",
            supportsUTLS: Bool = false
        ) {
            self.mode = mode
            self.mixedPort = mixedPort
            self.logLevel = logLevel
            self.tunDeviceName = tunDeviceName
            self.supportsUTLS = supportsUTLS
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
            "outbounds": try outbounds(for: config.proxies, supportsUTLS: options.supportsUTLS),
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

    private static func outbounds(for proxies: [ProxyNode], supportsUTLS: Bool) throws -> [[String: Any]] {
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
            result.append(try outbound(for: proxy, supportsUTLS: supportsUTLS))
        }
        return result
    }

    private static func outbound(for proxy: ProxyNode, supportsUTLS: Bool) throws -> [String: Any] {
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
            return try trojanOutbound(for: proxy, supportsUTLS: supportsUTLS)
        case .vmess:
            return try vmessOutbound(for: proxy, supportsUTLS: supportsUTLS)
        case .vless:
            return try vlessOutbound(for: proxy, supportsUTLS: supportsUTLS)
        case .hysteria2:
            return hysteria2Outbound(for: proxy, supportsUTLS: supportsUTLS)
        case .tuic:
            return try tuicOutbound(for: proxy, supportsUTLS: supportsUTLS)
        case .relay, .snell, .reality, .anytls, .ssh:
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

    private static func trojanOutbound(for proxy: ProxyNode, supportsUTLS: Bool) throws -> [String: Any] {
        guard let password = proxy.password, !password.isEmpty else {
            throw SingBoxConfigGeneratorError.missingRequiredField(proxyName: proxy.name, field: "password")
        }

        var outbound = baseServerOutbound(proxy: proxy, type: "trojan")
        outbound["password"] = password
        // Trojan always runs over TLS.
        if let tls = tlsOptions(for: proxy, forceEnabled: true, supportsUTLS: supportsUTLS) {
            outbound["tls"] = tls
        }
        if let transport = transportOptions(for: proxy) {
            outbound["transport"] = transport
        }
        return outbound
    }

    private static func vmessOutbound(for proxy: ProxyNode, supportsUTLS: Bool) throws -> [String: Any] {
        guard let uuid = proxy.uuid, !uuid.isEmpty else {
            throw SingBoxConfigGeneratorError.missingRequiredField(proxyName: proxy.name, field: "uuid")
        }
        var outbound = baseServerOutbound(proxy: proxy, type: "vmess")
        outbound["uuid"] = uuid
        outbound["security"] = proxy.security ?? proxy.cipher ?? "auto"
        outbound["alter_id"] = proxy.alterId ?? 0
        // TLS only when the node opts in (vmess can run plaintext over tcp/ws).
        if let tls = tlsOptions(for: proxy, forceEnabled: false, supportsUTLS: supportsUTLS) {
            outbound["tls"] = tls
        }
        if let transport = transportOptions(for: proxy) {
            outbound["transport"] = transport
        }
        return outbound
    }

    private static func vlessOutbound(for proxy: ProxyNode, supportsUTLS: Bool) throws -> [String: Any] {
        guard let uuid = proxy.uuid, !uuid.isEmpty else {
            throw SingBoxConfigGeneratorError.missingRequiredField(proxyName: proxy.name, field: "uuid")
        }
        var outbound = baseServerOutbound(proxy: proxy, type: "vless")
        outbound["uuid"] = uuid

        // v1.9.0 accepts only "" or "xtls-rprx-vision". Vision needs a raw TLS
        // stream, so it is mutually exclusive with a v2ray transport.
        let usesVision = proxy.flow == "xtls-rprx-vision"
        if usesVision {
            outbound["flow"] = "xtls-rprx-vision"
        }

        if let tls = tlsOptions(for: proxy, forceEnabled: false, supportsUTLS: supportsUTLS) {
            outbound["tls"] = tls
        }
        if !usesVision, let transport = transportOptions(for: proxy) {
            outbound["transport"] = transport
        }
        return outbound
    }

    private static func hysteria2Outbound(for proxy: ProxyNode, supportsUTLS: Bool) -> [String: Any] {
        var outbound = baseServerOutbound(proxy: proxy, type: "hysteria2")
        if let password = proxy.password, !password.isEmpty {
            outbound["password"] = password
        }
        // Hysteria2 is QUIC/TLS — tls is mandatory; default ALPN to ["h3"].
        outbound["tls"] = tlsOptions(for: proxy, forceEnabled: true, defaultALPN: ["h3"], supportsUTLS: supportsUTLS) ?? ["enabled": true]
        return outbound
    }

    private static func tuicOutbound(for proxy: ProxyNode, supportsUTLS: Bool) throws -> [String: Any] {
        guard let uuid = proxy.uuid, !uuid.isEmpty else {
            throw SingBoxConfigGeneratorError.missingRequiredField(proxyName: proxy.name, field: "uuid")
        }
        var outbound = baseServerOutbound(proxy: proxy, type: "tuic")
        outbound["uuid"] = uuid
        if let password = proxy.password, !password.isEmpty {
            outbound["password"] = password
        }
        if let cc = normalizedCongestionControl(proxy.congestionControl) {
            outbound["congestion_control"] = cc
        }
        // TUIC is QUIC/TLS — tls is mandatory; default ALPN to ["h3"].
        outbound["tls"] = tlsOptions(for: proxy, forceEnabled: true, defaultALPN: ["h3"], supportsUTLS: supportsUTLS) ?? ["enabled": true]
        return outbound
    }

    // MARK: - Shared TLS / transport builders (sing-box v1.9.0 schema)

    /// Builds the shared outbound `tls` object, or nil when TLS is not used.
    /// Only emits fields that exist in sing-box v1.9.0 (no v1.10+ keys).
    /// - Parameters:
    ///   - forceEnabled: protocols where TLS is mandatory (trojan/hysteria2/tuic).
    ///   - defaultALPN: fallback ALPN when the node specifies none (e.g. ["h3"]).
    private static func tlsOptions(
        for proxy: ProxyNode,
        forceEnabled: Bool,
        defaultALPN: [String]? = nil,
        supportsUTLS: Bool
    ) -> [String: Any]? {
        let realityRequested = (proxy.realityPublicKey?.isEmpty == false)
        let hasFlow = (proxy.flow?.isEmpty == false)
        let enabled = forceEnabled || realityRequested || proxy.tls == true || hasFlow
        guard enabled else { return nil }

        var tls: [String: Any] = ["enabled": true]

        // Prefer the REALITY/handshake host as SNI when present.
        let serverName = (realityRequested ? proxy.realityServerName : nil) ?? proxy.sni
        if let serverName, !serverName.isEmpty {
            tls["server_name"] = serverName
        }
        // REALITY authenticates via its public key; never weaken it with insecure.
        if proxy.skipCertVerify == true && !realityRequested {
            tls["insecure"] = true
        }
        if let alpn = proxy.alpn, !alpn.isEmpty {
            tls["alpn"] = alpn
        } else if let defaultALPN, !defaultALPN.isEmpty {
            tls["alpn"] = defaultALPN
        }

        // uTLS / REALITY require the core to be built with `-tags with_utls`.
        // When it isn't, omit them so the whole config still loads (a REALITY
        // node degrades to plain TLS — non-functional but non-fatal).
        guard supportsUTLS else { return tls }

        if realityRequested {
            tls["utls"] = [
                "enabled": true,
                "fingerprint": normalizedFingerprint(proxy.realityFingerprint) ?? "chrome"
            ]
            var reality: [String: Any] = [
                "enabled": true,
                "public_key": proxy.realityPublicKey ?? ""
            ]
            reality["short_id"] = proxy.realityShortId ?? ""
            tls["reality"] = reality
        } else if let fingerprint = normalizedFingerprint(proxy.realityFingerprint) {
            tls["utls"] = ["enabled": true, "fingerprint": fingerprint]
        }

        return tls
    }

    /// Builds the shared v2ray `transport` object for ws/grpc/http, or nil for
    /// raw TCP. sing-box has no "tcp"/"mkcp" transport — those map to no object.
    private static func transportOptions(for proxy: ProxyNode) -> [String: Any]? {
        switch proxy.network?.lowercased() {
        case "ws":
            var transport: [String: Any] = ["type": "ws"]
            if let path = proxy.wsPath, !path.isEmpty {
                transport["path"] = path
            }
            if let host = proxy.wsHost, !host.isEmpty {
                transport["headers"] = ["Host": host]
            }
            return transport
        case "grpc":
            var transport: [String: Any] = ["type": "grpc"]
            if let service = proxy.grpcServiceName, !service.isEmpty {
                transport["service_name"] = service
            }
            return transport
        case "http", "h2":
            var transport: [String: Any] = ["type": "http"]
            if let path = proxy.wsPath, !path.isEmpty {
                transport["path"] = path
            }
            if let host = proxy.wsHost, !host.isEmpty {
                transport["host"] = [host]
            }
            return transport
        default:
            return nil
        }
    }

    /// uTLS fingerprints recognized by sing-box v1.9.0.
    private static let validFingerprints: Set<String> = [
        "chrome", "firefox", "edge", "safari", "360", "qq",
        "ios", "android", "random", "randomized"
    ]

    private static func normalizedFingerprint(_ fingerprint: String?) -> String? {
        guard let fingerprint, !fingerprint.isEmpty else { return nil }
        return validFingerprints.contains(fingerprint) ? fingerprint : "chrome"
    }

    private static func normalizedCongestionControl(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        switch value.lowercased() {
        case "bbr": return "bbr"
        case "new_reno", "newreno", "reno": return "new_reno"
        case "cubic": return "cubic"
        default: return nil
        }
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
