import SwiftUI

struct ProxyTabView: View {
    @Bindable var vm: AppViewModel
    @State private var isTestingAll = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(vm.proxyGroups) { group in
                    ProxyGroupCard(group: group, vm: vm)
                }
            }
            .padding()
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .toolbar {
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
            }
        }
    }
}

struct ProxyGroupCard: View {
    let group: ProxyGroupDisplay
    @Bindable var vm: AppViewModel
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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
                ForEach(group.nodes) { node in
                    ProxyNodeRow(node: node, isSelected: node.name == group.selectedNodeName) {
                        Task {
                            await vm.selectProxy(groupID: group.id, nodeName: node.name)
                        }
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

struct ProxyNodeRow: View {
    let node: ProxyNodeDisplay
    let isSelected: Bool
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

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(node.name)
                .foregroundStyle(Theme.text)
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
    }
}
