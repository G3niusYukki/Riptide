import SwiftUI
import Riptide

// MARK: - Rule Editor View

public struct RuleEditorView: View {
    @State private var viewModel: RuleEditorViewModel
    @State private var showAddSheet = false
    @State private var editingRule: EditableRule = EditableRule()
    @State private var validationError: String?

    public init(viewModel: RuleEditorViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("规则编辑器")
                    .font(.headline)
                Spacer()
                Text("共 \(viewModel.rules.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("+ 添加规则") {
                    editingRule = EditableRule()
                    validationError = nil
                    showAddSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            // Rule list with drag-to-reorder
            List {
                ForEach(Array(viewModel.rules.enumerated()), id: \.offset) { index, rule in
                    RuleEditorRow(rule: rule, index: index)
                        .contextMenu {
                            Button("删除", role: .destructive) {
                                Task { try? await viewModel.deleteRule(rule) }
                            }
                        }
                }
                .onDelete { offsets in
                    Task { try? await viewModel.deleteRule(at: offsets) }
                }
                .onMove { source, destination in
                    Task { try? await viewModel.moveRule(from: source, to: destination) }
                }
            }
            .listStyle(.inset)
        }
        .sheet(isPresented: $showAddSheet) {
            RuleAddSheet(
                editingRule: $editingRule,
                validationError: $validationError,
                availablePolicies: viewModel.availablePolicies(),
                onSave: { addRule() },
                onCancel: { showAddSheet = false }
            )
        }
        .task {
            await viewModel.loadRules()
        }
    }

    private func addRule() {
        Task {
            do {
                let rule = editingRule.toProxyRule()
                try await viewModel.addRule(rule)
                showAddSheet = false
                validationError = nil
            } catch {
                validationError = error.localizedDescription
            }
        }
    }
}

// MARK: - Rule Editor Row

struct RuleEditorRow: View {
    let rule: ProxyRule
    let index: Int

    private var ruleText: String {
        switch rule {
        case .domain(let domain, let policy): return "DOMAIN \(domain) → \(policyText(policy))"
        case .domainSuffix(let suffix, let policy): return "DOMAIN-SUFFIX \(suffix) → \(policyText(policy))"
        case .domainKeyword(let keyword, let policy): return "DOMAIN-KEYWORD \(keyword) → \(policyText(policy))"
        case .ipCIDR(let cidr, let policy): return "IP-CIDR \(cidr) → \(policyText(policy))"
        case .ipCIDR6(let cidr, let policy): return "IP-CIDR6 \(cidr) → \(policyText(policy))"
        case .srcIPCIDR(let cidr, let policy): return "SRC-IP-CIDR \(cidr) → \(policyText(policy))"
        case .srcPort(let port, let policy): return "SRC-PORT \(port) → \(policyText(policy))"
        case .dstPort(let port, let policy): return "DST-PORT \(port) → \(policyText(policy))"
        case .processName(let name, let policy): return "PROCESS \(name) → \(policyText(policy))"
        case .geoIP(let countryCode, let policy): return "GEOIP \(countryCode) → \(policyText(policy))"
        case .ipASN(let asn, let policy): return "IP-ASN AS\(asn) → \(policyText(policy))"
        case .geoSite(let countryCode, let cat, let policy): return "GEOSITE \(countryCode),\(cat) → \(policyText(policy))"
        case .ruleSet(let name, let policy): return "RULE-SET \(name) → \(policyText(policy))"
        case .script(let code, let policy): return "SCRIPT \(code.prefix(20))... → \(policyText(policy))"
        case .not(let ruleType, let value, let policy): return "NOT \(ruleType) \(value) → \(policyText(policy))"
        case .reject: return "REJECT"
        case .matchAll: return "MATCH → DIRECT"
        case .final(let policy): return "MATCH → \(policyText(policy))"
        }
    }

    private func policyText(_ policy: RoutingPolicy) -> String {
        switch policy {
        case .direct: return "直连"
        case .reject: return "拒绝"
        case .proxyNode(let name): return name
        }
    }

