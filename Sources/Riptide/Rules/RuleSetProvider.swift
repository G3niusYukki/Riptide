import Foundation

/// Error types for rule set operations.
public enum RuleSetError: Error, Sendable {
    case downloadFailed(underlying: Error)
    case parseError(underlying: Error)
}

/// Actor that downloads and auto-updates a remote rule set.
public actor RuleSetProvider {
    private let config: RuleSetProviderConfig
    private var currentRuleSet: RuleSet?
    private var updateTask: Task<Void, Never>?

    public init(config: RuleSetProviderConfig) {
        self.config = config
    }

    /// Start periodic rule set updates.
    public func start() async {
        await refresh()

        guard config.interval > 0 else { return }

        updateTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(config.interval))
                await refresh()
            }
        }
    }

    /// Stop periodic updates.
    public func stop() {
        updateTask?.cancel()
        updateTask = nil
    }

    /// Returns the current rules, or an empty array if not yet loaded.
    public func rules() -> [ProxyRule] {
        currentRuleSet?.rules ?? []
    }

    /// Manually trigger a refresh.
    public func refresh() async {
        do {
            let data = try await downloadData(from: config.url)
            guard let yaml = String(data: data, encoding: .utf8), !yaml.isEmpty else {
                return
            }
            let ruleSet = try parseRuleSet(yaml: yaml)
            currentRuleSet = ruleSet
        } catch {
            // Keep existing rule set on failure.
        }
    }

    /// Download raw data from a URL using URLSession.
    private func downloadData(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw RuleSetError.downloadFailed(underlying: URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw RuleSetError.downloadFailed(
                underlying: URLError(.badServerResponse)
            )
        }

        return data
    }

    /// Parse a Clash-style rule set YAML string into a RuleSet.
    private func parseRuleSet(yaml: String) throws -> RuleSet {
        var rules: [ProxyRule] = []

        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count >= 2 else { continue }

            let ruleType = parts[0].uppercased()
            let policyName = parts.last!
            let policy = parsePolicy(policyName)

            switch ruleType {
            case "DOMAIN":
                let domain = parts[1]
                guard !domain.isEmpty else { continue }
                rules.append(.domain(domain: domain, policy: policy))

            case "DOMAIN-SUFFIX":
                let suffix = parts[1]
                guard !suffix.isEmpty else { continue }
                rules.append(.domainSuffix(suffix: suffix, policy: policy))

            case "DOMAIN-KEYWORD":
                let keyword = parts[1]
                guard !keyword.isEmpty else { continue }
                rules.append(.domainKeyword(keyword: keyword, policy: policy))

            case "IP-CIDR":
                let cidr = parts[1]
                guard !cidr.isEmpty else { continue }
                rules.append(.ipCIDR(cidr: cidr, policy: policy))

            case "IP-CIDR6":
                let cidr = parts[1]
                guard !cidr.isEmpty else { continue }
                rules.append(.ipCIDR6(cidr: cidr, policy: policy))

            case "GEOIP":
                let countryCode = parts[1]
                guard !countryCode.isEmpty else { continue }
                rules.append(.geoIP(countryCode: countryCode, policy: policy))

            case "SRC-IP-CIDR":
                guard parts.count >= 3 else { continue }
                let cidr = parts[1]
                guard !cidr.isEmpty else { continue }
                rules.append(.srcIPCIDR(cidr: cidr, policy: policy))

            default:
                // Skip unknown rule types.
                break
            }
        }

        return RuleSet(name: config.name, behavior: config.behavior, rules: rules, updatedAt: Date())
    }

    private func parsePolicy(_ rawPolicy: String) -> RoutingPolicy {
        let normalized = rawPolicy.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch normalized {
        case "DIRECT": return .direct
        case "REJECT": return .reject
        default: return .proxyNode(name: rawPolicy)
        }
    }
}
