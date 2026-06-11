import SwiftUI
import Riptide

// MARK: - Node Health Card

/// Top-N proxy groups with their healthy-node ratios. A node counts as
/// "healthy" when its last health-check delay is non-nil.
struct NodeHealthCard: View {
    @Bindable var vm: AppViewModel

    private var topGroups: [ProxyGroupDisplay] {
        Array(vm.proxyGroups.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("节点健康").font(.subheadline).foregroundStyle(Theme.subtext)

            if topGroups.isEmpty {
                Text("暂无代理组")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(topGroups) { group in
                    GroupHealthRow(group: group)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityIdentifier(A11yID.Dashboard.nodeHealth)
    }
}

private struct GroupHealthRow: View {
    let group: ProxyGroupDisplay

    private var healthyCount: Int {
        group.nodes.filter { $0.status == .available }.count
    }
    private var total: Int { group.nodes.count }
    private var ratio: Double { total > 0 ? Double(healthyCount) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 8) {
            Text(group.name)
                .font(.caption)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.success)
                        .frame(width: max(0, geo.size.width * ratio))
                    Rectangle()
                        .fill(Theme.danger.opacity(0.3))
                        .frame(width: max(0, geo.size.width * (1 - ratio)))
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())

            Text("\(healthyCount)/\(total)")
                .font(.caption2.monospaced())
                .foregroundStyle(Theme.subtext)
                .frame(width: 50, alignment: .trailing)
        }
    }
}
