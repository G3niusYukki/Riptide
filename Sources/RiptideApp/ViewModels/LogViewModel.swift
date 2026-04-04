import Foundation
import Riptide

// MARK: - Log ViewModel

/// Actor-based view model for log streaming
public actor LogViewModel {
    // MARK: - State
    private(set) var entries: [LogEntry] = []
    private(set) var filteredEntries: [LogEntry] = []
    private(set) var minLevel: LogLevel = .debug
    private(set) var isAutoScrolling: Bool = true
    private(set) var lastError: Error?

    // MARK: - Configuration
    public let maxEntries = 1000
    private var refreshTask: Task<Void, Never>?
    private var isPolling = false

    // MARK: - Dependencies
    private let apiClient: LogProvider?
    private let parser = LogEntryParser()

    // MARK: - Initialization
    public init(apiClient: LogProvider? = nil) {
        self.apiClient = apiClient
    }

    // MARK: - Entry Management
    public func addLogEntry(_ entry: LogEntry) {
        entries.append(entry)

        // Limit total entries
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        // Update filtered entries if level matches
        if entry.level >= minLevel {
            filteredEntries.append(entry)
            if filteredEntries.count > maxEntries {
                filteredEntries.removeFirst(filteredEntries.count - maxEntries)
            }
        }
    }

    public func addLogLine(_ line: String) {
        let entry = parser.parse(line)
        addLogEntry(entry)
    }

    public func addLogLines(_ lines: [String]) {
        for line in lines {
            addLogLine(line)
        }
    }

    // MARK: - Filtering
    public func setMinLevel(_ level: LogLevel) {
        minLevel = level
        applyFilter()
    }

    private func applyFilter() {
        filteredEntries = entries.filter { $0.level >= minLevel }
    }

    // MARK: - API Integration
    public func fetchLogs(level: String? = nil, lines: Int = 100) async {
        guard let apiClient = apiClient else {
            lastError = LogError.noAPIClient
            return
        }

        let levelString = level ?? minLevel.displayName.lowercased()

        do {
            let lines = try await apiClient.getLogs(level: levelString, lines: lines)
            addLogLines(lines)
            lastError = nil
        } catch {
            lastError = error
        }
    }

    // MARK: - Polling
    public func startPolling(interval: TimeInterval = 1.0) {
        stopPolling()
        isPolling = true

        refreshTask = Task {
            while isPolling && !Task.isCancelled {
                await fetchLogs()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stopPolling() {
        isPolling = false
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Control
    public func clear() {
        entries.removeAll()
        filteredEntries.removeAll()
    }

    public func toggleAutoScroll() {
        isAutoScrolling.toggle()
    }

    public func exportLogs() -> String {
        let formatter = LogFormatter()
        return entries.map { formatter.formatFull($0) }.joined(separator: "\n")
    }

    // MARK: - Queries
    public func entryCount() -> Int {
        entries.count
    }

    public func filteredCount() -> Int {
        filteredEntries.count
    }

    public func latestEntry() -> LogEntry? {
        entries.last
    }

    public func entries(atLevel level: LogLevel) -> [LogEntry] {
        entries.filter { $0.level == level }
    }
}

// MARK: - Log Error

public enum LogError: Error, Equatable, Sendable {
    case noAPIClient
    case networkError(String)
    case invalidResponse
}
