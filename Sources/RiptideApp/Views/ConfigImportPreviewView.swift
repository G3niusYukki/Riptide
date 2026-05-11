import SwiftUI
import Riptide

// MARK: - Config Import Preview View

/// Shows a preview of a config file before importing it.
/// Displays proxy count, rule count, proxy groups, and allows the user to
/// confirm or cancel the import.
public struct ConfigImportPreviewView: View {
    let yaml: String
    let fileName: String
    let onImport: (String) -> Void
    let onCancel: () -> Void

    @State private var config: RiptideConfig?
    @State private var parseError: String?

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let config {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Summary card
                            summaryCard(config)

                            // Proxies list
                            if !config.proxies.isEmpty {
                                proxiesSection(config.proxies)
                            }

                            // Proxy groups
                            if !config.proxyGroups.isEmpty {
                                groupsSection(config.proxyGroups)
                            }

                            // Rules summary
                            if !config.rules.isEmpty {
                                rulesSection(config.rules)
                            }
                        }
                        .padding()
                    }
                } else if let error = parseError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text("解析失败")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ProgressView("解析中...")
                }
            }
            .navigationTitle("配置预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        if config != nil {
                            onImport(yaml)
                        }
                    }
                    .disabled(config == nil)
                }
            }
        }
        .frame(minWidth: 450, minHeight: 400)
        .task {
            parseConfig()
        }
    }

    // MARK: - Summary Card

    private func summaryCard(_ config: RiptideConfig) -> some View {
        VStack(spacing: 12) {
            Text(fileName)
                .font(.headline)

            HStack(spacing: 24) {
                StatBadge(
                    label: "节点",
                    value: "\(config.proxies.count)",
                    icon: "server.rack",
                    color: .blue
                )
                StatBadge(
                    label: "规则",
                    value: "\(config.rules.count)",
                    icon: "list.bullet",
                    color: .green
                )
                StatBadge(
                    label: "代理组",
                    value: "\(config.proxyGroups.count)",
                    icon: "rectangle.3.group",
                    color: .purple
                )
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Proxies Section

    private func proxiesSection(_ proxies: [ProxyNode]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("代理节点 (\(proxies.count))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(proxies.prefix(20), id: \.name) { proxy in
                HStack {
                    Text(proxy.kind.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15))
                        .clipShape(Capsule())

                    Text(proxy.name)
                        .font(.body)

                    Spacer()

                    Text("\(proxy.server):\(proxy.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if proxies.count > 20 {
                Text("... 还有 \(proxies.count - 20) 个节点")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Groups Section

    private func groupsSection(_ groups: [ProxyGroup]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("代理组 (\(groups.count))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(groups, id: \.id) { group in
                HStack {
                    Text(group.kind.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.purple.opacity(0.15))
                        .clipShape(Capsule())

                    Text(group.id)
                        .font(.body)

                    Spacer()

                    Text("\(group.proxies.count) 个节点")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Rules Section

    private func rulesSection(_ rules: [ProxyRule]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("规则 (\(rules.count))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(rules.prefix(15).enumerated()), id: \.offset) { _, rule in
                Text(ruleText(rule))
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
            }

            if rules.count > 15 {
                Text("... 还有 \(rules.count - 15) 条规则")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func parseConfig() {
        do {
            let (parsed, _) = try ClashConfigParser.parse(yaml: yaml)
            config = parsed
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func ruleText(_ rule: ProxyRule) -> String {
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
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
    }
}
