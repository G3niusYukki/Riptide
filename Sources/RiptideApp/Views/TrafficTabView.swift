import SwiftUI

struct TrafficTabView: View {
    @Bindable var vm: AppViewModel

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1024 / 1024) }
        return String(format: "%.2f GB", Double(bytes) / 1024 / 1024 / 1024)
    }

    private func formatSpeed(_ bytesPerSec: Int64) -> String {
        if bytesPerSec < 1024 { return "\(bytesPerSec) B/s" }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", Double(bytesPerSec) / 1024) }
        return String(format: "%.1f MB/s", Double(bytesPerSec) / 1024 / 1024)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Total traffic
                HStack(spacing: 24) {
                    VStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.accent)
                        Text(formatBytes(vm.totalTrafficUp))
                            .font(.title2.bold())
                            .foregroundStyle(Theme.text)
                        Text("上传")
                            .font(.caption)
                            .foregroundStyle(Theme.subtext)
                    }
                    VStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.success)
                        Text(formatBytes(vm.totalTrafficDown))
                            .font(.title2.bold())
                            .foregroundStyle(Theme.text)
                        Text("下载")
                            .font(.caption)
                            .foregroundStyle(Theme.subtext)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))

                // Speed
                HStack {
                    HStack {
                        Image(systemName: "arrow.up").foregroundStyle(Theme.accent)
                        Text(formatSpeed(vm.currentSpeedUp))
                            .foregroundStyle(Theme.text)
                    }
                    Spacer()
                    HStack {
                        Image(systemName: "arrow.down").foregroundStyle(Theme.success)
                        Text(formatSpeed(vm.currentSpeedDown))
                            .foregroundStyle(Theme.text)
                    }
                }
                .font(.headline)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))

                // Active connections — real-time list
                ConnectionListView(vm: vm)
            }
            .padding()
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
