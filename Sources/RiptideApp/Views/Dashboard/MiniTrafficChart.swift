import SwiftUI
import Charts
import Riptide

// MARK: - Mini Traffic Chart

/// Tiny inline chart that pulses with the current upload/download speed.
///
/// We don't keep a history buffer here (that's the full TrafficChartView's
/// job); we just plot a single point at `Date()` so the user sees the chart
/// react in step with the Speed Box cards above it.
struct MiniTrafficChart: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        Chart {
            LineMark(
                x: .value("Time", Date()),
                y: .value("Up", Double(vm.currentSpeedUp))
            )
            .foregroundStyle(Theme.accent)
            .interpolationMethod(.linear)

            LineMark(
                x: .value("Time", Date()),
                y: .value("Down", Double(vm.currentSpeedDown))
            )
            .foregroundStyle(Theme.success)
            .interpolationMethod(.linear)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 60)
        .accessibilityIdentifier(A11yID.Dashboard.miniChart)
    }
}
