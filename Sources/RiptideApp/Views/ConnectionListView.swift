import SwiftUI

/// Real-time view of active connections with search and close support.
struct ConnectionListView: View {
    @Bindable var vm: AppViewModel
    @State private var searchText = ""
    @State private var isClosingAll = false

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
                // Connection list
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredConnections) { conn in
                            ConnectionRow(conn: conn) {
                                Task { await vm.closeConnection(id: conn.backendId) }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 300)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .searchable(text: $searchText, prompt: "搜索连接 / 域名 / 代理")
    }
}

/// A single connection row.
struct ConnectionRow: View {
    let conn: ConnectionInfo
    let onClose: () -> Void
    @State private var isHovered = false

    private var proxyColor: Color {
        if conn.proxyName == "Direct" { return Theme.success }
        return Theme.accent
    }

    var body: some View {
        HStack(spacing: 8) {
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

            // Close button
            if isHovered {
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
        .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
