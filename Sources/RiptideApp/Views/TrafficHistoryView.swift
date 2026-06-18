import SwiftUI
import Charts
import Riptide

struct TrafficHistoryView: View {
    enum Range: String, CaseIterable {
        case day = "日", week = "周", month = "月"
    }

    @Bindable var vm: AppViewModel
    @State private var range: Range = .day
    @State private var dataPoints: [DateTraffic] = []
    @State private var totalUp: Int64 = 0
    @State private var totalDown: Int64 = 0

    struct DateTraffic: Identifiable {
        let id = UUID()
        let date: Date
        let up: Int64
        let down: Int64
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("历史流量").font(.headline)
                Spacer()
                Picker("", selection: $range) {
                    ForEach(Range.allCases, id: \.self) { rangeCase in
                        Text(rangeCase.rawValue).tag(rangeCase)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .onChange(of: range) { _, _ in Task { await load() } }

            HStack(spacing: 24) {
                Label("\(formatBytes(Int(totalUp))) ↑", systemImage: "arrow.up.circle.fill")
                    .foregroundStyle(Theme.accent)
                Label("\(formatBytes(Int(totalDown))) ↓", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(Theme.success)
            }
            .font(.subheadline)

            if dataPoints.isEmpty {
                Text("暂无数据").foregroundStyle(Theme.subtext).frame(maxWidth: .infinity, alignment: .center).padding()
            } else {
                Chart {
                    ForEach(dataPoints) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Up", point.up)
                        )
                        .foregroundStyle(Theme.accent)
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Down", point.down)
                        )
                        .foregroundStyle(Theme.success)
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .task { await load() }
    }

    private func load() async {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let days: Int
        switch range {
        case .day: days = 1
        case .week: days = 7
        case .month: days = 30
        }
        guard let start = cal.date(byAdding: .day, value: -days, to: now) else { return }

        let store = vm.logbook.store
        guard let result = try? await store.trafficByDate(from: start, to: now) else { return }

        var points: [DateTraffic] = []
        var sumUp: Int64 = 0
        var sumDown: Int64 = 0
        for (date, traffic) in result.sorted(by: { $0.key < $1.key }) {
            points.append(DateTraffic(date: date, up: Int64(traffic.up), down: Int64(traffic.down)))
            sumUp += Int64(traffic.up)
            sumDown += Int64(traffic.down)
        }
        await MainActor.run {
            dataPoints = points
            totalUp = sumUp
            totalDown = sumDown
        }
    }
}
