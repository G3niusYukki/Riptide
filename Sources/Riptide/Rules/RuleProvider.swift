import Foundation

public enum RuleProviderError: Error, Sendable {
    case downloadFailed(underlying: Error)
    case parseError(String)
    case noURL
    case fileReadFailed(String)
    case invalidConfig(reason: String)
}

/// Configuration for a rule provider.
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

    public init(
        name: String,
        type: RuleProviderType,
        url: URL? = nil,
        path: String? = nil,
        updateInterval: Int? = nil
    ) {
        self.name = name
        self.type = type
        self.url = url
        self.path = path
        self.updateInterval = updateInterval
    }
}

/// Actor that downloads and auto-updates a remote rule provider.
public actor RuleProvider: Identifiable {
    public let id: UUID
    public nonisolated let config: RuleProviderConfig
    private var rules: [ProxyRule] = []
    private var lastUpdated: Date?
    private var updateTask: Task<Void, Never>?

    public init(config: RuleProviderConfig) {
        self.id = UUID()
        self.config = config
    }

    /// Start periodic rule updates.
    public func start() async {
        try? await refresh()

        guard let interval = config.updateInterval, interval > 0 else { return }

        updateTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                try? await refresh()
            }
        }
    }

    /// Stop periodic updates.
    public func stop() {
        updateTask?.cancel()
        updateTask = nil
    }

    /// Returns the current rules.
    public func getRules() -> [ProxyRule] {
        rules
    }

    /// Returns the last updated date.
    public func lastUpdateTime() -> Date? {
        lastUpdated
    }

    /// Manually trigger a refresh.
    public func refresh() async throws {
        let newRules: [ProxyRule]

        switch config.type {
        case .http:
            guard let url = config.url else {
                throw RuleProviderError.noURL
            }
            newRules = try await fetchRules(from: url)
        case .file:
            guard let path = config.path else {
                throw RuleProviderError.fileReadFailed("No path configured")
            }
            newRules = try await loadRules(from: path)
        }

        self.rules = newRules
        self.lastUpdated = Date()
    }

    private func fetchRules(from url: URL) async throws -> [ProxyRule] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw RuleProviderError.downloadFailed(underlying: URLError(.badServerResponse))
        }

        return try parseRules(from: data)
    }

    private func loadRules(from path: String) async throws -> [ProxyRule] {
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RuleProviderError.fileReadFailed("Failed to read file: \(error)")
        }
        return try parseRules(from: data)
    }

    private func parseRules(from data: Data) throws -> [ProxyRule] {
        guard let content = String(data: data, encoding: .utf8), !content.isEmpty else {
            return []
        }

        var rules: [ProxyRule] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
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

            case "SRC-PORT":
                guard parts.count >= 3 else { continue }
                guard let port = Int(parts[1]) else { continue }
                rules.append(.srcPort(port: port, policy: policy))

            case "DST-PORT":
                guard parts.count >= 3 else { continue }
                guard let port = Int(parts[1]) else { continue }
                rules.append(.dstPort(port: port, policy: policy))

            case "PROCESS-NAME":
                guard parts.count >= 3 else { continue }
                let name = parts[1]
                guard !name.isEmpty else { continue }
                rules.append(.processName(name: name, policy: policy))

            default:
                // Skip unknown rule types.
                break
            }
        }

        return rules
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
