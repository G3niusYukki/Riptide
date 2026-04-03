import Foundation

public enum DNSEnhancedMode: Equatable, Sendable {
    case realIP
    case fakeIP
}

public struct DNSPolicy: Equatable, Sendable {
    public let enable: Bool
    public let listen: String?
    public let enhancedMode: DNSEnhancedMode
    public let fakeIPRange: String?
    public let fakeIPFilter: [String]
    public let nameserver: [String]
    public let fallback: [String]?
    public let nameserverPolicy: [String: [String]]

    public init(
        enable: Bool = true,
        listen: String? = nil,
        enhancedMode: DNSEnhancedMode = .realIP,
        fakeIPRange: String? = "198.18.0.0/15",
        fakeIPFilter: [String] = [],
        nameserver: [String] = ["8.8.8.8", "1.1.1.1"],
        fallback: [String]? = nil,
        nameserverPolicy: [String: [String]] = [:]
    ) {
        self.enable = enable
        self.listen = listen
        self.enhancedMode = enhancedMode
        self.fakeIPRange = fakeIPRange
        self.fakeIPFilter = fakeIPFilter
        self.nameserver = nameserver
        self.fallback = fallback
        self.nameserverPolicy = nameserverPolicy
    }
}
