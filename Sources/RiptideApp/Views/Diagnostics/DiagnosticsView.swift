import SwiftUI
import Riptide

// MARK: - Diagnostics View

/// Runs a battery of network and system diagnostics and displays the results.
struct DiagnosticsView: View {
    @State private var isRunning = false
    @State private var report: ActiveDiagnosticsReport?
    @State private var error: String?

    private let runner = DiagnosticsRunner()

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Label("网络诊断", systemImage: "stethoscope")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
            }

            if isRunning {
                VStack(spacing: 12) {
                    ProgressView("正在诊断…")
                        .foregroundStyle(Theme.subtext)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            } else if let report = report {
                // Summary card
                summaryCard(report: report)

                // Individual checks
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(report.checks) { check in
                            checkCard(check)
                        }
                    }
                }
            } else if let error = error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.danger)
                    Text(error)
                        .foregroundStyle(Theme.text)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.accent)
                    Text("点击下方按钮运行诊断")
                        .foregroundStyle(Theme.subtext)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            }

            Spacer()

            // Run button
            Button {
                Task {
                    isRunning = true
                    report = nil
                    error = nil
                    report = await runner.runDiagnostics()
                    isRunning = false
                }
            } label: {
                Label(isRunning ? "诊断中…" : "开始诊断", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)
        }
        .padding()
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    // MARK: - Summary Card

    private func summaryCard(report: ActiveDiagnosticsReport) -> some View {
        HStack(spacing: 12) {
            // Passed
            StatPill(count: report.passedCount, label: "通过", color: Theme.success)
            StatPill(count: report.warningCount, label: "警告", color: Theme.warning)
            StatPill(count: report.failedCount, label: "失败", color: Theme.danger)

            Spacer()

            if report.allPassed {
                Label("全部正常", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.success)
            } else if report.hasFailures {
                Label("需要修复", systemImage: "wrench.fill")
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Check Card

    private func checkCard(_ check: DiagnosticCheck) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.status.icon)
                .foregroundStyle(statusColor(check.status))
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(check.name)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.text)

                    Spacer()

                    Text(statusLabel(check.status))
                        .font(.caption)
                        .foregroundStyle(statusColor(check.status))
                }

                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)

                if let suggestion = check.suggestion {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb")
                            .font(.caption2)
                            .foregroundStyle(Theme.warning)
                        Text(suggestion)
                            .font(.caption2)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                    .background(Theme.warning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Helpers

    private func statusColor(_ status: DiagnosticCheck.Status) -> Color {
        switch status {
        case .passed: return Theme.success
        case .warning: return Theme.warning
        case .failed: return Theme.danger
        }
    }

    private func statusLabel(_ status: DiagnosticCheck.Status) -> String {
        switch status {
        case .passed: return "通过"
        case .warning: return "警告"
        case .failed: return "失败"
        }
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.subtext)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
