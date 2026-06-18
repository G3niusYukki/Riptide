import SwiftUI
import Charts
import Riptide

// MARK: - Traffic Chart View

@MainActor
public struct TrafficChartView: View {
    @State private var viewModel: TrafficViewModel
    @State private var timer: Timer?
    @State private var history: [TrafficDataPoint] = []
    @State private var totalTraffic = TrafficStatistics()
    @State private var peakUpload: Double = 0
    @State private var peakDownload: Double = 0
    @State private var currentUpSpeed: Double = 0
    @State private var currentDownSpeed: Double = 0
    @State private var timeRange: TrafficTimeRange = .oneMin

    public init(viewModel: TrafficViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Statistics Header
            HStack(spacing: 20) {
                TrafficStatBox(
                    title: "Upload",
                    value: formatSpeed(currentUpSpeed),
                    icon: "arrow.up",
                    color: Theme.accent
                )

                TrafficStatBox(
                    title: "Download",
                    value: formatSpeed(currentDownSpeed),
                    icon: "arrow.down",
                    color: Theme.success
                )
            }

            // Total Traffic
            HStack(spacing: 20) {
                TotalTrafficBox(
                    title: "Total Up",
                    bytes: totalTraffic.totalUp,
                    icon: "arrow.up.circle",
                    color: Theme.accent
                )

                TotalTrafficBox(
                    title: "Total Down",
                    bytes: totalTraffic.totalDown,
                    icon: "arrow.down.circle",
                    color: Theme.success
                )
            }

            // Chart
            Chart {
                ForEach(Array(history.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Time", Date(timeIntervalSince1970: point.timestamp)),
                        y: .value("Speed", point.upSpeed)
                    )
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.catmullRom)
                    .accessibilityLabel("Upload")
                    .accessibilityValue("\(Int(point.upSpeed)) bytes per second")

                    AreaMark(
                        x: .value("Time", Date(timeIntervalSince1970: point.timestamp)),
                        y: .value("Speed", point.upSpeed)
                    )
                    .foregroundStyle(Theme.accent.opacity(0.1))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", Date(timeIntervalSince1970: point.timestamp)),
                        y: .value("Speed", point.downSpeed)
                    )
                    .foregroundStyle(Theme.success)
                    .interpolationMethod(.catmullRom)
                    .accessibilityLabel("Download")
                    .accessibilityValue("\(Int(point.downSpeed)) bytes per second")

                    AreaMark(
                        x: .value("Time", Date(timeIntervalSince1970: point.timestamp)),
                        y: .value("Speed", point.downSpeed)
                    )
                    .foregroundStyle(Theme.success.opacity(0.1))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    if let speed = value.as(Double.self) {
                        AxisValueLabel(formatSpeed(speed))
                    }
                }
            }
            .chartLegend(position: .top, alignment: .leading) {
                HStack {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                    Text("Upload")
                        .font(.caption)

                    Circle()
                        .fill(Theme.success)
                        .frame(width: 8, height: 8)
                    Text("Download")
                        .font(.caption)
                }
            }
            .frame(height: 200)
            .accessibilityIdentifier(A11yID.Traffic.chart)

            // Peak Speeds
            HStack {
                VStack(alignment: .leading) {
                    Text("Peak Upload")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatSpeed(peakUpload))
                        .font(.callout)
                        .foregroundStyle(Theme.accent)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Peak Download")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatSpeed(peakDownload))
                        .font(.callout)
                        .foregroundStyle(Theme.success)
                }
            }
            .padding(.horizontal)

            Spacer()

            // Controls
            HStack {
                Picker("时间范围", selection: $timeRange) {
                    ForEach(TrafficTimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: timeRange) { _, newRange in
                    Task { await viewModel.setTimeRange(newRange) }
                }

                Button {
                    Task { await viewModel.reset() }
                } label: {
                    Label("重置", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
        }
        .padding()
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .task {
            await refreshData()
        }
    }

    private func refreshData() async {
        let hist = await viewModel.history
        let total = await viewModel.totalTraffic
        let peakUp = await viewModel.peakUploadSpeed
        let peakDown = await viewModel.peakDownloadSpeed
        let speed = await viewModel.currentSpeed()

        await MainActor.run {
            history = hist
            totalTraffic = total
            peakUpload = peakUp
            peakDownload = peakDown
            currentUpSpeed = speed.up
            currentDownSpeed = speed.down
        }
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let absSpeed = abs(bytesPerSecond)
        let sign = bytesPerSecond < 0 ? "-" : ""

        switch absSpeed {
        case 0:
            return "0 B/s"
        case 1..<1024:
            return String(format: "\(sign)%.0f B/s", absSpeed)
        case 1024..<(1024 * 1024):
            return String(format: "\(sign)%.1f KB/s", absSpeed / 1024.0)
        case (1024 * 1024)..<(1024 * 1024 * 1024):
            return String(format: "\(sign)%.1f MB/s", absSpeed / (1024.0 * 1024.0))
        default:
            return String(format: "\(sign)%.1f GB/s", absSpeed / (1024.0 * 1024.0 * 1024.0))
        }
    }
}

// MARK: - Traffic Stat Box

struct TrafficStatBox: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Total Traffic Box

struct TotalTrafficBox: View {
    let title: String
    let bytes: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatBytes(bytes))
                    .font(.callout)
                    .fontWeight(.medium)
            }

            Spacer()
        }
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
