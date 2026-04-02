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

        return RiptideConfig(mode: mode, proxies: proxies, rules: rules)
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

            case .socks5, .http:
                return ProxyNode(
                    name: proxy.name,
                    kind: kind,
                    server: proxy.server,
                    port: port
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
        default:
            throw ClashConfigError.invalidProxy(index: index, reason: "unsupported proxy type")
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
}

private struct ClashRawConfig: Decodable {
    let mode: String?
    let proxies: [ClashRawProxy]?
    let rules: [String]?
}

private struct ClashRawProxy: Decodable {
    let name: String
    let type: String?
    let server: String
    let port: Int?
    let cipher: String?
    let password: String?
}
