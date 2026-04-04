import Foundation

public struct ImportedProfile: Sendable {
    public let profile: TunnelProfile
    public let ruleSetProviders: [String: RuleSetProvider]

    public init(profile: TunnelProfile, ruleSetProviders: [String: RuleSetProvider]) {
        self.profile = profile
        self.ruleSetProviders = ruleSetProviders
    }
}

public struct ConfigImportService: Sendable {
    public init() {}

    public func importProfile(name: String, yaml: String) throws -> ImportedProfile {
        let (config, providers) = try ClashConfigParser.parse(yaml: yaml)
        return ImportedProfile(
            profile: TunnelProfile(name: name, config: config),
            ruleSetProviders: providers
        )
    }
}
