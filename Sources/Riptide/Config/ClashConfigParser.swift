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
    public static func parse(yaml: String) throws -> RiptideConfig {
        let raw: ClashRawConfig
        do {
            raw = try YAMLDecoder().decode(ClashRawConfig.self, from: yaml)
        } catch {
            throw ClashConfigError.invalidYAML(error.localizedDescription)
        }

        let mode = try parseMode(raw.mode)
        let proxies = try parseProxies(raw.proxies)
        let proxyNameSet = Set(proxies.map(\.name))
        let rules = try parseRules(raw.rules, knownProxies: proxyNameSet, mode: mode)
        try validateModeRequirements(mode: mode, proxies: proxies, rules: rules)

        let proxyGroups = try parseProxyGroups(raw.proxyGroups)
        let dnsPolicy = parseDNSPolicy(raw.dns)
        return RiptideConfig(mode: mode, proxies: proxies, rules: rules, proxyGroups: proxyGroups, dnsPolicy: dnsPolicy)
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
            guard let port = proxy.port, (1...65_535).contains(port) else {
                throw ClashConfigError.invalidProxy(index: index, reason: "valid port is required")
            }
            let kind = try parseProxyKind(proxy.type, index: index)

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

            case .socks5, .http, .vmess, .hysteria2:
                return ProxyNode(
                    name: proxy.name,
                    kind: kind,
                    server: proxy.server,
                    port: port,
                    cipher: proxy.cipher,
                    password: proxy.password
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
        default:
            throw ClashConfigError.invalidProxy(index: index, reason: "unsupported proxy type: \(rawType ?? "nil")")
        }
    }

    private static func parseRules(
        _ rawRules: [String]?,
        knownProxies: Set<String>,
        mode: ProxyMode
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

            case "GEOIP":
                guard parts.count == 3 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "GEOIP requires country and policy")
                }
                return .geoIP(
                    countryCode: parts[1].uppercased(),
                    policy: try parsePolicy(parts[2], knownProxies: knownProxies)
                )

            case "MATCH", "FINAL":
                guard parts.count == 2 else {
                    throw ClashConfigError.invalidRule(index: index, reason: "MATCH requires policy")
                }
                return .final(policy: try parsePolicy(parts[1], knownProxies: knownProxies))

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
        guard let raw, raw.enable != false else {
            return DNSPolicy(enable: false)
        }
        let enhancedMode: DNSEnhancedMode = (raw.enhancedMode == "fake-ip") ? .fakeIP : .realIP
        return DNSPolicy(
            enable: raw.enable ?? true,
            listen: raw.listen,
            enhancedMode: enhancedMode,
            fakeIPRange: raw.fakeIPRange ?? "198.18.0.0/15",
            fakeIPFilter: raw.fakeIPFilter ?? [],
            nameserver: raw.nameserver ?? ["8.8.8.8", "1.1.1.1"],
            fallback: raw.fallback,
            nameserverPolicy: raw.nameserverPolicy ?? [:]
        )
    }
}

private struct ClashRawDNS: Codable {
    let enable: Bool?
    let listen: String?
    let enhancedMode: String?
    let fakeIPRange: String?
    let fakeIPFilter: [String]?
    let nameserver: [String]?
    let fallback: [String]?
    let nameserverPolicy: [String: [String]]?

    private enum CodingKeys: String, CodingKey {
        case enable, listen, nameserver, fallback, nameserverPolicy
        case enhancedMode = "enhanced-mode"
        case fakeIPRange = "fake-ip-range"
        case fakeIPFilter = "fake-ip-filter"
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
    }
}
