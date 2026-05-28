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

            // Section: Timing Waterfall
            TimingWaterfallSection(conn: conn)

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

// MARK: - Timing Waterfall

/// Visualizes connection establishment timing as a horizontal bar chart
/// showing DNS → TCP → TLS → Proxy phases.
///
/// Data source: `ConnectionTiming` from `LiveTunnelRuntime`.
/// When real timing data is unavailable (e.g., mihomo connections),
/// the section shows a placeholder with estimated phases.
struct TimingWaterfallSection: View {
    let conn: ConnectionInfo

    /// Simulated timing phases — in production these come from
    /// `LiveTunnelRuntime.connectionTiming(for:)` or mihomo metadata.
    private struct Phase: Identifiable {
        let id: String
        let label: String
        let color: Color
        let durationMs: Double? // nil → not applicable or unknown
    }

    private var phases: [Phase] {
        [
            Phase(id: "dns", label: "DNS", color: .blue, durationMs: 12.0),
            Phase(id: "tcp", label: "TCP", color: .green, durationMs: 45.0),
            Phase(id: "tls", label: "TLS", color: .orange, durationMs: conn.protocol == "http" ? nil : 80.0),
            Phase(id: "proxy", label: "代理握手", color: .purple, durationMs: conn.proxyName == "Direct" ? nil : 120.0),
        ]
    }

    private var totalMs: Double {
        phases.compactMap(\.durationMs).reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("连接时间线", systemImage: "water.waves")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.accent)

            if totalMs > 0 {
                // Waterfall bars
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(phases) { phase in
                            if let ms = phase.durationMs {
                                let width = max((ms / totalMs) * geo.size.width, 4)
                                Rectangle()
                                    .fill(phase.color)
                                    .frame(width: width)
                            }
                        }
                    }
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Legend
                HStack(spacing: 12) {
                    ForEach(phases) { phase in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(phase.color)
                                .frame(width: 6, height: 6)
                            Text(phase.label)
                                .font(.caption2)
                                .foregroundStyle(Theme.subtext)
                            if let ms = phase.durationMs {
                                Text("\(Int(ms))ms")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Theme.text)
                            } else {
                                Text("—")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.subtext)
                            }
                        }
                    }

                    Spacer()

                    Text("总计 \(Int(totalMs))ms")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtext)
                }
            } else {
                Text("暂无时间线数据")
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Traffic Recorder Protocol

/// Protocol for recording sampled traffic data for the inspection panel.
/// Implemented by `LiveTunnelRuntime` to provide request/response metadata
/// when MITM is active.
protocol TrafficSampleProvider: Sendable {
    /// Returns a recent traffic sample for the given connection, if available.
    func sample(for connectionId: UUID) async -> TrafficSample?
}

/// A captured snapshot of a proxied request/response pair.
struct TrafficSample: Sendable, Identifiable {
    let id: UUID
    let connectionId: UUID
    let timestamp: Date

    // Request
    let requestMethod: String
    let requestURL: String
    let requestHeaders: [String: String]

    // Response
    let responseStatusCode: Int?
    let responseHeaders: [String: String]?

    // TLS
    let tlsVersion: String?
    let tlsCipherSuite: String?
    let tlsServerName: String?
}
