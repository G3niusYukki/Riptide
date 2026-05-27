import SwiftUI

// MARK: - Connection Detail View

/// Inline-expanded detail panel for a single connection.
/// Shows 5-tuple, rule hit tracing, timing, and bytes transferred.
struct ConnectionDetailView: View {
    let conn: ConnectionInfo
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .background(Theme.accent.opacity(0.3))

            // Section: 5-Tuple
            detailSection("连接信息", icon: "point.3.connected.trianglepath.dotted") {
                detailRow("协议", conn.protocol)
                if let networkType = conn.networkType { detailRow("类型", networkType) }
                detailRow("目标", conn.host)

                let srcAddr = format5Tuple(srcIP: conn.sourceIP, srcPort: conn.sourcePort)
                let dstAddr = format5Tuple(srcIP: conn.destinationIP, srcPort: conn.destinationPort)
                if !srcAddr.isEmpty || !dstAddr.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        if !srcAddr.isEmpty {
                            Label(srcAddr, systemImage: "arrow.up.forward")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.subtext)
                        }
                        if !dstAddr.isEmpty {
                            Label(dstAddr, systemImage: "arrow.down.forward")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.subtext)
                        }
                    }
                }
            }

            // Section: Rule Hit Trace
            if let rule = conn.matchedRule, !rule.isEmpty {
                detailSection("匹配规则", icon: "arrow.triangle.branch") {
                    HStack(spacing: 4) {
                        Text(rule)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.15))
                            .clipShape(Capsule())

                        if let payload = conn.rulePayload, !payload.isEmpty, payload != rule {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(Theme.subtext)
                            Text(payload)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
            }

            // Section: Proxy Chain
            if !conn.chain.isEmpty {
                detailSection("代理链", icon: "link") {
                    HStack(spacing: 4) {
                        ForEach(Array(conn.chain.enumerated()), id: \.offset) { idx, node in
                            Text(node)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(idx == conn.chain.count - 1 ? Theme.success : Theme.subtext)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    idx == conn.chain.count - 1
                                        ? Theme.success.opacity(0.15)
                                        : Color.white.opacity(0.05)
                                )
                                .clipShape(Capsule())

                            if idx < conn.chain.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.subtext)
                            }
                        }
                    }
                }
            }

            // Section: Traffic & Timing
            detailSection("流量 / 时间", icon: "clock.arrow.circlepath") {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("上传")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtext)
                        Text(formatBytes(conn.uploadBytes))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("下载")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtext)
                        Text(formatBytes(conn.downloadBytes))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("总计")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtext)
                        Text(formatBytes(conn.uploadBytes + conn.downloadBytes))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.text)
                    }
                }

                if let start = conn.startTime, !start.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtext)
                        Text("建立于 \(start)")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtext)
                    }
                }
            }

            // Close button row
            HStack {
                Spacer()
                Button(role: .destructive) {
                    onClose()
                } label: {
                    Label("关闭连接", systemImage: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func detailSection(_ title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.accent)
            content()
                .padding(.leading, 4)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.text)
        }
    }

    private func format5Tuple(srcIP: String?, srcPort: String?) -> String {
        guard let ip = srcIP, !ip.isEmpty else { return "" }
        if let port = srcPort, !port.isEmpty {
            return "\(ip):\(port)"
        }
        return ip
    }

    private func formatBytes(_ bytes: Int) -> String {
        let absBytes = abs(bytes)
        switch absBytes {
        case 0: return "0 B"
        case 1..<1024: return "\(absBytes) B"
        case 1024..<(1024 * 1024):
            return String(format: "%.1f KB", Double(absBytes) / 1024.0)
        case (1024 * 1024)..<(1024 * 1024 * 1024):
            return String(format: "%.1f MB", Double(absBytes) / (1024.0 * 1024.0))
        default:
            return String(format: "%.1f GB", Double(absBytes) / (1024.0 * 1024.0 * 1024.0))
        }
    }
}
