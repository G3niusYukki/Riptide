import Foundation
import Yams

public enum ClashConfigError: Error, Equatable, Sendable {
    case invalidYAML(String)
    case unsupportedMode(String)
    case missingProxies
    case missingRules
    case invalidProxy(index: Int, reason: String)
    case invalidRule(index: Int, reason: String)
    case unknownProxyReference(String)
}

public enum ClashConfigParser {
    public static func parse(yaml: String) throws -> (RiptideConfig, [String: RuleSetProvider]) {
        let rawMap: [String: Any]
        do {
            guard let node = try Yams.load(yaml: yaml) as? [String: Any] else {
                throw ClashConfigError.invalidYAML("root must be a mapping")
            }
            rawMap = node
        } catch {
            throw ClashConfigError.invalidYAML(error.localizedDescription)
        }

        let mode = try parseMode(rawMap["mode"] as? String)
        let raw = try YAMLDecoder().decode(ClashRawConfig.self, from: yaml)
        let proxies = try parseProxies(raw.proxies)
        let proxyGroups = try parseProxyGroups(raw.proxyGroups)

        let ruleProviders = try parseRuleProviders(rawMap["rule-providers"] as? [String: Any])
        let proxyProviders = try parseProxyProviders(rawMap["proxy-providers"] as? [String: Any])

        // Include both leaf proxy names and group IDs so rules can reference either.
        let proxyNameSet = Set(proxies.map(\.name))
        let groupIDSet = Set(proxyGroups.map(\.id))
        let knownProxySet = proxyNameSet.union(groupIDSet)
        let rules = try parseRules(raw.rules, mode: mode, knownProxies: knownProxySet, ruleProviders: ruleProviders)
        try validateModeRequirements(mode: mode, proxies: proxies, rules: rules)
        let dnsPolicy = parseDNSPolicy(raw.dns)

        // Build RuleSetProvider objects from configs
        var ruleSetProviders: [String: RuleSetProvider] = [:]
        for (name, config) in ruleProviders {
            ruleSetProviders[name] = RuleSetProvider(config: config)
        }

        let config = RiptideConfig(
            mode: mode,
            proxies: proxies,
            rules: rules,
            proxyGroups: proxyGroups,
            dnsPolicy: dnsPolicy,
            ruleProviders: ruleProviders,
            proxyProviders: proxyProviders
        )

        return (config, ruleSetProviders)
    }

    private static func parseMode(_ mode: String?) throws -> ProxyMode {
        switch mode?.lowercased() {
        case .none, "":
            return .rule
        case ProxyMode.rule.rawValue:
            return .rule
        case ProxyMode.global.rawValue:
            return .global
        case ProxyMode.direct.rawValue:
            return .direct
        case let unsupported?:
            throw ClashConfigError.unsupportedMode(unsupported)
        }
    }

    private static func parseProxies(_ rawProxies: [ClashRawProxy]?) throws -> [ProxyNode] {
        guard let rawProxies, !rawProxies.isEmpty else {
            return []
        }

        return try rawProxies.enumerated().map { index, proxy in
            guard !proxy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ClashConfigError.invalidProxy(index: index, reason: "name is required")
            }
            guard !proxy.server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ClashConfigError.invalidProxy(index: index, reason: "server is required")
            }
            let kind = try parseProxyKind(proxy.type, index: index)

            // Relay nodes use the chain proxy for transport; port is not required.
            guard kind == .relay || (proxy.port != nil && (1...65_535).contains(proxy.port!)) else {
                throw ClashConfigError.invalidProxy(index: index, reason: "valid port is required")
            }
            let port = proxy.port ?? 0