    var body: some View {
        HStack {
            Text("\(index + 1).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)

            Text(ruleText)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Rule Add Sheet

struct RuleAddSheet: View {
    @Binding var editingRule: EditableRule
    @Binding var validationError: String?
    let availablePolicies: [String]
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let error = validationError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section("规则类型") {
                    Picker("类型", selection: $editingRule.type) {
                        ForEach(EditableRuleType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("匹配值") {
                    switch editingRule.type {
                    case .domain:
                        TextField("example.com", text: $editingRule.value)
                    case .domainSuffix:
                        TextField("google.com", text: $editingRule.value)
                    case .domainKeyword:
                        TextField("google", text: $editingRule.value)
                    case .ipCIDR:
                        TextField("192.168.0.0/16", text: $editingRule.value)
                    case .geoIP:
                        TextField("CN", text: $editingRule.value)
                    case .geoSite:
                        TextField("google", text: $editingRule.value)
                    case .dstPort:
                        TextField("443", text: $editingRule.value)
                    case .processName:
                        TextField("Safari", text: $editingRule.value)
                    case .ruleSet:
                        TextField("ruleset-name", text: $editingRule.value)
                    case .matchFinal:
                        Text("匹配所有流量")
                            .foregroundStyle(.secondary)
                    }
                }

                if editingRule.type != .matchFinal {
                    Section("策略") {
                        Picker("策略", selection: $editingRule.policy) {
                            ForEach(availablePolicies, id: \.self) { policy in
                                Text(policy).tag(policy)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .navigationTitle("添加规则")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加", action: onSave)
                        .disabled(editingRule.type != .matchFinal && editingRule.value.isEmpty)
                }
            }
        }
        .frame(minWidth: 350, minHeight: 300)
    }
}

// MARK: - Editable Rule Types

/// Supported rule types for the visual editor.
public enum EditableRuleType: String, CaseIterable, Sendable {
    case domain
    case domainSuffix
    case domainKeyword
    case ipCIDR
    case geoIP
    case geoSite
    case dstPort
    case processName
    case ruleSet
    case matchFinal

    public var displayName: String {
        switch self {
        case .domain: return "DOMAIN"
        case .domainSuffix: return "DOMAIN-SUFFIX"
        case .domainKeyword: return "DOMAIN-KEYWORD"
        case .ipCIDR: return "IP-CIDR"
        case .geoIP: return "GEOIP"
        case .geoSite: return "GEOSITE"
        case .dstPort: return "DST-PORT"
        case .processName: return "PROCESS-NAME"
        case .ruleSet: return "RULE-SET"
        case .matchFinal: return "MATCH"
        }
    }
}

/// A mutable rule for editing in the UI.
public struct EditableRule: Sendable {
    public var type: EditableRuleType = .domain
    public var value: String = ""
    public var policy: String = "DIRECT"

    public init() {}

    public func toProxyRule() -> ProxyRule {
        let routingPolicy: RoutingPolicy
        switch policy.uppercased() {
        case "DIRECT": routingPolicy = .direct
        case "REJECT": routingPolicy = .reject
        default: routingPolicy = .proxyNode(name: policy)
        }

        switch type {
        case .domain: return .domain(domain: value, policy: routingPolicy)
        case .domainSuffix: return .domainSuffix(suffix: value, policy: routingPolicy)
        case .domainKeyword: return .domainKeyword(keyword: value, policy: routingPolicy)
        case .ipCIDR: return .ipCIDR(cidr: value, policy: routingPolicy)
        case .geoIP: return .geoIP(countryCode: value, policy: routingPolicy)
        case .geoSite: return .geoSite(code: value, category: "geolocation-cn", policy: routingPolicy)
        case .dstPort:
            let port = Int(value) ?? 0
            return .dstPort(port: port, policy: routingPolicy)
        case .processName: return .processName(name: value, policy: routingPolicy)
        case .ruleSet: return .ruleSet(name: value, policy: routingPolicy)
        case .matchFinal: return .final(policy: routingPolicy)
        }
    }
}
