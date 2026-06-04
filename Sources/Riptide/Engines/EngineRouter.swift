import Foundation

public struct EngineRouter: Sendable {
    public enum Policy: Sendable, Equatable {
        case defaultMihomo
        case explicitSingbox
    }

    public let policy: Policy
    public init(policy: Policy) { self.policy = policy }

    // MARK: - Routing

    public func engine(for kind: ProxyKind) -> ProxyEngineKind {
        switch kind {
        case .reality, .anytls:
            return .singbox
        default:
            return policy == .explicitSingbox ? .singbox : .mihomo
        }
    }
}
