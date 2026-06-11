import SwiftUI
import AppKit
import Riptide

struct ProxyTabView: View {
    @Bindable var vm: AppViewModel
    @State private var isTestingAll = false
    @State private var sortOrder: ProxySortOrder = .default
    @State private var filter: ProxyFilter = .all
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.proxyGroups) { group in
                        ProxyGroupCard(
                            group: group,
                            vm: vm,
                            sortOrder: sortOrder,
                            filter: filter,
                            searchText: searchText
                        )
                        .accessibilityIdentifier(A11yID.Proxy.groupCard + ".\(group.name)")
                    }
                }
                .padding()
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .searchable(text: $searchText, prompt: "搜索节点")
            .toolbar {
                ToolbarItem {
                    Menu {
                        Picker("排序", selection: $sortOrder) {
                            ForEach(ProxySortOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        Divider()
                        Picker("过滤", selection: $filter) {
                            Text("全部").tag(ProxyFilter.all)
                            Text("可用").tag(ProxyFilter.available)
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem {
                    Button {
                        isTestingAll = true
                        Task {
                            await vm.testDelay()
                            isTestingAll = false
                        }
                    } label: {
                        Label("延迟测试", systemImage: "speedometer")
                    }
                    .disabled(isTestingAll)
                    .accessibilityIdentifier(A11yID.Proxy.testDelayButton)
                }
            }
        }
    }
}

struct ProxyGroupCard: View {
    let group: ProxyGroupDisplay
    @Bindable var vm: AppViewModel
    let sortOrder: ProxySortOrder
    let filter: ProxyFilter
    let searchText: String
    @State private var isExpanded = true

    private var visibleNodes: [ProxyNodeDisplay] {
        ProxyTabFilter.applySortAndFilter(
            group.nodes,
            sort: sortOrder,
            filter: filter,
            searchText: searchText
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(Theme.accent)
                    .frame(width: 16)
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Text("(\(group.kind.rawValue))")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                Spacer()
                if let selected = group.selectedNodeName {
                    Text(selected)
                        .font(.caption)
                        .foregroundStyle(Theme.success)
                }
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }

            Divider().background(Theme.subtext.opacity(0.3))

            if isExpanded {
                ForEach(visibleNodes) { node in
                    ProxyNodeRow(
                        node: node,
                        isSelected: node.name == group.selectedNodeName,
                        group: group,
                        vm: vm,
                        onSelect: {
                            Task {
                                await vm.selectProxy(groupID: group.id, nodeName: node.name)
                            }
                        }
                    )
                    .accessibilityIdentifier(A11yID.Proxy.nodeRow + ".\(node.name)")
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
    }
}

struct ProxyNodeRow: View {
    let node: ProxyNodeDisplay
    let isSelected: Bool
    let group: ProxyGroupDisplay
    @Bindable var vm: AppViewModel
    let onSelect: () -> Void

    private var statusColor: Color {
        switch node.status {
        case .available: return Theme.success
        case .timeout: return Theme.danger
        case .error: return Theme.danger
        }
    }

    private var delayColor: Color {
        guard let ms = node.delayMs else { return Theme.subtext }
        if ms < 100 { return Theme.success }
        if ms < 300 { return Color.yellow }
        return Theme.danger
    }

    /// `ProxyNodeDisplay.kind` is already a `ProxyKind` enum, so this is a passthrough.
    private var protocolKind: ProxyKind { node.kind }

    var body: some View {
        HStack(spacing: 8) {
            CountryFlagView(nodeName: node.name, size: 14)
            ProtocolBadge(kind: protocolKind)
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(node.name)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer()
            if let ms = node.delayMs {
                Text("\(ms)ms")
                    .font(.caption)
                    .foregroundStyle(delayColor)
            }
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .contextMenu {
            Button {
                Task { await vm.testDelay(groupID: group.id) }
            } label: { Label("测试延迟", systemImage: "speedometer") }

            Button {
                let info = "\(node.name) (\(node.kind))"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(info, forType: .string)
            } label: { Label("复制节点信息", systemImage: "doc.on.doc") }
        }
    }
}
