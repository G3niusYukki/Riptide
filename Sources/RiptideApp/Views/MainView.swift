import SwiftUI
import Charts
import Riptide

struct MainView: View {
    @State private var vpnVM = VPNViewModel()
    @State private var proxyVM = ProxyViewModel()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(minWidth: 800, minHeight: 500)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Riptide")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Divider()

            List(proxyVM.proxyNodes, id: \ProxyNode.name, selection: $proxyVM.selectedProxy) { node in
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(node.name)
                        .font(.system(.body))
                    Spacer()
                    Text(node.kind.kindString)
                        .font(.system(.caption))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.sidebar)
        }
        .frame(width: 240)
    }

    private var detail: some View {
        VStack(spacing: 16) {
            header
            Divider()
            trafficChart
            Spacer()
        }
        .padding(24)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.title2.bold())
                Text(vpnVM.statusText)
                    .foregroundStyle(vpnVM.isRunning ? .green : .secondary)
            }
            Spacer()
            Button(vpnVM.isRunning ? "Stop" : "Start") {
                Task {
                    if vpnVM.isRunning {
                        await vpnVM.stop()
                    } else {
                        await vpnVM.start()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var trafficChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Traffic")
                .font(.headline)
            HStack {
                Label("Up: \(formatBytes(vpnVM.bytesUp))", systemImage: "arrow.up")
                Label("Down: \(formatBytes(vpnVM.bytesDown))", systemImage: "arrow.down")
                Label("Active: \(vpnVM.activeConnections)", systemImage: "network")
            }
            .font(.system(.callout))
            .foregroundStyle(.secondary)
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1024 / 1024) }
        return String(format: "%.2f GB", Double(bytes) / 1024 / 1024 / 1024)
    }
}

extension ProxyKind {
    var kindString: String {
        switch self {
        case .http: return "HTTP"
        case .socks5: return "SOCKS5"
        case .shadowsocks: return "SS"
        case .vmess: return "VMess"
        case .vless: return "VLESS"
        case .trojan: return "Trojan"
        case .hysteria2: return "H2"
        case .snell: return "Snell"
        case .tuic: return "TUIC"
        case .relay: return "Relay"
        }
    }
}
