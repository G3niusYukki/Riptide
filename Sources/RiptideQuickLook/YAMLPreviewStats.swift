import Foundation

/// A trimmed, presentation-friendly projection of a single proxy node
/// extracted from a YAML configuration file.
///
/// The full `ProxyNode` model from the `Riptide` library carries many
/// protocol-specific fields (cipher, password, UUID, Reality keys,
/// WireGuard keys, …) that we deliberately do **not** surface in the
/// Quick Look preview. Showing credentials in a Finder preview pane
/// would be a privacy hazard (the file is typically open in a
/// viewer that other apps can screenshot).
public struct YAMLPreviewNode: Equatable, Sendable, Hashable {
    public let name: String
    public let rawType: String
    public let server: String

    public init(name: String, type: String, server: String) {
        self.name = name
        self.rawType = type
        self.server = server
    }

    /// A human-readable display name for the protocol type. Falls back
    /// to the raw string uppercased when the protocol is unknown so the
    /// preview is still informative for future protocol additions.
    public var displayType: String {
        YAMLPreviewParser.displayType(forRawType: rawType)
    }
}

/// Aggregated statistics computed from a Clash-style YAML configuration.
///
/// The values are used to render the Finder Quick Look preview. Everything
/// here is `Sendable` so the parser can run off the main thread when the
/// preview extension is wired up in a real `.appex`.
public struct YAMLPreviewStats: Equatable, Sendable {
    public var proxyCount: Int
    public var groupCount: Int
    public var ruleCount: Int
    public var protocolBreakdown: [String: Int]
    public var firstNodes: [YAMLPreviewNode]
    public var sanitizedSubscriptionURL: String?
    public var updatedAt: Date?
    public var isSubscription: Bool

    public init(
        proxyCount: Int = 0,
        groupCount: Int = 0,
        ruleCount: Int = 0,
        protocolBreakdown: [String: Int] = [:],
        firstNodes: [YAMLPreviewNode] = [],
        sanitizedSubscriptionURL: String? = nil,
        updatedAt: Date? = nil,
        isSubscription: Bool = false
    ) {
        self.proxyCount = proxyCount
        self.groupCount = groupCount
        self.ruleCount = ruleCount
        self.protocolBreakdown = protocolBreakdown
        self.firstNodes = firstNodes
        self.sanitizedSubscriptionURL = sanitizedSubscriptionURL
        self.updatedAt = updatedAt
        self.isSubscription = isSubscription
    }

    /// A zero-value stats object used as a safe default when the source
    /// YAML cannot be read or parsed.
    public static let empty = YAMLPreviewStats()
}
