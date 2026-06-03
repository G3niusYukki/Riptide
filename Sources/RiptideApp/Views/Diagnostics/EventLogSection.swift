import SwiftUI
import Riptide
import AppKit

struct EventLogSection: View {
    @Bindable var vm: AppViewModel
    @ObservedObject private var logbookVM: LogbookViewModel
    @State private var saveError: String?

    init(vm: AppViewModel) {
        self.vm = vm
        self._logbookVM = ObservedObject(wrappedValue: vm.logbook.viewModel)
    }

    private var filtered: [LogbookEntry] {
        logbookVM.entries
    }

    var body: some View {
        VStack(spacing: 8) {
            // Filter bar
            HStack {
                levelPicker
                categoryPicker
                rangePicker

                Spacer()

                Button("导出") { exportEntries() }
                    .accessibilityIdentifier(A11yID.Diagnostics.exportButton)

                Button("清空") {
                    Task { await logbookVM.clear() }
                }
                .accessibilityIdentifier(A11yID.Diagnostics.clearButton)
            }
            .padding(.horizontal)

            if filtered.isEmpty {
                Text("暂无事件")
                    .foregroundStyle(Theme.subtext)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(filtered.enumerated()), id: \.offset) { _, entry in
                            EventRow(entry: entry)
                        }
                    }
                    .padding()
                }
                .accessibilityIdentifier(A11yID.Diagnostics.eventList)
            }
        }
        .onAppear { logbookVM.load() }
        .onChange(of: logbookVM.filterLevel) { _, _ in
            logbookVM.applyFilter()
        }
        .onChange(of: logbookVM.filterCategory) { _, _ in
            logbookVM.applyFilter()
        }
        .onChange(of: logbookVM.dateRange) { _, _ in
            logbookVM.applyFilter()
        }
    }

    private var levelPicker: some View {
        Picker("level", selection: $logbookVM.filterLevel) {
            Text("全部").tag(Riptide.LogLevel?.none)
            ForEach([Riptide.LogLevel.debug, .info, .warning, .error], id: \.self) { lvl in
                Text(lvl.displayName).tag(Optional(lvl))
            }
        }
        .pickerStyle(.menu)
        .frame(width: 110)
    }

    private var categoryPicker: some View {
        Picker("category", selection: $logbookVM.filterCategory) {
            Text("全部").tag(LogbookCategory?.none)
            ForEach(LogbookCategory.allCases, id: \.self) { cat in
                Text(cat.rawValue).tag(Optional(cat))
            }
        }
        .pickerStyle(.menu)
        .frame(width: 140)
    }

    private var rangePicker: some View {
        Picker("range", selection: $logbookVM.dateRange) {
            ForEach(LogbookViewModel.DateRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
    }

    private func exportEntries() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "riptide-logbook.jsonl"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try logbookVM.export(to: url)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct EventRow: View {
    let entry: LogbookEntry

    private var event: LogEvent? {
        if case .event(let innerEvent) = entry { return innerEvent } else { return nil }
    }

    var body: some View {
        if let innerEvent = event {
            HStack(alignment: .top, spacing: 8) {
                Text("[\(innerEvent.level.displayName)]")
                    .font(.caption.monospaced())
                    .foregroundStyle(color(for: innerEvent.level))
                    .frame(width: 70, alignment: .leading)
                Text(innerEvent.timestamp, style: .time)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.subtext)
                Text(innerEvent.category.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.accent)
                Text(innerEvent.message)
                    .font(.caption)
                    .foregroundStyle(Theme.text)
            }
        }
    }

    private func color(for level: Riptide.LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return Theme.accent
        case .warning: return .yellow
        case .error: return Theme.danger
        }
    }
}