            switch kind {
            case .shadowsocks:
                guard let cipher = proxy.cipher, !cipher.isEmpty else {
                    throw ClashConfigError.invalidProxy(index: index, reason: "cipher is required for Shadowsocks")
                }
                guard let password = proxy.password, !password.isEmpty else {
                    throw ClashConfigError.invalidProxy(index: index, reason: "password is required for Shadowsocks")
                }
                return ProxyNode(
                    name: proxy.name,
                    kind: .shadowsocks,
                    server: proxy.server,
                    port: port,
                    cipher: cipher,
                    password: password
                )

            case .vless:
                guard let uuid = proxy.uuid, !uuid.isEmpty else {
                    throw ClashConfigError.invalidProxy(index: index, reason: "uuid is required for VLESS")
                }
                return ProxyNode(
                    name: proxy.name,
                    kind: .vless,
                    server: proxy.server,
                    port: port,
                    uuid: uuid,
                    flow: proxy.flow,
                    sni: proxy.sni,
                    alpn: proxy.alpn,
                    skipCertVerify: proxy.skipCertVerify,
                    network: proxy.network,
                    wsPath: proxy.wsOpts?.path,
                    wsHost: proxy.wsOpts?.headers?["Host"],
                    grpcServiceName: proxy.grpcOpts?.grpcServiceName
                )

            case .trojan:
                guard let password = proxy.password, !password.isEmpty else {
                    throw ClashConfigError.invalidProxy(index: index, reason: "password is required for Trojan")
                }
                return ProxyNode(
                    name: proxy.name,
                    kind: .trojan,
                    server: proxy.server,
                    port: port,
                    password: password,
                    sni: proxy.sni,
                    alpn: proxy.alpn,
                    skipCertVerify: proxy.skipCertVerify,
                    network: proxy.network
                )

            case .vmess:
                guard let uuid = proxy.uuid, !uuid.isEmpty else {
                    throw ClashConfigError.invalidProxy(index: index, reason: "uuid is required for VMess")
                }
                return ProxyNode(
                    name: proxy.name,
                    kind: .vmess,
                    server: proxy.server,
                    port: port,
                    uuid: uuid,
                    alterId: proxy.alterId,
                    security: proxy.security,
                    sni: proxy.sni,
                    alpn: proxy.alpn,
                    skipCertVerify: proxy.skipCertVerify,
                    network: proxy.network,
                    wsPath: proxy.wsOpts?.path,
                    wsHost: proxy.wsOpts?.headers?["Host"]
                )

            case .socks5, .http:
                return ProxyNode(
                    name: proxy.name,
                    kind: kind,
                    server: proxy.server,
                    port: port,
                    cipher: proxy.cipher,
                    password: proxy.password
                )

            case .hysteria2:
                guard let password = proxy.password, !password.isEmpty else {
                    throw ClashConfigError.invalidProxy(index: index, reason: "password is required for Hysteria2")
                }
                return ProxyNode(
                    name: proxy.name,
                    kind: .hysteria2,
                    server: proxy.server,
                    port: port,
                    password: password,
                    sni: proxy.sni,
                    skipCertVerify: proxy.skipCertVerify
                )

            case .relay:
                guard let chainName = proxy.chain, !chainName.isEmpty else {
                    throw ClashConfigError.invalidProxy(index: index, reason: "chain proxy name is required for relay")
                }
                return ProxyNode(
                    name: proxy.name,
                    kind: .relay,
                    server: proxy.server,
                    port: port,
                    chainProxyName: chainName
                )

            case .snell:
                guard let password = proxy.password, !password.isEmpty else {
                    throw ClashConfigError.invalidProxy(index: index, reason: "psk is required for Snell")
                }
                return ProxyNode(
                    name: proxy.name,
                    kind: .snell,
                    server: proxy.server,
                    port: port,
                    password: password,
                    snellVersion: proxy.snellVersion
                )
            }
        }
    }

    private static func parseProxyKind(_ rawType: String?, index: Int) throws -> ProxyKind {
        switch rawType?.lowercased() {
        case "ss":
            return .shadowsocks
        case "socks5":
            return .socks5
        case "http":
            return .http
        case "vmess":
            return .vmess
        case "vless":
            return .vless
        case "trojan":
            return .trojan
        case "hysteria2":
            return .hysteria2
        case "relay":
            return .relay
        case "snell":
            return .snell
        default:
            throw ClashConfigError.invalidProxy(index: index, reason: "unsupported proxy type: \(rawType ?? "nil")")
        }
    }

    private static func parseRules(
        _ rawRules: [String]?,
        mode: ProxyMode,
        knownProxies: Set<String>,
        ruleProviders: [String: RuleSetProviderConfig]
    ) throws -> [ProxyRule] {
        guard let rawRules, !rawRules.isEmpty else {
            switch mode {
            case .rule:
                throw ClashConfigError.missingRules
            case .global, .direct:
                return []
            }
        }

        return try rawRules.enumerated().map { index, rawRule in
            let parts = rawRule.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let kind = parts.first, !kind.isEmpty else {
                throw ClashConfigError.invalidRule(index: index, reason: "missing rule type")
            }

            switch kind.uppercased() {
            case "DOMAIN":
                guard parts.count == 3 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "DOMAIN requires pattern and policy")
                }
                return .domain(
                    domain: parts[1],
                    policy: try parsePolicy(parts[2], knownProxies: knownProxies)
                )

            case "DOMAIN-SUFFIX":
                guard parts.count == 3 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "DOMAIN-SUFFIX requires pattern and policy")
                }
                return .domainSuffix(
                    suffix: parts[1],
                    policy: try parsePolicy(parts[2], knownProxies: knownProxies)
                )

            case "DOMAIN-KEYWORD":
                guard parts.count == 3 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "DOMAIN-KEYWORD requires keyword and policy")
                }
                return .domainKeyword(
                    keyword: parts[1],
                    policy: try parsePolicy(parts[2], knownProxies: knownProxies)
                )

            case "IP-CIDR":
                guard parts.count == 3 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "IP-CIDR requires CIDR and policy")
                }
                return .ipCIDR(
                    cidr: parts[1],
                    policy: try parsePolicy(parts[2], knownProxies: knownProxies)
                )

            case "IP-CIDR6":
                guard parts.count == 3 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "IP-CIDR6 requires CIDR and policy")
                }
                return .ipCIDR6(
                    cidr: parts[1],
                    policy: try parsePolicy(parts[2], knownProxies: knownProxies)
                )

            case "SRC-IP-CIDR":
                guard parts.count == 3 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "SRC-IP-CIDR requires CIDR and policy")
                }
                return .srcIPCIDR(
                    cidr: parts[1],
                    policy: try parsePolicy(parts[2], knownProxies: knownProxies)
                )

            case "SRC-PORT":
                guard parts.count == 3 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "SRC-PORT requires port and policy")
                }
                guard let port = Int(parts[1]), (1...65535).contains(port) else {
                    throw ClashConfigError.invalidRule(index: index, reason: "SRC-PORT requires a valid port number (1-65535)")
                }
                return .srcPort(
                    port: port,
                    policy: try parsePolicy(parts[2], knownProxies: knownProxies)
                )

            case "DST-PORT":
                guard parts.count == 3 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "DST-PORT requires port and policy")
                }
                guard let port = Int(parts[1]), (1...65535).contains(port) else {
                    throw ClashConfigError.invalidRule(index: index, reason: "DST-PORT requires a valid port number (1-65535)")
                }
                return .dstPort(
                    port: port,
                    policy: try parsePolicy(parts[2], knownProxies: knownProxies)
                )

            case "GEOIP":
                guard parts.count == 3 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "GEOIP requires country and policy")
                }
                return .geoIP(
                    countryCode: parts[1].uppercased(),
                    policy: try parsePolicy(parts[2], knownProxies: knownProxies)
                )

            case "NOT":
                guard parts.count == 4 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "NOT requires rule-type, value, and policy")
                }
                return .not(
                    ruleType: parts[1],
                    value: parts[2],
                    policy: try parsePolicy(parts[3], knownProxies: knownProxies)
                )

            case "REJECT":
                return .reject

            case "MATCH", "FINAL":
                guard parts.count == 2 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "MATCH requires policy")
                }
                return .final(policy: try parsePolicy(parts[1], knownProxies: knownProxies))

            case "RULE-SET":
                guard parts.count >= 2 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "RULE-SET requires provider name")
                }
                let providerName = parts[1]
                let policyName = parts.count > 2 ? parts[2] : "DIRECT"
                guard ruleProviders[providerName] != nil else {
                    throw ClashConfigError.unknownProxyReference(providerName)
                }
                // RULE-SET default policy can be DIRECT/REJECT or any known proxy.
                return .ruleSet(
                    name: providerName,
                    policy: try parsePolicyOrBuiltin(policyName, knownProxies: knownProxies)
                )

            default:
                throw ClashConfigError.invalidRule(index: index, reason: "unsupported rule type")
            }
        }
    }

    private static func parsePolicy(_ rawPolicy: String, knownProxies: Set<String>) throws -> RoutingPolicy {
        let normalized = rawPolicy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ClashConfigError.invalidRule(index: 0, reason: "policy is required")
        }

        switch normalized.uppercased() {
        case "DIRECT":
            return .direct
        case "REJECT":
            return .reject
        default:
            guard knownProxies.contains(normalized) else {
                throw ClashConfigError.unknownProxyReference(normalized)
            }
            return .proxyNode(name: normalized)
        }
    }

    /// Like parsePolicy but also accepts DIRECT/REJECT even if not in knownProxies.
    /// Used for RULE-SET default policies where the set's own rules carry their own policy.
    private static func parsePolicyOrBuiltin(_ rawPolicy: String, knownProxies: Set<String>) throws -> RoutingPolicy {
        let normalized = rawPolicy.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "DIRECT":
            return .direct
        case "REJECT":
            return .reject
        default:
            guard knownProxies.contains(rawPolicy) else {
                throw ClashConfigError.unknownProxyReference(rawPolicy)
            }
            return .proxyNode(name: rawPolicy)
        }
    }

    private static func parseProxyGroups(_ rawGroups: [ClashRawProxyGroup]?) throws -> [ProxyGroup] {
        guard let rawGroups, !rawGroups.isEmpty else { return [] }
        return try rawGroups.enumerated().map { index, group in
            guard let id = group.name, !id.isEmpty else {
                throw ClashConfigError.invalidProxy(index: index, reason: "proxy-group name is required")
            }
            guard let typeStr = group.type else {
                throw ClashConfigError.invalidProxy(index: index, reason: "proxy-group type is required")
            }
            let kind: ProxyGroupKind
            switch typeStr.lowercased() {
            case "select":
                kind = .select
            case "url-test":
                kind = .urlTest
            case "fallback":
                kind = .fallback
            case "load-balance":
                kind = .loadBalance
            default:
                throw ClashConfigError.invalidProxy(index: index, reason: "unsupported proxy-group type: \(typeStr)")
            }
            let strategy: LBStrategy?
            if let s = group.strategy {
                strategy = (s == "consistent-hashing") ? .consistentHashing : .roundRobin
            } else {
                strategy = nil
            }
            return ProxyGroup(
                id: id,
                kind: kind,
                proxies: group.proxies ?? [],
                interval: group.interval,
                tolerance: group.tolerance,
                strategy: strategy
            )
        }
    }

    private static func validateModeRequirements(
        mode: ProxyMode,
        proxies: [ProxyNode],
        rules: [ProxyRule]
    ) throws {
        switch mode {
        case .rule:
            guard !rules.isEmpty else {
                throw ClashConfigError.missingRules
            }
        case .global:
            guard !proxies.isEmpty else {
                throw ClashConfigError.missingProxies
            }
        case .direct:
            break
        }
    }

    private static func parseDNSPolicy(_ raw: ClashRawDNS?) -> DNSPolicy {
        guard let raw else {
            return .default
        }

        let primary: [DNSResolverEndpoint]
        if let ns = raw.nameserver, !ns.isEmpty {
            primary = ns.map { addr in
                let normalized = addr.lowercased()
                if normalized.hasPrefix("https://") {
                    return .doh(url: addr)
                } else if normalized.hasPrefix("tls://") {
                    let stripped = String(addr.dropFirst(6))
                    if stripped.contains(":") {
                        return DNSResolverEndpoint(kind: .dot, address: stripped)
                    } else {
                        return .dot(host: stripped)
                    }
                } else if normalized.hasPrefix("quic://") {
                    let stripped = String(addr.dropFirst(7))
                    if stripped.contains(":") {
                        return DNSResolverEndpoint(kind: .doq, address: stripped)
                    } else {
                        return .doq(host: stripped)
                    }
                } else if addr.contains(":") {
                    return DNSResolverEndpoint(kind: .udp, address: addr)
                } else {
                    return .udp(host: addr)
                }
            }
        } else {
            primary = []
        }

        let fb: [DNSResolverEndpoint]
        if let fallback = raw.fallback, !fallback.isEmpty {
            fb = fallback.map { addr in
                if addr.contains(":") {
                    return DNSResolverEndpoint(kind: .udp, address: addr)
                } else {
                    return .udp(host: addr)
                }
            }
        } else {
            fb = []
        }

        // Parse tls-nameserver (DoT entries) — add to primary resolvers.
        // Entries may be in "tls://host:port" format.
        var dotResolvers: [DNSResolverEndpoint] = []
        if let tlsNS = raw.tlsNameserver, !tlsNS.isEmpty {
            for addr in tlsNS {
                let normalized = addr.lowercased()
                if normalized.hasPrefix("https://") {
                    // Some configs may put DoH URLs in tls-nameserver
                    dotResolvers.append(.doh(url: addr))
                } else {
                    // Strip "tls://" prefix if present, then treat as DoT
                    let stripped = normalized.hasPrefix("tls://") ? String(addr.dropFirst(6)) : addr
                    if stripped.contains(":") {
                        dotResolvers.append(DNSResolverEndpoint(kind: .dot, address: stripped))
                    } else {
                        dotResolvers.append(.dot(host: stripped))
                    }
                }
            }
        }

        let allPrimary = primary + dotResolvers

        // Parse quic-nameserver (DoQ entries).
        var doqResolvers: [DNSResolverEndpoint] = []
        if let quicNS = raw.quicNameserver, !quicNS.isEmpty {
            for addr in quicNS {
                let normalized = addr.lowercased()
                if normalized.hasPrefix("quic://") {
                    let stripped = String(addr.dropFirst(7))  // drop "quic://"
                    if stripped.contains(":") {
                        doqResolvers.append(DNSResolverEndpoint(kind: .doq, address: stripped))
                    } else {
                        doqResolvers.append(.doq(host: stripped))
                    }
                } else if normalized.hasPrefix("https://") {
                    doqResolvers.append(.doh(url: addr))
                } else {
                    // Bare address — treat as DoQ on default port 853
                    if addr.contains(":") {
                        doqResolvers.append(DNSResolverEndpoint(kind: .doq, address: addr))
                    } else {
                        doqResolvers.append(.doq(host: addr))
                    }
                }
            }
        }

        let finalPrimary = allPrimary + doqResolvers

        return DNSPolicy(
            primaryResolvers: finalPrimary,
            fallbackResolvers: fb,
            domainPolicies: [],
            respectRules: raw.respectRules ?? false,
            fakeIPEnabled: raw.fakeIP ?? true,
            fakeIPCIDR: raw.fakeIPRange ?? "198.18.0.0/16",
            hosts: raw.hosts ?? [:]
        )
    }
    private static func parseRuleProviders(
        _ raw: [String: Any]?
    ) throws -> [String: RuleSetProviderConfig] {
        guard let raw, !raw.isEmpty else { return [:] }

        var providers: [String: RuleSetProviderConfig] = [:]
        for (name, value) in raw {
            guard let dict = value as? [String: Any],
                  let type = dict["type"] as? String,
                  let url = dict["url"] as? String,
                  let interval = dict["interval"] as? Int else {
                continue
            }

            let behaviorStr = (dict["behavior"] as? String) ?? "classical"
            let behavior: RuleSetBehavior
            switch behaviorStr {
            case "domain": behavior = .domain
            case "ipcidr": behavior = .ipcidr
            default: behavior = .classical
            }

            providers[name] = RuleSetProviderConfig(
                name: name,
                type: type,
                url: url,
                interval: interval,
                behavior: behavior
            )
        }
        return providers
    }

    private static func parseProxyProviders(
        _ raw: [String: Any]?
    ) throws -> [String: ProxyProviderConfig] {
        guard let raw, !raw.isEmpty else { return [:] }

        var providers: [String: ProxyProviderConfig] = [:]
        for (name, value) in raw {
            guard let dict = value as? [String: Any],
                  let type = dict["type"] as? String else {
                continue
            }

            let url = dict["url"] as? String
            let path = dict["path"] as? String
            let interval = dict["interval"] as? Int

            let healthCheckDict = dict["health-check"] as? [String: Any]
            let healthCheck: HealthCheckConfig?
            if let hc = healthCheckDict {
                healthCheck = HealthCheckConfig(
                    enable: (hc["enable"] as? Bool) ?? false,
                    url: hc["url"] as? String,
                    interval: hc["interval"] as? Int
                )
            } else {
                healthCheck = nil
            }

            providers[name] = ProxyProviderConfig(
                name: name,
                type: type,
                url: url,
                path: path,
                interval: interval,
                healthCheck: healthCheck
            )
        }
        return providers
    }
}

