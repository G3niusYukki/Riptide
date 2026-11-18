import SwiftUI

/// Compact status chip used on the dashboard hero and menu bar.
struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(Theme.Typography.caption)
            .fontWeight(.medium)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// One numeric metric: label, monospaced value, optional caption.
struct MetricTile: View {
    let title: String
    let value: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tint)
                .frame(width: 18, height: 3)
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.subtext)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(Theme.Typography.caption2)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(Theme.activityCard, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.cardBorder.opacity(0.35), lineWidth: 0.5)
        )
    }
}

/// Grouped surface for a chart or a short list. Mirrors the activity-card
/// granularity of a dedicated overview pane without copying its artwork.
struct ActivityCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label(title, systemImage: systemImage)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.text)
            content()
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.activityCard, in: RoundedRectangle(cornerRadius: Theme.largeRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.largeRadius)
                .stroke(Theme.cardBorder.opacity(0.35), lineWidth: 0.5)
        )
    }
}

/// One recent connection, host on the left and a proxy pill on the right.
struct ActivityConnectionRow: View {
    let host: String
    let proxyName: String

    private var isDirect: Bool { proxyName == "Direct" }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: isDirect ? "arrow.up.right" : "arrow.triangle.swap")
                .font(Theme.Typography.caption)
                .foregroundStyle(isDirect ? Theme.success : Theme.accent)
                .frame(width: 16)
            Text(host)
                .font(Theme.Typography.monoCaption)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Theme.Spacing.sm)
            Text(proxyName)
                .font(Theme.Typography.caption2)
                .foregroundStyle(isDirect ? Theme.success : Theme.accent)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 2)
                .background((isDirect ? Theme.success : Theme.accent).opacity(0.14), in: Capsule())
        }
    }
}

func formatSpeed(_ bytesPerSecond: Int64) -> String {
    let absSpeed = abs(Double(bytesPerSecond))
    switch absSpeed {
    case 0: return "0 B/s"
    case 1..<1024: return String(format: "%.0f B/s", absSpeed)
    case 1024..<(1024 * 1024): return String(format: "%.1f KB/s", absSpeed / 1024.0)
    case (1024 * 1024)..<(1024 * 1024 * 1024): return String(format: "%.1f MB/s", absSpeed / (1024.0 * 1024.0))
    default: return String(format: "%.1f GB/s", absSpeed / (1024.0 * 1024.0 * 1024.0))
    }
}
