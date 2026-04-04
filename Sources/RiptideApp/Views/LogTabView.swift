import SwiftUI
import Riptide

struct LogTabView: View {
    @Bindable var vm: AppViewModel
    @State private var searchText = ""
    @State private var selectedLevel: Riptide.LogLevel? = nil

    private var effectiveLevel: Riptide.LogLevel? {
        selectedLevel
    }

    private var filteredLogs: [Riptide.LogEntry] {
        vm.logEntries.filter { entry in
            let matchesLevel = effectiveLevel == nil || entry.level.rawValue >= (effectiveLevel?.rawValue ?? 0)
            let matchesSearch = searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSearch
        }
    }

    private func levelColor(_ level: Riptide.LogLevel) -> Color {
        switch level {
        case .debug: return Color.gray
        case .info: return Theme.accent
        case .warning: return Color.yellow
        case .error: return Theme.danger
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filters
            HStack {
                Picker("级别", selection: $selectedLevel) {
                    Text("全部").tag(Riptide.LogLevel?.none)
                    ForEach([Riptide.LogLevel.debug, .info, .warning, .error], id: \.self) { level in
                        Text(level.displayName).tag(Optional(level))
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Spacer()

                Button("清空") {
                    // Clear logs — stub: add clear method to AppViewModel if needed
                }

                Button("导出") {
                    // Export logs — stub
                }
            }
            .padding()
            .background(Theme.background)

            // Log list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if filteredLogs.isEmpty {
                            Text("暂无日志")
                                .foregroundStyle(Theme.subtext)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(filteredLogs) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("[\(entry.level.displayName)]")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(levelColor(entry.level))
                                        .frame(width: 70, alignment: .leading)
                                    Text(entry.timestamp, style: .time)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(Theme.subtext)
                                    Text(entry.message)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(Theme.text)
                                }
                                .id(entry.id)
                            }
                        }
                    }
                    .padding()
                }
                .background(Theme.background)
                .onChange(of: filteredLogs.count) { _, _ in
                    if let last = filteredLogs.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索日志")
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
