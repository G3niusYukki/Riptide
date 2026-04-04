import SwiftUI
import Riptide

// MARK: - Log Stream View

public struct LogStreamView: View {
    @State private var viewModel: LogViewModel
    @State private var selectedLevel: LogLevel = .debug
    @State private var autoScroll = true
    @State private var searchText = ""
    @State private var showExportSheet = false

    public init(viewModel: LogViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Level Filter
                Picker("Level", selection: $selectedLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .onChange(of: selectedLevel) { _, newValue in
                    Task {
                        await viewModel.setMinLevel(newValue)
                    }
                }

                Spacer()

                // Search
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)

                // Auto Scroll Toggle
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .onChange(of: autoScroll) { _, newValue in
                        if newValue {
                            Task {
                                await viewModel.toggleAutoScroll()
                            }
                        }
                    }

                // Clear Button
                Button("Clear") {
                    Task {
                        await viewModel.clear()
                    }
                }
                .buttonStyle(.bordered)

                // Export Button
                Button("Export") {
                    showExportSheet = true
                }
                .buttonStyle(.bordered)
            }
            .padding()

            // Log Entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.filteredEntries) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: viewModel.filteredEntries.count) { _, _ in
                    if autoScroll, let last = viewModel.filteredEntries.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Status Bar
            HStack {
                Text("\(viewModel.entryCount()) entries (\(viewModel.filteredCount()) shown)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let error = viewModel.lastError {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .task {
            await viewModel.startPolling(interval: 1.0)
        }
        .onDisappear {
            Task {
                await viewModel.stopPolling()
            }
        }
        .sheet(isPresented: $showExportSheet) {
            LogExportSheet(logs: viewModel.exportLogs())
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Level Indicator
            Circle()
                .fill(levelColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                // Timestamp and Level
                HStack {
                    Text(formatTime(entry.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(entry.level.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(levelColor)
                }

                // Message
                Text(entry.message)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
        .background(levelColor.opacity(0.05))
    }

    private var levelColor: Color {
        switch entry.level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

// MARK: - Log Export Sheet

struct LogExportSheet: View {
    let logs: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: .constant(logs))
                    .font(.system(.body, design: .monospaced))
                    .padding()

                HStack {
                    Button("Copy to Clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(logs, forType: .string)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Save to File") {
                        saveToFile()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("Export Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveToFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "riptide-logs.txt"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? logs.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
