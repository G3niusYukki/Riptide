import Foundation
import Riptide
import Yams

// MARK: - Rule Editor ViewModel

/// View model for the rule editor UI.
/// Manages CRUD operations on proxy rules within the active profile.
@Observable
public final class RuleEditorViewModel: @unchecked Sendable {

    // MARK: - State
    private(set) var rules: [ProxyRule] = []
    private(set) var isLoading = false
    private(set) var error: String?

    // MARK: - Dependencies
    private let profileStore: ProfileStore
    private var currentProfile: Riptide.Profile?

    public init(profileStore: ProfileStore) {
        self.profileStore = profileStore
    }

    // MARK: - Load

    public func loadRules() async {
        isLoading = true
        defer { isLoading = false }

        currentProfile = await profileStore.currentProfile()
        guard let profile = currentProfile else {
            rules = []
            return
        }
        rules = parseRulesFromYAML(profile.rawYAML)
    }

    // MARK: - Add

    public func addRule(_ rule: ProxyRule) async throws {
        guard currentProfile != nil else {
            throw NodeValidationError.storeError("No profile selected")
        }
        rules.append(rule)
        try await saveToProfile()
    }

    // MARK: - Delete

    public func deleteRule(at offsets: IndexSet) async throws {
        guard currentProfile != nil else {
            throw NodeValidationError.storeError("No profile selected")
        }
        rules.remove(atOffsets: offsets)
        try await saveToProfile()
    }

    public func deleteRule(_ rule: ProxyRule) async throws {
        guard currentProfile != nil else {
            throw NodeValidationError.storeError("No profile selected")
        }
        rules.removeAll { $0 == rule }
        try await saveToProfile()
    }

    // MARK: - Move

    public func moveRule(from source: IndexSet, to destination: Int) async throws {
        guard currentProfile != nil else {
            throw NodeValidationError.storeError("No profile selected")
        }
        rules.move(fromOffsets: source, toOffset: destination)
        try await saveToProfile()
    }

    // MARK: - Available Policies

    /// Returns available proxy names from the current profile for use as rule policies.
    public func availablePolicies() -> [String] {
        guard let profile = currentProfile else { return ["DIRECT", "REJECT"] }
        guard let (config, _) = try? ClashConfigParser.parse(yaml: profile.rawYAML) else {
            return ["DIRECT", "REJECT"]
        }
        let proxyNames = config.proxies.map { $0.name }
        let groupNames = config.proxyGroups.map { $0.id }
        return ["DIRECT", "REJECT"] + proxyNames + groupNames
    }

    // MARK: - Private

    private func saveToProfile() async throws {
        guard let profile = currentProfile else { return }
        let yaml = generateYAMLWithRules(rules, baseYAML: profile.rawYAML)
        _ = try await profileStore.importProfile(name: profile.name, yaml: yaml)
        await loadRules()
    }

    private func parseRulesFromYAML(_ yaml: String) -> [ProxyRule] {
        guard let (config, _) = try? ClashConfigParser.parse(yaml: yaml) else {
            return []
        }
        return config.rules
    }

    private func generateYAMLWithRules(_ rules: [ProxyRule], baseYAML: String) -> String {
        guard var raw = try? Yams.load(yaml: baseYAML) as? [String: Any] else {
            return baseYAML
        }

        let ruleStrings = rules.map { ruleToString($0) }
        raw["rules"] = ruleStrings

        return (try? Yams.dump(object: raw)) ?? baseYAML
    }

    private func ruleToString(_ rule: ProxyRule) -> String {
        switch rule {
        case .domain(let domain, let policy):
            return "DOMAIN,\(domain),\(policyString(policy))"
        case .domainSuffix(let suffix, let policy):
            return "DOMAIN-SUFFIX,\(suffix),\(policyString(policy))"
        case .domainKeyword(let keyword, let policy):
            return "DOMAIN-KEYWORD,\(keyword),\(policyString(policy))"
        case .ipCIDR(let cidr, let policy):
            return "IP-CIDR,\(cidr),\(policyString(policy))"
        case .ipCIDR6(let cidr, let policy):
            return "IP-CIDR6,\(cidr),\(policyString(policy))"
        case .srcIPCIDR(let cidr, let policy):
            return "SRC-IP-CIDR,\(cidr),\(policyString(policy))"
        case .srcPort(let port, let policy):
            return "SRC-PORT,\(port),\(policyString(policy))"
        case .dstPort(let port, let policy):
            return "DST-PORT,\(port),\(policyString(policy))"
        case .processName(let name, let policy):
            return "PROCESS-NAME,\(name),\(policyString(policy))"
        case .geoIP(let cc, let policy):
            return "GEOIP,\(cc),\(policyString(policy))"
        case .geoSite(let cc, let category, let policy):
            return "GEOSITE,\(cc),\(category),\(policyString(policy))"
        case .ipASN(let asn, let policy):
            return "IP-ASN,\(asn),\(policyString(policy))"
        case .ruleSet(let name, let policy):
            return "RULE-SET,\(name),\(policyString(policy))"
        case .script(let code, let policy):
            return "SCRIPT,\(code),\(policyString(policy))"
        case .not(let ruleType, let value, let policy):
            return "NOT,\(ruleType) \(value),\(policyString(policy))"
        case .reject:
            return "REJECT"
        case .matchAll:
            return "MATCH,DIRECT"
        case .final(let policy):
            return "MATCH,\(policyString(policy))"
        }
    }

    private func policyString(_ policy: RoutingPolicy) -> String {
        switch policy {
        case .direct: return "DIRECT"
        case .reject: return "REJECT"
        case .proxyNode(let name): return name
        }
    }
}
