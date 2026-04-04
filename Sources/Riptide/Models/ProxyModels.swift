import Foundation

public enum ProxyMode: String, Equatable, Sendable {
    case rule
    case global
    case direct
}

public enum ProxyKind: Equatable, Sendable {
    case http
    case socks5
    case shadowsocks
    case vmess
    case vless
    case trojan
    case hysteria2
    case relay
}

public struct ProxyNode: Equatable, Sendable {
    public let name: String
    public let kind: ProxyKind
    public let server: String
    public let port: Int
    public let cipher: String?
    public let password: String?
    public let uuid: String?
    public let flow: String?
    public let alterId: Int?
    public let security: String?
    public let sni: String?
    public let alpn: [String]?
    public let skipCertVerify: Bool?
    public let network: String?
    public let wsPath: String?
    public let wsHost: String?
    public let grpcServiceName: String?
    public let chainProxyName: String?

    public init(
        name: String,
        kind: ProxyKind,
        server: String,
        port: Int,
        cipher: String? = nil,
        password: String? = nil,
        uuid: String? = nil,
        flow: String? = nil,
        alterId: Int? = nil,
        security: String? = nil,
        sni: String? = nil,
        alpn: [String]? = nil,
        skipCertVerify: Bool? = nil,
        network: String? = nil,
        wsPath: String? = nil,
        wsHost: String? = nil,
        grpcServiceName: String? = nil,
        chainProxyName: String? = nil
    ) {
        self.name = name
        self.kind = kind
        self.server = server
        self.port = port
        self.cipher = cipher
        self.password = password
        self.uuid = uuid
        self.flow = flow
        self.alterId = alterId
        self.security = security
        self.sni = sni
        self.alpn = alpn
        self.skipCertVerify = skipCertVerify
        self.network = network
        self.wsPath = wsPath
        self.wsHost = wsHost
        self.grpcServiceName = grpcServiceName
        self.chainProxyName = chainProxyName
    }
}

public enum RoutingPolicy: Equatable, Sendable {
    case direct
    case reject
    case proxyNode(name: String)
}

public enum ProxyRule: Equatable, Sendable {
    case domain(domain: String, policy: RoutingPolicy)
    case domainSuffix(suffix: String, policy: RoutingPolicy)
    case domainKeyword(keyword: String, policy: RoutingPolicy)
    case ipCIDR(cidr: String, policy: RoutingPolicy)
    case ipCIDR6(cidr: String, policy: RoutingPolicy)
    case srcIPCIDR(cidr: String, policy: RoutingPolicy)
    case srcPort(port: Int, policy: RoutingPolicy)
    case dstPort(port: Int, policy: RoutingPolicy)
    case processName(name: String, policy: RoutingPolicy)
    case geoIP(countryCode: String, policy: RoutingPolicy)
    case ipASN(asn: Int, policy: RoutingPolicy)
    case geoSite(code: String, category: String, policy: RoutingPolicy)
    case ruleSet(name: String, policy: RoutingPolicy)
    case script(code: String, policy: RoutingPolicy)
    case matchAll
    case final(policy: RoutingPolicy)
}

public struct RiptideConfig: Equatable, Sendable {
    public let mode: ProxyMode
    public let proxies: [ProxyNode]
    public let rules: [ProxyRule]
    public let proxyGroups: [ProxyGroup]
    public let dnsPolicy: DNSPolicy
    /// Static rule-set provider configurations parsed from the config file.
    public let ruleProviders: [String: RuleSetProviderConfig]
    /// Static proxy provider configurations parsed from the config file.
    public let proxyProviders: [String: ProxyProviderConfig]

    public init(
        mode: ProxyMode,
        proxies: [ProxyNode],
        rules: [ProxyRule],
        proxyGroups: [ProxyGroup] = [],
        dnsPolicy: DNSPolicy = .default,
        ruleProviders: [String: RuleSetProviderConfig] = [:],
        proxyProviders: [String: ProxyProviderConfig] = [:]
    ) {
        self.mode = mode
        self.proxies = proxies
        self.rules = rules
        self.proxyGroups = proxyGroups
        self.dnsPolicy = dnsPolicy
        self.ruleProviders = ruleProviders
        self.proxyProviders = proxyProviders
    }
}

/// Configuration for a Clash-style proxy provider.
public struct ProxyProviderConfig: Codable, Sendable, Equatable {
    public let name: String
    public let type: String  // "http" or "file"
    public let url: String?
    public let path: String?
    public let interval: Int?  // seconds
    public let healthCheck: HealthCheckConfig?

    public init(
        name: String,
        type: String,
        url: String? = nil,
        path: String? = nil,
        interval: Int? = nil,
        healthCheck: HealthCheckConfig? = nil
    ) {
        self.name = name
        self.type = type
        self.url = url
        self.path = path
        self.interval = interval
        self.healthCheck = healthCheck
    }
}

/// Health check configuration for a proxy provider.
public struct HealthCheckConfig: Codable, Sendable, Equatable {
    public let enable: Bool
    public let url: String?
    public let interval: Int?

    public init(enable: Bool, url: String? = nil, interval: Int? = nil) {
        self.enable = enable
        self.url = url
        self.interval = interval
    }
}
