import Foundation

// MARK: - Editable Proxy Node

/// A mutable version of ProxyNode for editing
public struct EditableProxyNode: Equatable, Sendable {
    public var name: String
    public var kind: ProxyKind
    public var server: String
    public var port: Int
    public var cipher: String?
    public var password: String?
    public var uuid: String?
    public var flow: String?
    public var alterId: Int?
    public var security: String?
    public var sni: String?
    public var alpn: [String]?
    public var skipCertVerify: Bool?
    public var network: String?
    public var wsPath: String?
    public var wsHost: String?
    public var grpcServiceName: String?
    public var chainProxyName: String?

    public init(
        name: String = "",
        kind: ProxyKind = .shadowsocks,
        server: String = "",
        port: Int = 443,
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

    /// Creates an EditableProxyNode from a ProxyNode
    public init(from node: ProxyNode) {
        self.name = node.name
        self.kind = node.kind
        self.server = node.server
        self.port = node.port
        self.cipher = node.cipher
        self.password = node.password
        self.uuid = node.uuid
        self.flow = node.flow
        self.alterId = node.alterId
        self.security = node.security
        self.sni = node.sni
        self.alpn = node.alpn
        self.skipCertVerify = node.skipCertVerify
        self.network = node.network
        self.wsPath = node.wsPath
        self.wsHost = node.wsHost
        self.grpcServiceName = node.grpcServiceName
        self.chainProxyName = node.chainProxyName
    }

    /// Converts back to an immutable ProxyNode
    public func toProxyNode() -> ProxyNode {
        ProxyNode(
            name: name,
            kind: kind,
            server: server,
            port: port,
            cipher: cipher,
            password: password,
            uuid: uuid,
            flow: flow,
            alterId: alterId,
            security: security,
            sni: sni,
            alpn: alpn,
            skipCertVerify: skipCertVerify,
            network: network,
            wsPath: wsPath,
            wsHost: wsHost,
            grpcServiceName: grpcServiceName,
            chainProxyName: chainProxyName
        )
    }

    /// Default values for a new node of the specified kind
    public static func defaults(for kind: ProxyKind) -> EditableProxyNode {
        var node = EditableProxyNode(kind: kind)

        switch kind {
        case .shadowsocks:
            node.cipher = "aes-256-gcm"
            node.port = 8388

        case .vmess:
            node.security = "auto"
            node.alterId = 0
            node.port = 443

        case .vless:
            node.flow = "xtls-rprx-vision"
            node.port = 443

        case .trojan:
            node.port = 443

        case .hysteria2:
            node.port = 443

        case .http, .socks5:
            node.port = kind == .http ? 8080 : 1080

        case .relay:
            node.port = 0
        }

        return node
    }
}

// MARK: - Field Requirements

/// Specifies which fields are required for each proxy kind
public struct ProxyFieldRequirements {
    public let requiresCipher: Bool
    public let requiresPassword: Bool
    public let requiresUUID: Bool
    public let requiresSNI: Bool
    public let supportsNetwork: Bool
    public let supportsWebSocket: Bool

    public static func forKind(_ kind: ProxyKind) -> ProxyFieldRequirements {
        switch kind {
        case .shadowsocks:
            return ProxyFieldRequirements(
                requiresCipher: true,
                requiresPassword: true,
                requiresUUID: false,
                requiresSNI: false,
                supportsNetwork: false,
                supportsWebSocket: false
            )

        case .vmess:
            return ProxyFieldRequirements(
                requiresCipher: false,
                requiresPassword: false,
                requiresUUID: true,
                requiresSNI: false,
                supportsNetwork: true,
                supportsWebSocket: true
            )

        case .vless:
            return ProxyFieldRequirements(
                requiresCipher: false,
                requiresPassword: false,
                requiresUUID: true,
                requiresSNI: false,
                supportsNetwork: true,
                supportsWebSocket: true
            )

        case .trojan:
            return ProxyFieldRequirements(
                requiresCipher: false,
                requiresPassword: true,
                requiresUUID: false,
                requiresSNI: true,
                supportsNetwork: true,
                supportsWebSocket: true
            )

        case .hysteria2:
            return ProxyFieldRequirements(
                requiresCipher: false,
                requiresPassword: true,
                requiresUUID: false,
                requiresSNI: true,
                supportsNetwork: false,
                supportsWebSocket: false
            )

        case .http, .socks5, .relay:
            return ProxyFieldRequirements(
                requiresCipher: false,
                requiresPassword: false,
                requiresUUID: false,
                requiresSNI: false,
                supportsNetwork: false,
                supportsWebSocket: false
            )
        }
    }
}

// MARK: - Common Values

/// Common values for proxy configuration fields
public enum ProxyFieldOptions {
    /// Common Shadowsocks ciphers
    public static let shadowsocksCiphers = [
        "aes-128-gcm",
        "aes-192-gcm",
        "aes-256-gcm",
        "chacha20-ietf-poly1305",
        "xchacha20-ietf-poly1305",
        "aes-128-ctr",
        "aes-192-ctr",
        "aes-256-ctr",
        "aes-128-cfb",
        "aes-192-cfb",
        "aes-256-cfb",
        "rc4-md5",
        "none"
    ]

    /// Common VMess/VLESS security options
    public static let vmessSecurityOptions = [
        "auto",
        "aes-128-gcm",
        "chacha20-poly1305",
        "none"
    ]

    /// Common VLESS flow options
    public static let vlessFlowOptions = [
        "",
        "xtls-rprx-vision",
        "xtls-rprx-vision-udp443"
    ]

    /// Common network types
    public static let networkTypes = [
        "tcp",
        "ws",
        "h2",
        "grpc"
    ]
}
