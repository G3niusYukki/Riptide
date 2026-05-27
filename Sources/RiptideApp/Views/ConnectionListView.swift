import SwiftUI

/// Real-time view of active connections with search and close support.
struct ConnectionListView: View {
    @Bindable var vm: AppViewModel
    @State private var searchText = ""
    @State private var isClosingAll = false
    @State private var expandedConnectionId: UUID?

    private var filteredConnections: [ConnectionInfo] {
        guard !searchText.isEmpty else { return vm.activeConnections }
        let query = searchText.lowercased()
        return vm.activeConnections.filter { conn in
            conn.host.lowercased().contains(query)
            || conn.proxyName.lowercased().contains(query)
            || conn.`protocol`.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("活跃连接 (\(vm.activeConnections.count))")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                if !vm.activeConnections.isEmpty {
                    Button {
                        withAnimation { isClosingAll = true }
                        Task {
                            await vm.closeAllConnections()
                            await MainActor.run { isClosingAll = false }
                        }
                    } label: {
                        Label(isClosingAll ? "关闭中…" : "全部关闭", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .disabled(isClosingAll)
                }
            }

            if vm.activeConnections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.subtext)
                    Text("暂无连接")
                        .foregroundStyle(Theme.subtext)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
            } else {
                // Connection list with expandable detail
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredConnections) { conn in
                            ConnectionRow(
                                conn: conn,
                                isExpanded: expandedConnectionId == conn.id,
                                onClose: {
                                    Task { await vm.closeConnection(id: conn.backendId) }
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedConnectionId == conn.id {
                                        expandedConnectionId = nil
                                    } else {
                                        expandedConnectionId = conn.id
                                    }
                                }
                            }

                            if expandedConnectionId == conn.id {
                                ConnectionDetailView(conn: conn) {
                                    Task { await vm.closeConnection(id: conn.backendId) }
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 400)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .searchable(text: $searchText, prompt: "搜索连接 / 域名 / 代理")
    }
}

/// A single connection row with tap-to-expand support.
struct ConnectionRow: View {
    let conn: ConnectionInfo
    let isExpanded: Bool
    let onClose: () -> Void
    @State private var isHovered = false

    private var proxyColor: Color {
        if conn.proxyName == "Direct" { return Theme.success }
        return Theme.accent
    }

    var body: some View {
        HStack(spacing: 8) {
            // Expand chevron indicator
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
                .frame(width: 10)

            // Protocol badge
            Text(conn.`protocol`)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.accent.opacity(0.15))
                .clipShape(Capsule())

            // Host
            Text(conn.host)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Proxy used
            Text(conn.proxyName)
                .font(.caption)
                .foregroundStyle(proxyColor)

            // Close button — always visible on expanded, hover for collapsed
            if isHovered || isExpanded {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isExpanded ? Theme.accent.opacity(0.08) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
