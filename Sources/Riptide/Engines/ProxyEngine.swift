import Foundation

public enum ProxyEngineKind: String, Sendable, Codable {
    case mihomo
    case singbox
    case swift
}

public protocol ProxyEngine: Sendable {
    var name: String { get }
    var kind: ProxyEngineKind { get }
    var supportedProxyKinds: Set<ProxyKind> { get }
    func generateConfig(from nodes: [ProxyNode]) throws -> Data
}
