import Foundation
import Riptide
import Yams

// MARK: - Config Merge ViewModel

/// View model for the config merge UI.
/// Manages loading merge sources, previewing diffs, and applying merges.
@Observable
public final class ConfigMergeViewModel: @unchecked Sendable {

    // MARK: - State
    private(set) var currentConfig: RiptideConfig?
    private(set) var currentYAML: String = ""
    private(set) var mergeSources: [MergeSource] = []
    private(set) var previewResult: MergePreview?
    private(set) var isMerging = false
    private(set) var error: String?

    // MARK: - Dependencies
    private let profileStore: ProfileStore
    private var currentProfile: Riptide.Profile?

    public init(profileStore: ProfileStore) {
        self.profileStore = profileStore
    }

    // MARK: - Load

    public func loadCurrentProfile() async {
        currentProfile = await profileStore.currentProfile()
        guard let profile = currentProfile else {
            currentConfig = nil
            currentYAML = ""
            return
        }
        currentYAML = profile.rawYAML
        currentConfig = try? ClashConfigParser.parse(yaml: profile.rawYAML).0
    }

    // MARK: - Add Merge Source

    public func addFileSource(url: URL) {
        guard let data = try? Data(contentsOf: url),
              let yaml = String(data: data, encoding: .utf8) else {
            error = "无法读取文件: \(url.lastPathComponent)"
            return
        }

        let source = MergeSource(
            name: url.deletingPathExtension().lastPathComponent,
            yaml: yaml,
            kind: .file(url)
        )
        mergeSources.append(source)
        previewResult = nil
    }

    public func addYAMLSource(name: String, yaml: String) {
        let source = MergeSource(name: name, yaml: yaml, kind: .manual)
        mergeSources.append(source)
        previewResult = nil
    }

    public func removeSource(at offsets: IndexSet) {
        mergeSources.remove(atOffsets: offsets)
        previewResult = nil
    }

    public func removeSource(_ source: MergeSource) {
        mergeSources.removeAll { $0.id == source.id }
        previewResult = nil
    }

    // MARK: - Preview

    public func generatePreview() {
        guard let baseConfig = currentConfig else {
            error = "没有加载的配置"
            return
        }

        do {
            // Merge all sources
            let mergedConfig = try ConfigMerger.merge(
                base: baseConfig,
                mergeYAMLs: mergeSources.map { $0.yaml }
            )

            // Generate merged YAML
            let mergedYAML = try Yams.dump(object: configToDict(mergedConfig))

            // Compute diff summary
            let diff = computeDiff(base: baseConfig, merged: mergedConfig)

            previewResult = MergePreview(
                mergedConfig: mergedConfig,
                mergedYAML: mergedYAML,
                diff: diff
            )
            error = nil
        } catch {
            self.error = "合并预览失败: \(error.localizedDescription)"
            previewResult = nil
        }
    }

    // MARK: - Apply Merge

    public func applyMerge() async throws {
        guard let preview = previewResult,
              let profile = currentProfile else {
            error = "请先生成预览"
            return
        }

        isMerging = true
        defer { isMerging = false }

        _ = try await profileStore.importProfile(
            name: profile.name,
            yaml: preview.mergedYAML
        )

        // Reload
        await loadCurrentProfile()
        mergeSources = []
        previewResult = nil
    }

    // MARK: - Helpers

    private func configToDict(_ config: RiptideConfig) -> [String: Any] {
        var dict: [String: Any] = ["mode": config.mode.rawValue]

        if !config.proxies.isEmpty {
            dict["proxies"] = config.proxies.map { proxyToDict($0) }
        }

        if !config.proxyGroups.isEmpty {
            dict["proxy-groups"] = config.proxyGroups.map { groupToDict($0) }
        }

        if !config.rules.isEmpty {
            dict["rules"] = config.rules.map { ruleToString($0) }
        }

        return dict
    }

