import Foundation

public struct ImportedProfile: Equatable, Sendable {
    public let profile: TunnelProfile

    public init(profile: TunnelProfile) {
        self.profile = profile
    }
}

public struct ConfigImportService: Sendable {
    public init() {}

    public func importProfile(name: String, yaml: String) throws -> ImportedProfile {
        let config = try ClashConfigParser.parse(yaml: yaml)
        return ImportedProfile(profile: TunnelProfile(name: name, config: config))
    }
}
