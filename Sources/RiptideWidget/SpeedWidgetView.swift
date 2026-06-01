import SwiftUI
import WidgetKit

/// The SwiftUI body for the Riptide speed widget.
public struct SpeedWidgetView: View {
    public let entry: SpeedProvider.Entry
    @Environment(\.widgetFamily) private var family

    public init(entry: SpeedProvider.Entry) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            Spacer(minLength: 4)

            HStack(spacing: 12) {
                speedColumn(label: "↑", bytes: entry.upload, color: .green)
                speedColumn(label: "↓", bytes: entry.download, color: .blue)
            }

            Text(entry.date, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: "network")
                .foregroundStyle(.blue)
            Text(entry.nodeName)
                .font(.caption)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func speedColumn(label: String, bytes: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Self.formatBytes(bytes))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private var accessibilityDescription: String {
        let upload = Self.formatBytes(entry.upload)
        let download = Self.formatBytes(entry.download)
        return "Riptide \(entry.nodeName),上传 \(upload),下载 \(download)"
    }

    /// Format a bytes-per-second value as a human-readable speed string.
    nonisolated public static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B/s" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB/s", Double(bytes) / 1024) }
        return String(format: "%.1f MB/s", Double(bytes) / 1024 / 1024)
    }
}
