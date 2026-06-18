import SwiftUI
import AppKit

/// Filter mode for connection list.
enum ConnectionFilter: String, CaseIterable {
    case all = "全部"
    case proxied = "代理"
    case direct = "直连"

    func matches(_ conn: ConnectionInfo) -> Bool {
        switch self {
        case .all: return true
        case .proxied: return conn.proxyName != "Direct"
        case .direct: return conn.proxyName == "Direct"
        }
    }
}

/// Sort order for connection list.
enum ConnectionSort: String, CaseIterable {
    case newest = "最新"
    case host = "域名"
    case traffic = "流量"

    func comparator() -> (ConnectionInfo, ConnectionInfo) -> Bool {
        switch self {
        case .newest:
            return { ($0.startTime ?? "") > ($1.startTime ?? "") }
        case .host:
            return { $0.host.localizedCompare($1.host) == .orderedAscending }
        case .traffic:
            return { ($0.uploadBytes + $0.downloadBytes) > ($1.uploadBytes + $1.downloadBytes) }
        }
    }
}

/// Real-time view of active connections with search, filter, sort, and close support.
struct ConnectionListView: View {
    @Bindable var vm: AppViewModel
    @State private var searchText = ""
    @State private var isClosingAll = false
    @State private var selectedConnection: ConnectionInfo?
    @State private var showInspector = false
    @State private var selectedFilter: ConnectionFilter = .all
    @State private var selectedSort: ConnectionSort = .newest

    private var filteredConnections: [ConnectionInfo] {
        var result = vm.activeConnections.filter { selectedFilter.matches($0) }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { conn in
                conn.host.lowercased().contains(query)
                || conn.proxyName.lowercased().contains(query)
                || conn.`protocol`.lowercased().contains(query)
                || (conn.matchedRule?.lowercased().contains(query) ?? false)
            }
        }
        result.sort(by: selectedSort.comparator())
        return result
    }

    private var filterCounts: [ConnectionFilter: Int] {
        [
            .all: vm.activeConnections.count,
            .proxied: vm.activeConnections.filter { $0.proxyName != "Direct" }.count,
            .direct: vm.activeConnections.filter { $0.proxyName == "Direct" }.count,
        ]
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

            // Filter + Sort toolbar
            if !vm.activeConnections.isEmpty {
                HStack(spacing: 8) {
                    // Filter chips
                    ForEach(ConnectionFilter.allCases, id: \.self) { filter in
                        let count = filterCounts[filter] ?? 0
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedFilter = filter
                                selectedConnection = nil
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(filter.rawValue)
                                Text("(\(count))")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.subtext)
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(selectedFilter == filter ? Theme.accent : Color.white.opacity(0.05))
                            .foregroundStyle(selectedFilter == filter ? .black : Theme.text)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    // Sort picker
                    Picker("排序", selection: $selectedSort) {
                        ForEach(ConnectionSort.allCases, id: \.self) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }

            if vm.activeConnections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.subtext)
                        .symbolEffect(.pulse, isActive: vm.activeConnections.isEmpty)
                    Text("暂无连接")
                        .foregroundStyle(Theme.subtext)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
            } else {
                List(filteredConnections, selection: $selectedConnection) { conn in
                    ConnectionRow(
                        conn: conn,
                        onClose: {
                            Task { await vm.closeConnection(id: conn.backendId) }
                        }
                    )
                    .contentShape(Rectangle())
                    .accessibilityIdentifier(A11yID.Traffic.connectionRow + ".\(conn.id)")
                }
                .listStyle(.plain)
                .refreshable {
                    await vm.refreshStats()
                }
                .frame(maxHeight: 400)
                .onChange(of: selectedConnection) { _, newValue in
                    showInspector = newValue != nil
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .searchable(text: $searchText, prompt: "搜索连接 / 域名 / 代理")
        .inspector(isPresented: $showInspector) {
            if let connection = selectedConnection {
                ConnectionDetailView(conn: connection) {
                    Task { await vm.closeConnection(id: connection.backendId) }
                }
                .inspectorColumnWidth(min: 300, ideal: 350, max: 500)
            }
        }
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

            // Close button on hover
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
        .contextMenu {
            Button {
                onClose()
            } label: { Label("关闭连接", systemImage: "xmark.circle") }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(conn.host, forType: .string)
            } label: { Label("复制域名", systemImage: "doc.on.doc") }
        }
    }
}
