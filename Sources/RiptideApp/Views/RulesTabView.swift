import SwiftUI
import AppKit
import Riptide

struct RulesTabView: View {
    @Bindable var vm: AppViewModel
    @State private var showRuleMarket = false
    @State private var showRuleTester = false
    @State private var showVisualRuleEditor = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Mode selector
                HStack {
                    ForEach([ProxyMode.rule, .global, .direct], id: \.self) { mode in
                        Button {
                            Task { await vm.switchMode(mode) }
                        } label: {
                            Text(mode.rawValue.uppercased())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(vm.proxyMode == mode ? Theme.accent : Color.clear)
                                .foregroundStyle(vm.proxyMode == mode ? .black : Theme.text)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))

                // Rule list
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("规则列表")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Button {
                            showRuleMarket = true
                        } label: {
                            Label("规则市场", systemImage: "cart")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button {
                            showRuleTester = true
                        } label: {
                            Label("测试工具", systemImage: "magnifyingglass")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button {
                            showVisualRuleEditor = true
                        } label: {
                            Label("添加规则", systemImage: "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Text("共 \(vm.rules.count) 条")
                            .font(.caption)
                            .foregroundStyle(Theme.subtext)
                    }
                    Divider()
                    ForEach(Array(vm.rules.enumerated()), id: \.offset) { _, rule in
                        RuleRow(rule: rule)
                        Divider()
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            }
            .padding()
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .sheet(isPresented: $showRuleMarket) {
            RuleMarketView()
        }
        .sheet(isPresented: $showRuleTester) {
            RuleMatchTesterView(vm: vm)
        }
        .sheet(isPresented: $showVisualRuleEditor) {
            VisualRuleEditorView(vm: vm)
        }
    }
}

struct RuleRow: View {
    let rule: ProxyRule

    private var ruleText: String {
        switch rule {
        case .domain(let domain, let policy): return "DOMAIN \(domain) → \(policyText(policy))"
        case .domainSuffix(let suffix, let policy): return "DOMAIN-SUFFIX \(suffix) → \(policyText(policy))"
        case .domainKeyword(let kw, let policy): return "DOMAIN-KEYWORD \(kw) → \(policyText(policy))"
        case .ipCIDR(let cidr, let policy): return "IP-CIDR \(cidr) → \(policyText(policy))"
        case .ipCIDR6(let cidr, let policy): return "IP-CIDR6 \(cidr) → \(policyText(policy))"
        case .srcIPCIDR(let cidr, let policy): return "SRC-IP-CIDR \(cidr) → \(policyText(policy))"
        case .srcPort(let port, let policy): return "SRC-PORT \(port) → \(policyText(policy))"
        case .dstPort(let port, let policy): return "DST-PORT \(port) → \(policyText(policy))"
        case .processName(let name, let policy): return "PROCESS \(name) → \(policyText(policy))"
        case .geoIP(let cc, let policy): return "GEOIP \(cc) → \(policyText(policy))"
        case .ipASN(let asn, let policy): return "IP-ASN AS\(asn) → \(policyText(policy))"
        case .geoSite(let cc, let cat, let policy): return "GEOSITE \(cc),\(cat) → \(policyText(policy))"
        case .ruleSet(let name, let policy): return "RULE-SET \(name) → \(policyText(policy))"
        case .script(let code, let policy): return "SCRIPT \(code.prefix(20))... → \(policyText(policy))"
        case .not(let ruleType, let value, let policy): return "NOT \(ruleType) \(value) → \(policyText(policy))"
        case .reject: return "REJECT"
        case .matchAll: return "MATCH → \(policyText(.proxyNode(name: "代理")))"
        case .final(let policy): return "FINAL → \(policyText(policy))"
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
        Text(ruleText)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Theme.text)
            .contextMenu {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ruleText, forType: .string)
                } label: { Label("复制规则文本", systemImage: "doc.on.doc") }
            }
    }
}
