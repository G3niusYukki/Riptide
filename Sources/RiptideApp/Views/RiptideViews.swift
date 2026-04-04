import SwiftUI
import Riptide

struct ProxyListView: View {
    let proxies: [ProxyNode]
    @Binding var selected: String

    var body: some View {
        List(proxies, id: \.name, selection: $selected) { node in
            HStack {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text(node.name).font(.system(.body))
                Spacer()
                Text(node.kind.kindString)
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
                Text("\(node.server):\(node.port)")
                    .font(.system(.caption2))
                    .foregroundStyle(.tertiary)
            }
            .tag(node.name)
        }
    }
}

struct RuleTableView: View {
    let rules: [ProxyRule]

    var body: some View {
        List(rules, id: \.ruleDescription) { rule in
            HStack {
                Text(rule.ruleTypeString)
                    .font(.system(.caption))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                Text(rule.ruleDescription)
                    .font(.system(.callout))
                Spacer()
            }
        }
    }
}

struct ConnectionView: View {
    let count: Int
    let bytesUp: UInt64
    let bytesDown: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Active Connections", systemImage: "network")
                    .font(.headline)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("Upload", systemImage: "arrow.up")
                Text(formatBytes(bytesUp))
            }
            HStack {
                Label("Download", systemImage: "arrow.down")
                Text(formatBytes(bytesDown))
            }
        }
        .font(.system(.callout))
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1024 / 1024) }
        return String(format: "%.2f GB", Double(bytes) / 1024 / 1024 / 1024)
    }
}

struct TrafficView: View {
    let bytesUp: UInt64
    let bytesDown: UInt64

    var body: some View {
        HStack(spacing: 32) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Upload").font(.caption).foregroundStyle(.secondary)
                Text(formatBytes(bytesUp)).font(.title3.monospaced())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Download").font(.caption).foregroundStyle(.secondary)
                Text(formatBytes(bytesDown)).font(.title3.monospaced())
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1024 / 1024) }
        return String(format: "%.2f GB", Double(bytes) / 1024 / 1024 / 1024)
    }
}

struct ConfigView: View {
    @Binding var yamlText: String
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Config").font(.headline)
            TextEditor(text: $yamlText)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 200)
                .border(Color.gray.opacity(0.3))
            HStack {
                Button("Import YAML", action: onImport)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

struct SettingsView: View {
    @Binding var controllerPort: String

    var body: some View {
        Form {
            Section("External Controller") {
                HStack {
                    Text("API Port")
                    TextField("9090", text: $controllerPort)
                        .frame(width: 80)
                }
            }
            Section("About") {
                Text("Riptide v1.0.0")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }
}

extension ProxyRule {
    var ruleTypeString: String {
        switch self {
        case .domain: return "DOMAIN"
        case .domainSuffix: return "DOMAIN-SUFFIX"
        case .domainKeyword: return "DOMAIN-KEYWORD"
        case .ipCIDR: return "IP-CIDR"
        case .ipCIDR6: return "IP-CIDR6"
        case .srcIPCIDR: return "SRC-IP-CIDR"
        case .srcPort: return "SRC-PORT"
        case .dstPort: return "DST-PORT"
        case .processName: return "PROCESS"
        case .geoIP: return "GEOIP"
        case .ipASN: return "IP-ASN"
        case .geoSite: return "GEOSITE"
        case .ruleSet: return "RULE-SET"
        case .script: return "SCRIPT"
        case .not: return "NOT"
        case .matchAll: return "MATCH"
        case .final: return "FINAL"
        case .reject: return "REJECT"
        }
    }

    var ruleDescription: String {
        switch self {
        case .domain(let d, _): return d
        case .domainSuffix(let s, _): return s
        case .domainKeyword(let k, _): return k
        case .ipCIDR(let c, _): return c
        case .ipCIDR6(let c, _): return c
        case .srcIPCIDR(let c, _): return c
        case .srcPort(let p, _): return "\(p)"
        case .dstPort(let p, _): return "\(p)"
        case .processName(let n, _): return n
        case .geoIP(let c, _): return c
        case .ipASN(let a, _): return "AS\(a)"
        case .geoSite(let c, let cat, _): return "\(c),\(cat)"
        case .ruleSet(let n, _): return n
        case .script(let code, _): return String(code.prefix(30)) + "..."
        case .not(let ruleType, let value, _): return "\(ruleType) \(value)"
        case .matchAll: return "*"
        case .final: return "FINAL"
        case .reject: return "REJECT"
        }
    }
}
