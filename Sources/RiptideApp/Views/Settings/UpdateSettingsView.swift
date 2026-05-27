import SwiftUI

/// Placeholder — Sparkle temporarily disabled to debug CI Build failure.
struct UpdateSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("软件更新", systemImage: "arrow.down.circle.dotted")
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text("v2.1.0")
                .font(.callout)
                .foregroundStyle(Theme.text)
            Text("自动更新暂不可用")
                .font(.caption)
                .foregroundStyle(Theme.subtext)
        }
        .padding()
    }
}