    private func groupToDict(_ group: ProxyGroup) -> [String: Any] {
        var dict: [String: Any] = [
            "name": group.id,
            "type": group.kind.rawValue,
            "proxies": group.proxies
        ]
        if let interval = group.interval { dict["interval"] = interval }
        if let tolerance = group.tolerance { dict["tolerance"] = tolerance }
        if let strategy = group.strategy { dict["strategy"] = strategy.rawValue }
        return dict
    }

    private func proxyToDict(_ node: ProxyNode) -> [String: Any] {
        var dict: [String: Any] = [
            "name": node.name,
            "type": node.kind.mihomoType,
            "server": node.server,
            "port": node.port
        ]
        if let cipher = node.cipher { dict["cipher"] = cipher }
        if let password = node.password { dict["password"] = password }
        if let uuid = node.uuid { dict["uuid"] = uuid }
        return dict
    }

    private func ruleToString(_ rule: ProxyRule) -> String {
        switch rule {
        case .domain(let domain, let policy): return "DOMAIN,\(domain),\(policyStr(policy))"
        case .domainSuffix(let suffix, let policy): return "DOMAIN-SUFFIX,\(suffix),\(policyStr(policy))"
        case .domainKeyword(let keyword, let policy): return "DOMAIN-KEYWORD,\(keyword),\(policyStr(policy))"
        case .ipCIDR(let cidr, let policy): return "IP-CIDR,\(cidr),\(policyStr(policy))"
        case .geoIP(let country, let policy): return "GEOIP,\(country),\(policyStr(policy))"
        case .final(let policy): return "MATCH,\(policyStr(policy))"
        case .reject: return "REJECT"
        default: return "MATCH,DIRECT"
        }
    }

    private func policyStr(_ policy: RoutingPolicy) -> String {
        switch policy {
        case .direct: return "DIRECT"
        case .reject: return "REJECT"
        case .proxyNode(let name): return name
        }
    }

    private func computeDiff(base: RiptideConfig, merged: RiptideConfig) -> MergeDiff {
        let addedProxies = merged.proxies.filter { mergedProxy in !base.proxies.contains(where: { $0.name == mergedProxy.name }) }
        let removedProxies = base.proxies.filter { baseProxy in !merged.proxies.contains(where: { $0.name == baseProxy.name }) }
        let modifiedProxies = merged.proxies.filter { mergedProxy in
            base.proxies.contains(where: { $0.name == mergedProxy.name && $0 != mergedProxy })
        }

        let addedRules = max(0, merged.rules.count - base.rules.count)

        return MergeDiff(
            addedProxies: addedProxies.map { $0.name },
            removedProxies: removedProxies.map { $0.name },
            modifiedProxies: modifiedProxies.map { $0.name },
            addedRules: addedRules,
            totalProxies: merged.proxies.count,
            totalRules: merged.rules.count
        )
    }
}

// MARK: - Supporting Types

/// A source YAML to merge from.
public struct MergeSource: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let yaml: String
    public let kind: MergeSourceKind

    public init(name: String, yaml: String, kind: MergeSourceKind) {
        self.name = name
        self.yaml = yaml
        self.kind = kind
    }
}

public enum MergeSourceKind: Sendable {
    case file(URL)
    case url(URL)
    case manual
}

/// Preview of a merge result.
public struct MergePreview: Sendable {
    public let mergedConfig: RiptideConfig
    public let mergedYAML: String
    public let diff: MergeDiff
}

/// Summary of changes from a merge.
public struct MergeDiff: Sendable {
    public let addedProxies: [String]
    public let removedProxies: [String]
    public let modifiedProxies: [String]
    public let addedRules: Int
    public let totalProxies: Int
    public let totalRules: Int

    public var hasChanges: Bool {
        !addedProxies.isEmpty || !removedProxies.isEmpty || !modifiedProxies.isEmpty || addedRules > 0
    }
}
