import Foundation

/// The source of a profile — locally imported or fetched from a subscription.
public enum ProfileSourceKind: String, Sendable, Codable, Equatable {
    case local
    case subscription
}

/// A persisted profile entry with source metadata.
public struct Profile: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var sourceKind: ProfileSourceKind
    /// Raw YAML configuration string.
    public var rawYAML: String
    /// Subscription URL, populated only when sourceKind is .subscription.
    public var subscriptionURL: URL?
    /// When this profile was last refreshed from its subscription source.
    public var lastRefresh: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        sourceKind: ProfileSourceKind,
        rawYAML: String,
        subscriptionURL: URL? = nil,
        lastRefresh: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.sourceKind = sourceKind
        self.rawYAML = rawYAML
        self.subscriptionURL = subscriptionURL
        self.lastRefresh = lastRefresh
    }
}

/// Errors from profile store operations.
public enum ProfileStoreError: Error, Equatable, Sendable {
    case notFound(UUID)
    case parseFailed(String)
    case persistenceFailed(String)
    case refreshFailed(UUID, String)
}

/// Actor-backed profile persistence layer.
/// Persists profiles to a JSON file in the application support directory.
public actor ProfileStore {
    private var profiles: [UUID: Profile]
    private var currentProfileID: UUID?
    private let fileURL: URL

    public init(fileName: String = "profiles.json") throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Riptide", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(fileName)
        self.profiles = [:]
        self.currentProfileID = nil
        let loaded = try Self.loadFromDisk(fileURL: fileURL)
        self.profiles = loaded.profiles
        self.currentProfileID = loaded.currentProfileID
    }

    /// Import a YAML config as a new local profile and make it active.
    public func importProfile(name: String, yaml: String) throws -> Profile {
        let profile = Profile(
            name: name,
            sourceKind: .local,
            rawYAML: yaml
        )
        profiles[profile.id] = profile
        currentProfileID = profile.id
        try saveToDisk()
        return profile
    }

    /// Add a subscription-backed profile. Does not set it as active.
    public func addSubscriptionProfile(name: String, yaml: String, subscriptionURL: URL) throws -> Profile {
        let profile = Profile(
            name: name,
            sourceKind: .subscription,
            rawYAML: yaml,
            subscriptionURL: subscriptionURL,
            lastRefresh: Date()
        )
        profiles[profile.id] = profile
        try saveToDisk()
        return profile
    }

    /// All persisted profiles.
    public func allProfiles() -> [Profile] {
        Array(profiles.values).sorted { $0.name < $1.name }
    }

    /// A profile by ID.
    public func profile(id: UUID) -> Profile? {
        profiles[id]
    }

    /// The currently active profile, if any.
    public func currentProfile() -> Profile? {
        guard let id = currentProfileID else { return nil }
        return profiles[id]
    }

    /// Switch to a different profile by ID.
    public func selectProfile(id: UUID) throws {
        guard profiles[id] != nil else {
            throw ProfileStoreError.notFound(id)
        }
        currentProfileID = id
        try saveToDisk()
    }

    /// Delete a profile by ID.
    public func deleteProfile(id: UUID) throws {
        guard let removed = profiles.removeValue(forKey: id) else {
            throw ProfileStoreError.notFound(id)
        }
        _ = removed
        if currentProfileID == id {
            currentProfileID = nil
        }
        try saveToDisk()
    }

    /// Refresh a subscription-backed profile by re-fetching its content.
    /// Returns the updated profile.
    public func refreshProfile(id: UUID, using subscriptionManager: SubscriptionManager) async throws -> Profile {
        guard var profile = profiles[id] else {
            throw ProfileStoreError.notFound(id)
        }
        guard profile.sourceKind == .subscription,
              let url = profile.subscriptionURL else {
            throw ProfileStoreError.refreshFailed(id, "not a subscription profile")
        }

        let update = try await subscriptionManager.fetchSubscription(url: url)
        let updatedYAML = buildYAML(nodes: update.nodes, name: profile.name)
        profile.rawYAML = updatedYAML
        profile.lastRefresh = Date()
        profiles[id] = profile
        try saveToDisk()
        return profile
    }

    private func saveToDisk() throws {
        let wrapper = Wrapper(profiles: profiles, currentProfileID: currentProfileID)
        let data = try JSONEncoder().encode(wrapper)
        try data.write(to: fileURL)
    }

    private static func loadFromDisk(fileURL: URL) throws -> (profiles: [UUID: Profile], currentProfileID: UUID?) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ([:], nil) }
        do {
            let data = try Data(contentsOf: fileURL)
            let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
            return (wrapper.profiles, wrapper.currentProfileID)
        } catch {
            throw ProfileStoreError.persistenceFailed(String(describing: error))
        }
    }

    private func buildYAML(nodes: [ProxyNode], name: String) -> String {
        var lines = ["mode: rule", "proxies:"]
        for node in nodes {
            let typeStr: String
            switch node.kind {
            case .socks5: typeStr = "socks5"
            case .http: typeStr = "http"
            case .shadowsocks: typeStr = "ss"
            default: typeStr = "http"
            }
            lines.append("  - name: \"\(node.name)\"")
            lines.append("    type: \(typeStr)")
            lines.append("    server: \"\(node.server)\"")
            lines.append("    port: \(node.port)")
            if let cipher = node.cipher {
                lines.append("    cipher: \(cipher)")
            }
            if let password = node.password {
                lines.append("    password: \(password)")
            }
        }
        lines.append("rules:")
        lines.append("  - MATCH,\(nodes.first?.name ?? "DIRECT")")
        return lines.joined(separator: "\n")
    }
}

private struct Wrapper: Codable {
    let profiles: [UUID: Profile]
    let currentProfileID: UUID?
}