private struct ClashRawConfig: Decodable {
    let mode: String?
    let proxies: [ClashRawProxy]?
    let rules: [String]?
    var proxyGroups: [ClashRawProxyGroup]?
    let dns: ClashRawDNS?

    private enum CodingKeys: String, CodingKey {
        case mode, proxies, rules, dns
        case proxyGroups = "proxy-groups"
    }
}

private struct ClashRawDNS: Decodable {
    let enable: Bool?
    let nameserver: [String]?
    let fallback: [String]?
    let tlsNameserver: [String]?
    let quicNameserver: [String]?
    let fakeIP: Bool?
    let fakeIPRange: String?
    let respectRules: Bool?
    let defaultNameserver: [String]?
    let hosts: [String: String]?

    enum CodingKeys: String, CodingKey {
        case enable
        case nameserver
        case fallback
        case fakeIP = "fake-ip"
        case fakeIPRange = "fake-ip-range"
        case respectRules = "respect-rules"
        case defaultNameserver = "default-nameserver"
        case hosts
        case tlsNameserver = "tls-nameserver"
        case quicNameserver = "quic-nameserver"
    }
}

private struct ClashRawProxyGroup: Codable {
    let name: String?
    let `type`: String?
    let proxies: [String]?
    let interval: Int?
    let tolerance: Int?
    let strategy: String?

    private enum CodingKeys: String, CodingKey {
        case name, type, proxies, interval, tolerance, strategy
    }
}

private struct ClashRawProxy: Decodable {
    let name: String
    let type: String?
    let server: String
    let port: Int?
    let cipher: String?
    let password: String?
    let uuid: String?
    let alterId: Int?
    let security: String?
    let flow: String?
    let network: String?
    let tls: Bool?
    let sni: String?
    let alpn: [String]?
    let skipCertVerify: Bool?
    let wsOpts: WSOpts?
    let grpcOpts: GRPCOpts?
    let chain: String?
    let snellVersion: Int?

    struct WSOpts: Codable {
        let path: String?
        let headers: [String: String]?
    }

    struct GRPCOpts: Codable {
        let grpcServiceName: String?
        private enum CodingKeys: String, CodingKey {
            case grpcServiceName = "grpc-service-name"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name, type, server, port, cipher, password
        case uuid, alterId, security, flow, network, tls, sni, alpn
        case skipCertVerify = "skip-cert-verify"
        case wsOpts = "ws-opts"
        case grpcOpts = "grpc-opts"
        case chain
        case snellVersion = "version"
    }
}
