import Foundation

/// A persisted user override: a partial YAML that overlays on top of an active profile.
/// Raw YAML is stored verbatim (comments, key order preserved) for git-friendliness
/// and round-trip fidelity.
public struct Override: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var rawYAML: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        rawYAML: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rawYAML = rawYAML
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
