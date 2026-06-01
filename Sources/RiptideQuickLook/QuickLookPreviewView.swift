import SwiftUI

/// The SwiftUI body rendered in the Finder Quick Look preview pane for
/// `.yaml` and `.yml` files.
///
/// The view is intentionally host-agnostic: it can be embedded in a
/// Quick Look preview extension (where it would be hosted by an
/// `NSHostingController` writing to a `QLPreviewRequest` context), or
/// used in the host app's previewer for development.
public struct QuickLookPreviewView: View {
    public let stats: YAMLPreviewStats

    public init(stats: YAMLPreviewStats) {
        self.stats = stats
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if stats.isSubscription {
                subscriptionBanner
            }

            Divider()

            statsRow

            if !stats.protocolBreakdown.isEmpty {
                protocolBreakdown
            }

            if !stats.firstNodes.isEmpty {
                nodeTable
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(24)
        .frame(width: 600, height: 800)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Riptide 配置文件")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Clash 格式 YAML")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var subscriptionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("订阅配置")
                    .font(.caption)
                    .fontWeight(.medium)
                Text(stats.sanitizedSubscriptionURL ?? "—")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statsRow: some View {
        HStack(spacing: 24) {
            statCard(label: "代理节点", value: stats.proxyCount, icon: "server.rack")
            statCard(label: "代理组", value: stats.groupCount, icon: "rectangle.3.group")
            statCard(label: "规则", value: stats.ruleCount, icon: "list.bullet.rectangle")
        }
    }

    private func statCard(label: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(value)")
                .font(.system(.title, design: .rounded))
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var protocolBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("协议分布")
                .font(.headline)
            let entries = stats.protocolBreakdown.sorted { $0.value > $1.value }
            FlowLayout(spacing: 8) {
                ForEach(entries, id: \.key) { entry in
                    HStack(spacing: 4) {
                        Text(YAMLPreviewParser.displayType(forRawType: entry.key))
                            .font(.caption)
                        Text("\(entry.value)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
        }
    }

    private var nodeTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("节点预览")
                    .font(.headline)
                Spacer()
                if stats.proxyCount > stats.firstNodes.count {
                    Text("前 \(stats.firstNodes.count) / \(stats.proxyCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 0) {
                nodeTableRow(name: "名称", type: "协议", server: "服务器", isHeader: true)
                Divider()
                ForEach(Array(stats.firstNodes.enumerated()), id: \.offset) { _, node in
                    nodeTableRow(name: node.name, type: node.displayType, server: node.server, isHeader: false)
                    if node != stats.firstNodes.last {
                        Divider()
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func nodeTableRow(name: String, type: String, server: String, isHeader: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(type)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(typeColor(for: type).opacity(0.18))
                .foregroundStyle(typeColor(for: type))
                .clipShape(Capsule())
                .frame(width: 90, alignment: .leading)
            Text(server)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(width: 200, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHeader ? Color(nsColor: .controlBackgroundColor).opacity(0.6) : .clear)
    }

    private func typeColor(for type: String) -> Color {
        switch type.lowercased() {
        case "shadowsocks", "ss", "ssm": return .blue
        case "vmess": return .purple
        case "vless": return .indigo
        case "trojan": return .red
        case "hysteria2", "hy2", "hysteria": return .orange
        case "snell": return .teal
        case "tuic": return .pink
        case "wireguard", "wg": return .green
        case "http", "socks5": return .gray
        default: return .secondary
        }
    }

    private var footer: some View {
        HStack {
            if let updated = stats.updatedAt {
                Text("最后更新: ")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                + Text(updated, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Riptide Quick Look")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

/// A minimal flow layout that wraps children onto multiple lines when
/// they don't fit horizontally. Used for the protocol-type chip list.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
