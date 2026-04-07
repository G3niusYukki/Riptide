import Foundation

public struct RuleProviderConfig: Sendable, Equatable {
    public let name: String
    public let type: RuleProviderType
    public let url: URL?
    public let path: String?
    public let updateInterval: Int?
    
    public enum RuleProviderType: String, Sendable {
        case http
        case file
    }
    
    public init(name: String, type: RuleProviderType, url: URL? = nil, path: String? = nil, updateInterval: Int? = nil) {
        self.name = name
        self.type = type
        self.url = url
        self.path = path
        self.updateInterval = updateInterval
    }
}

public actor RuleProvider: Identifiable {
    public let id: UUID
    public let config: RuleProviderConfig
    private var rules: [ProxyRule] = []
    private var lastUpdated: Date?
    
    public init(config: RuleProviderConfig) {
        self.id = UUID()
        self.config = config
    }
    
    public func update() async throws {
        let newRules: [ProxyRule]
        
        switch config.type {
        case .http:
            guard let url = config.url else { return }
            newRules = try await fetchRules(from: url)
        case .file:
            guard let path = config.path else { return }
            newRules = try await loadRules(from: path)
        }
        
        self.rules = newRules
        self.lastUpdated = Date()
    }
    
    public func getRules() -> [ProxyRule] {
        rules
    }
    
    public func getLastUpdated() -> Date? {
        lastUpdated
    }
    
    private func fetchRules(from url: URL) async throws -> [ProxyRule] {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try parseRules(from: data)
    }
    
    private func loadRules(from path: String) async throws -> [ProxyRule] {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try parseRules(from: data)
    }
    
    private func parseRules(from data: Data) throws -> [ProxyRule] {
        // Simplified implementation - return empty array for now
        // Full implementation would parse YAML/JSON rule files
        return []
    }
}
