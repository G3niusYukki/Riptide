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
                    color: .blue
                )

                TrafficStatBox(
                    title: "Download",
                    value: formatSpeed(currentDownSpeed),
                    icon: "arrow.down",
                    color: .green
                )
            }

            // Total Traffic
            HStack(spacing: 20) {
                TotalTrafficBox(
                    title: "Total Up",
                    bytes: totalTraffic.totalUp,
                    icon: "arrow.up.circle",
                    color: .blue
                )

                TotalTrafficBox(
                    title: "Total Down",
                    bytes: totalTraffic.totalDown,
                    icon: "arrow.down.circle",
                    color: .green
                )
            }

            // Chart
            Chart {
                ForEach(Array(history.enumerated()), id: \.offset) { index, point in
                    LineMark(
                        x: .value("Time", index),
                        y: .value("Speed", point.upSpeed)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", index),
                        y: .value("Speed", point.upSpeed)
                    )
                    .foregroundStyle(.blue.opacity(0.1))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", index),
                        y: .value("Speed", point.downSpeed)
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Time", index),
                        y: .value("Speed", point.downSpeed)
                    )
                    .foregroundStyle(.green.opacity(0.1))
                    .interpolationMethod(.catmullRom)
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
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                    Text("Upload")
                        .font(.caption)

                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Download")
                        .font(.caption)
                }
            }
            .frame(height: 200)

            // Peak Speeds
            HStack {
                VStack(alignment: .leading) {
                    Text("Peak Upload")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatSpeed(peakUpload))
                        .font(.callout)
                        .foregroundStyle(.blue)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Peak Download")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatSpeed(peakDownload))
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal)

            Spacer()

            // Control Buttons
            HStack {
                Button("Reset") {
                    Task {
                        await viewModel.reset()
                        await refreshData()
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(timer == nil ? "Start Monitoring" : "Stop Monitoring") {
                    toggleMonitoring()
                }
                .buttonStyle(.borderedProminent)
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
        let h = await viewModel.history
        let total = await viewModel.totalTraffic
        let peakUp = await viewModel.peakUploadSpeed
        let peakDown = await viewModel.peakDownloadSpeed
        let speed = await viewModel.currentSpeed()

        await MainActor.run {
            history = h
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

    private func toggleMonitoring() {
        if timer != nil {
            timer?.invalidate()
            timer = nil
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task {
                    await viewModel.fetchTrafficFromAPI()
                    await refreshData()
                }
            }
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
