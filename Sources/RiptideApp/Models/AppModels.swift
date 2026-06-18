import Foundation
import Riptide

// MARK: - App-Shell Types

/// App-layer profile wrapper around a Riptide `TunnelProfile`.
public struct Profile: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let config: RiptideConfig
    public let source: ProfileSource

    public init(id: UUID = UUID(), name: String, config: RiptideConfig, source: ProfileSource = .local) {
        self.id = id
        self.name = name
        self.config = config
        self.source = source
    }

    /// Convert to a `TunnelProfile` for use by the tunnel runtime.
    public var tunnelProfile: TunnelProfile {
        TunnelProfile(name: name, config: config)
    }
}

/// Where a profile came from.
public enum ProfileSource: Equatable {
    case local
    case subscription(id: UUID, name: String)
}

// MARK: - Display Models

/// Display-friendly subscription model for the UI layer.
public struct SubscriptionDisplay: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let url: String
    public let autoUpdate: Bool
    public let lastUpdated: Date?
    public let lastError: String?
    public let profileCount: Int
    public let userinfo: SubscriptionUserinfo?

    public init(
        id: UUID, name: String, url: String, autoUpdate: Bool,
        lastUpdated: Date?, lastError: String?, profileCount: Int = 0,
        userinfo: SubscriptionUserinfo? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.autoUpdate = autoUpdate
        self.lastUpdated = lastUpdated
        self.lastError = lastError
        self.profileCount = profileCount
        self.userinfo = userinfo
    }
}

/// Display-friendly rule set provider model for the UI layer.
public struct RuleSetDisplay: Identifiable, Equatable {
    public let id: String  // provider name
    public let name: String
    public let url: String
    public let interval: Int
    public let ruleCount: Int
    public let lastUpdated: Date?

    public init(id: String, name: String, url: String, interval: Int, ruleCount: Int, lastUpdated: Date? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.interval = interval
        self.ruleCount = ruleCount
        self.lastUpdated = lastUpdated
    }
}

public struct ProxyNodeDisplay: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let kind: ProxyKind
    public let delayMs: Int?
    public let isSelected: Bool
    public let status: ProxyStatus

    public enum ProxyStatus: Equatable {
        case available
        case timeout
        case error
    }
}

public struct ProxyGroupDisplay: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let kind: ProxyGroupKind
    public let nodes: [ProxyNodeDisplay]
    public let selectedNodeName: String?
}

public struct ConnectionInfo: Identifiable, Hashable {
    public let id: UUID
    /// Raw backend connection ID — use this for close operations.
    public let backendId: String
    public let host: String
    public let port: Int
    public let `protocol`: String
    public let proxyName: String
    public let connectionCount: Int

    // Detail fields for connection detail panel
    public let sourceIP: String?
    public let sourcePort: String?
    public let destinationIP: String?
    public let destinationPort: String?
    public let matchedRule: String?
    public let rulePayload: String?
    public let chain: [String]
    public let startTime: String?
    public let uploadBytes: Int
    public let downloadBytes: Int
    public let networkType: String?

    public init(
        id: UUID, backendId: String, host: String, port: Int,
        `protocol`: String, proxyName: String, connectionCount: Int,
        sourceIP: String? = nil, sourcePort: String? = nil,
        destinationIP: String? = nil, destinationPort: String? = nil,
        matchedRule: String? = nil, rulePayload: String? = nil,
        chain: [String] = [], startTime: String? = nil,
        uploadBytes: Int = 0, downloadBytes: Int = 0,
        networkType: String? = nil
    ) {
        self.id = id
        self.backendId = backendId
        self.host = host
        self.port = port
        self.protocol = `protocol`
        self.proxyName = proxyName
        self.connectionCount = connectionCount
        self.sourceIP = sourceIP
        self.sourcePort = sourcePort
        self.destinationIP = destinationIP
        self.destinationPort = destinationPort
        self.matchedRule = matchedRule
        self.rulePayload = rulePayload
        self.chain = chain
        self.startTime = startTime
        self.uploadBytes = uploadBytes
        self.downloadBytes = downloadBytes
        self.networkType = networkType
    }
}

public struct RuleMatchLog: Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let domain: String
    public let matchedRule: String
    public let resolvedNode: String
}

public enum ConnectionMode: String, Equatable, CaseIterable {
    case systemProxy
    case tun

    public static var productAvailableModes: [ConnectionMode] {
        RuntimeMode.productAvailableModes.map { mode in
            switch mode {
            case .systemProxy:
                return .systemProxy
            case .tun:
                return .tun
            }
        }
    }

    public var displayName: String {
        switch self {
        case .systemProxy:
            return "系统代理"
        case .tun:
            return "TUN模式"
        }
    }
}
