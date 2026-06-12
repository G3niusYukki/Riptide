import SwiftUI
import Riptide

/// Sheet that lets the user append a new `ProxyRule` to the active profile's
/// rule list via a visual form. Supports the most common rule types; the
/// remaining cases (IP-CIDR6, SRC-IP-CIDR, SRC-PORT, IP-ASN, SCRIPT, NOT,
/// REJECT, MATCH, FINAL) are not exposed here and can be edited through the
/// YAML editor instead.
struct VisualRuleEditorView: View {
    @Bindable var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var ruleType: RuleType = .domain
    @State private var value: String = ""
    @State private var extra: String = ""  // GEOSITE category
    @State private var port: String = ""
    @State private var policyKind: PolicyKind = .proxyNode
    @State private var proxyName: String = ""
    @State private var validationError: String?

    enum RuleType: String, CaseIterable, Identifiable {
        case domain
        case domainSuffix
        case domainKeyword
        case ipCIDR
        case geoIP
        case geoSite
        case ruleSet
        case processName
        case dstPort

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .domain: return "DOMAIN"
            case .domainSuffix: return "DOMAIN-SUFFIX"
            case .domainKeyword: return "DOMAIN-KEYWORD"
            case .ipCIDR: return "IP-CIDR"
            case .geoIP: return "GEOIP"
            case .geoSite: return "GEOSITE"
            case .ruleSet: return "RULE-SET"
            case .processName: return "PROCESS"
            case .dstPort: return "DST-PORT"
            }
        }
    }

    enum PolicyKind: String, CaseIterable, Identifiable {
        case direct
        case reject
        case proxyNode

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .direct: return "DIRECT (直连)"
            case .reject: return "REJECT (拒绝)"
            case .proxyNode: return "PROXY (代理节点)"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("添加规则").font(.headline)
                Spacer()
                Button("关闭") { dismiss() }.buttonStyle(.bordered)
            }

            Picker("规则类型", selection: $ruleType) {
                ForEach(RuleType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 4) {
                Text(valueFieldLabel).font(.caption)
                TextField(valueFieldPlaceholder, text: $value)
                    .textFieldStyle(.roundedBorder)
                if ruleType == .geoSite {
                    Text("类别 (例如 cn, google)").font(.caption)
                    TextField("类别", text: $extra)
                        .textFieldStyle(.roundedBorder)
                }
                if ruleType == .dstPort {
                    Text("端口 (1-65535)").font(.caption)
                    TextField("端口", text: $port)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Picker("策略", selection: $policyKind) {
                ForEach(PolicyKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.menu)

            if policyKind == .proxyNode {
                TextField("代理节点名称", text: $proxyName)
                    .textFieldStyle(.roundedBorder)
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button {
                    if addRule(continueAdding: false) {
                        dismiss()
                    }
                } label: {
                    Text("添加")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    _ = addRule(continueAdding: true)
                } label: {
                    Text("添加并继续")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 380)
    }

    // MARK: - Field Labels

    private var valueFieldLabel: String {
        switch ruleType {
        case .domain, .domainSuffix, .domainKeyword: return "域名"
        case .ipCIDR: return "CIDR (e.g. 192.168.0.0/16)"
        case .geoIP: return "国家代码 (e.g. CN, US)"
        case .geoSite: return "国家代码"
        case .ruleSet: return "规则集名称"
        case .processName: return "进程名"
        case .dstPort: return "目标端口"
        }
    }

    private var valueFieldPlaceholder: String {
        switch ruleType {
        case .domain: return "example.com"
        case .domainSuffix: return "example.com"
        case .domainKeyword: return "example"
        case .ipCIDR: return "10.0.0.0/8"
        case .geoIP: return "CN"
        case .geoSite: return "CN"
        case .ruleSet: return "private"
        case .processName: return "curl"
        case .dstPort: return "443"
        }
    }

    // MARK: - Submission

    /// Builds a `ProxyRule` from the current form state, appends it to
    /// `vm.rules` via `appendRule(_:)`, and returns whether the operation
    /// succeeded. `continueAdding` clears the value fields on success so the
    /// user can quickly add a series of related rules.
    @discardableResult
    private func addRule(continueAdding: Bool) -> Bool {
        guard let policy = makePolicy() else {
            validationError = "代理节点名称不能为空"
            return false
        }

        guard let newRule = makeRule(policy: policy) else {
            // validationError already set by makeRule
            return false
        }

        validationError = nil
        vm.appendRule(newRule)

        if continueAdding {
            value = ""
            extra = ""
            port = ""
        }
        return true
    }

    private func makePolicy() -> RoutingPolicy? {
        if policyKind == .proxyNode && proxyName.trimmingCharacters(in: .whitespaces).isEmpty {
            return nil
        }
        switch policyKind {
        case .direct: return .direct
        case .reject: return .reject
        case .proxyNode: return .proxyNode(name: proxyName)
        }
    }

    /// Builds a ProxyRule from the form fields, validating input and setting
    /// `validationError` on failure. Returns nil on validation failure.
    private func makeRule(policy: RoutingPolicy) -> ProxyRule? {
        switch ruleType {
        case .domain:
            guard !value.isEmpty else { validationError = "请填写域名"; return nil }
            return .domain(domain: value, policy: policy)
        case .domainSuffix:
            guard !value.isEmpty else { validationError = "请填写域名后缀"; return nil }
            return .domainSuffix(suffix: value, policy: policy)
        case .domainKeyword:
            guard !value.isEmpty else { validationError = "请填写域名关键字"; return nil }
            return .domainKeyword(keyword: value, policy: policy)
        case .ipCIDR:
            guard !value.isEmpty else { validationError = "请填写 CIDR"; return nil }
            return .ipCIDR(cidr: value, policy: policy)
        case .geoIP:
            guard !value.isEmpty else { validationError = "请填写国家代码"; return nil }
            return .geoIP(countryCode: value, policy: policy)
        case .geoSite:
            guard !value.isEmpty, !extra.isEmpty else {
                validationError = "请填写 GEOSITE 国家代码和类别"
                return nil
            }
            return .geoSite(code: value, category: extra, policy: policy)
        case .ruleSet:
            guard !value.isEmpty else { validationError = "请填写规则集名称"; return nil }
            return .ruleSet(name: value, policy: policy)
        case .processName:
            guard !value.isEmpty else { validationError = "请填写进程名"; return nil }
            return .processName(name: value, policy: policy)
        case .dstPort:
            guard let portNum = Int(port), (1...65535).contains(portNum) else {
                validationError = "端口必须是 1-65535 之间的整数"
                return nil
            }
            return .dstPort(port: portNum, policy: policy)
        }
    }
}
