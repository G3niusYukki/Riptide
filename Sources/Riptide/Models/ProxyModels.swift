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
}

public struct ProxyNode: Equatable, Sendable {
    public let name: String
    public let kind: ProxyKind
    public let server: String
    public let port: Int
    public let cipher: String?
    public let password: String?

    public init(
        name: String,
        kind: ProxyKind,
        server: String,
        port: Int,
        cipher: String? = nil,
        password: String? = nil
    ) {
        self.name = name
        self.kind = kind
        self.server = server
        self.port = port
        self.cipher = cipher
        self.password = password
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
    case geoIP(countryCode: String, policy: RoutingPolicy)
    case final(policy: RoutingPolicy)
}

public struct RiptideConfig: Equatable, Sendable {
    public let mode: ProxyMode
    public let proxies: [ProxyNode]
    public let rules: [ProxyRule]

    public init(mode: ProxyMode, proxies: [ProxyNode], rules: [ProxyRule]) {
        self.mode = mode
        self.proxies = proxies
        self.rules = rules
    }
}
