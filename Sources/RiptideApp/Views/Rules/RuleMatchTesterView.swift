import SwiftUI
import Riptide

struct RuleMatchTesterView: View {
    @Bindable var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var inputText = ""
    @State private var lastResult: MatchResult?
    @State private var history: [MatchResult] = []
    @State private var isTesting = false

    struct MatchResult: Codable, Identifiable {
        let id: UUID
        let input: String
        let ruleType: String
        let ruleContent: String
        let policy: String
        let latencyMs: Double
        let timestamp: Date

        init(input: String, ruleType: String, ruleContent: String, policy: String, latencyMs: Double) {
            self.id = UUID()
            self.input = input
            self.ruleType = ruleType
            self.ruleContent = ruleContent
            self.policy = policy
            self.latencyMs = latencyMs
            self.timestamp = Date()
        }
    }

    private let historyKey = "riptide.ruleTestHistory"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("规则匹配测试").font(.headline)
                Spacer()
                Button("关闭") { dismiss() }.buttonStyle(.bordered)
            }

            HStack {
                TextField("输入域名或 IP", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runTest() }
                Button("测试") { runTest() }
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.isEmpty || isTesting)
            }

            if let result = lastResult {
                resultCard(result)
            }

            if !history.isEmpty {
                Divider()
                Text("最近测试").font(.subheadline).foregroundStyle(Theme.subtext)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(history) { entry in
                        HStack {
                            Text(entry.input).font(.caption.monospaced())
                            Text("→").foregroundStyle(.secondary)
                            Text(entry.ruleType).font(.caption)
                            Text("→").foregroundStyle(.secondary)
                            Text(entry.policy).font(.caption).foregroundStyle(policyColor(entry.policy))
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .onAppear { loadHistory() }
    }

    private func resultCard(_ result: MatchResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("匹配结果").font(.subheadline)
            Divider()
            row("命中规则", value: result.ruleType)
            row("规则内容", value: result.ruleContent)
            row("策略", value: result.policy)
            row("耗时", value: String(format: "%.2fms", result.latencyMs))
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.subtext).frame(width: 80, alignment: .leading)
            Text(value).foregroundStyle(Theme.text)
        }
    }

    private func runTest() {
        isTesting = true
        defer { isTesting = false }
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let target = RuleTarget.parse(trimmed)
        let start = Date()
        guard let engine = vm.buildRuleEngine() else {
            lastResult = MatchResult(input: trimmed, ruleType: "ERROR", ruleContent: "No active profile", policy: "N/A", latencyMs: 0)
            return
        }
        let policy = engine.resolve(target: target)
        let elapsed = Date().timeIntervalSince(start) * 1000

        let (ruleType, ruleContent) = findMatchingRule(rules: vm.rules, target: target)
        let result = MatchResult(
            input: trimmed,
            ruleType: ruleType,
            ruleContent: ruleContent,
            policy: policyDescription(policy),
            latencyMs: elapsed
        )
        lastResult = result
        history.insert(result, at: 0)
        if history.count > 10 { history = Array(history.prefix(10)) }
        saveHistory()
    }

    private func findMatchingRule(rules: [ProxyRule], target: RuleTarget) -> (String, String) {
        for rule in rules where matches(rule: rule, target: target) {
            return (ruleTypeName(rule), ruleContentString(rule))
        }
        return ("MATCH", "默认")
    }

    private func matches(rule: ProxyRule, target: RuleTarget) -> Bool {
        let targetDomain = target.domain?.lowercased()
        switch rule {
        case .domain(let domain, _):
            return targetDomain == domain.lowercased()
        case .domainSuffix(let suffix, _):
            return targetDomain?.hasSuffix(suffix.lowercased()) == true
        case .domainKeyword(let keyword, _):
            return targetDomain?.contains(keyword.lowercased()) == true
        default:
            return false
        }
    }

    private func ruleTypeName(_ rule: ProxyRule) -> String {
        switch rule {
        case .domain: return "DOMAIN"
        case .domainSuffix: return "DOMAIN-SUFFIX"
        case .domainKeyword: return "DOMAIN-KEYWORD"
        case .ipCIDR: return "IP-CIDR"
        case .geoIP: return "GEOIP"
        case .geoSite: return "GEOSITE"
        case .ruleSet: return "RULE-SET"
        case .matchAll: return "MATCH"
        default: return String(describing: rule)
        }
    }

    private func ruleContentString(_ rule: ProxyRule) -> String {
        switch rule {
        case .domain(let domain, _): return domain
        case .domainSuffix(let suffix, _): return ".\(suffix)"
        case .domainKeyword(let keyword, _): return keyword
        case .ipCIDR(let cidr, _): return cidr
        case .geoIP(let countryCode, _): return countryCode
        case .geoSite(let code, let category, _): return "\(code),\(category)"
        case .ruleSet(let name, _): return name
        case .matchAll: return "全部"
        default: return ""
        }
    }

    private func policyDescription(_ policy: RoutingPolicy) -> String {
        switch policy {
        case .direct: return "直连"
        case .reject: return "拒绝"
        case .proxyNode(let name): return "PROXY (\(name))"
        }
    }

    private func policyColor(_ policy: String) -> Color {
        if policy.contains("PROXY") { return Theme.success }
        if policy.contains("拒绝") { return Theme.danger }
        return Theme.subtext
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([MatchResult].self, from: data) {
            history = decoded
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
}
