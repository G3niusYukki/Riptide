import SwiftUI
import Riptide

// MARK: - Traffic History Card

/// Three side-by-side stat boxes: today / this week / this month. Values are
/// pulled from `LogbookStore.trafficByDate(...)` and refreshed whenever
/// `vm.tunnelState` changes (so toggling the tunnel reloads the data).
struct TrafficHistoryCard: View {
    @Bindable var vm: AppViewModel
    @State private var todayUp: Int64 = 0
    @State private var todayDown: Int64 = 0
    @State private var weekUp: Int64 = 0
    @State private var weekDown: Int64 = 0
    @State private var monthUp: Int64 = 0
    @State private var monthDown: Int64 = 0

    var body: some View {
        HStack(spacing: 12) {
            statBox(title: "今日", up: todayUp, down: todayDown)
            statBox(title: "本周", up: weekUp, down: weekDown)
            statBox(title: "本月", up: monthUp, down: monthDown)
        }
        .accessibilityIdentifier(A11yID.Dashboard.trafficHistory)
        .task(id: vm.tunnelState) { await loadStats() }
    }

    private func statBox(title: String, up: Int64, down: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.subtext)
            HStack(spacing: 4) {
                Image(systemName: "arrow.up").foregroundStyle(.blue).font(.caption2)
                Text(formatBytes(Int(up))).font(.caption.monospaced())
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.down").foregroundStyle(.green).font(.caption2)
                Text(formatBytes(Int(down))).font(.caption.monospaced())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadStats() async {
        let store = vm.logbook.store
        let now = Date()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let weekStart = cal.date(byAdding: .day, value: -7, to: today),
              let monthStart = cal.date(byAdding: .day, value: -30, to: today) else {
            return
        }

        // Fetch and aggregate. The store uses a UTC calendar for the day key,
        // so for "today" we have to use the same UTC start-of-day.
        let weekStats = (try? await store.trafficByDate(from: weekStart, to: now)) ?? [:]
        let monthStats = (try? await store.trafficByDate(from: monthStart, to: now)) ?? [:]
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let utcToday = utcCal.startOfDay(for: now)
        let todayStats = weekStats[utcToday] ?? (up: 0, down: 0)

        let newTodayUp = Int64(todayStats.up)
        let newTodayDown = Int64(todayStats.down)
        let newWeekUp = Int64(weekStats.values.reduce(0) { $0 + $1.up })
        let newWeekDown = Int64(weekStats.values.reduce(0) { $0 + $1.down })
        let newMonthUp = Int64(monthStats.values.reduce(0) { $0 + $1.up })
        let newMonthDown = Int64(monthStats.values.reduce(0) { $0 + $1.down })

        await MainActor.run {
            todayUp = newTodayUp
            todayDown = newTodayDown
            weekUp = newWeekUp
            weekDown = newWeekDown
            monthUp = newMonthUp
            monthDown = newMonthDown
        }
    }
}
