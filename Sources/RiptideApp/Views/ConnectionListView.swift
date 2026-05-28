import SwiftUI

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
    @State private var expandedConnectionId: UUID?
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
                                expandedConnectionId = nil
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
