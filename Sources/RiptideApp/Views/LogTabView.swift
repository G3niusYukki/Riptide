import SwiftUI

struct LogTabView: View {
    @Bindable var vm: AppViewModel
    @State private var searchText = ""
    @State private var selectedLevel: LogLevel? = nil

    private var effectiveLevel: LogLevel? {
        selectedLevel == nil ? nil : (selectedLevel == .all ? nil : selectedLevel)
    }

    private var filteredLogs: [LogEntry] {
        vm.logEntries.filter { entry in
            let matchesLevel = effectiveLevel == nil || entry.level == effectiveLevel
            let matchesSearch = searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesSearch
        }
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .info: return Theme.accent
        case .warn: return Color.yellow
        case .error: return Theme.danger
        case .all: return Theme.subtext
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filters
            HStack {
                Picker("级别", selection: $selectedLevel) {
                    Text("全部").tag(LogLevel?.none)
                    ForEach([LogLevel.info, .warn, .error], id: \.self) { level in
                        Text(level.rawValue.uppercased()).tag(Optional(level))
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
                                    Text("[\(entry.level.rawValue.uppercased())]")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(levelColor(entry.level))
                                        .frame(width: 50, alignment: .leading)
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
