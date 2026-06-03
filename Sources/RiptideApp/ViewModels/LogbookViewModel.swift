import Foundation
import Combine
import Riptide

/// UI-facing view model for the Logbook (Diagnostics) tab.
///
/// Reads/writes are mediated by `LogbookStore` and `LogbookWriter`. The
/// view model is `@MainActor` and `ObservableObject` so SwiftUI can drive
/// re-renders directly from its `@Published` filter properties.
@MainActor
public final class LogbookViewModel: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var entries: [LogbookEntry] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var totalSize: Int64 = 0
    @Published public var filterLevel: Riptide.LogLevel?
    @Published public var filterCategory: LogbookCategory?
    @Published public var dateRange: DateRange = .last24h

    // MARK: - Date Range

    public enum DateRange: String, CaseIterable, Identifiable {
        case last24h = "24h"
        case last7d = "7d"
        case last30d = "30d"

        public var id: String { rawValue }
    }

    // MARK: - Dependencies

    private let store: LogbookStore
    private let writer: LogbookWriter
    private var loadTask: Task<Void, Never>?

    // MARK: - Init

    public init(store: LogbookStore, writer: LogbookWriter) {
        self.store = store
        self.writer = writer
    }

    // MARK: - Public API

    /// Kick off (or restart) a load. The prior task is cancelled so rapid
    /// filter changes do not race each other.
    public func load() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.performLoad()
        }
    }

    /// Alias for `load()` — kept for call-site clarity when a filter has
    /// changed and the UI wants to re-query.
    public func applyFilter() {
        load()
    }

    /// Delete every entry on disk and reset local state.
    public func clear() async {
        try? await store.purgeAll()
        entries = []
        totalSize = 0
    }

    /// Write the currently displayed entries to `url` as JSONL using the
    /// shared `JSONEncoder.iso8601` codec (defined in Task 2).
    public func export(to url: URL) throws {
        var text = ""
        let encoder = JSONEncoder.iso8601
        for entry in entries {
            let data = try encoder.encode(entry)
            text += (String(data: data, encoding: .utf8) ?? "") + "\n"
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private func performLoad() async {
        isLoading = true
        defer { if !Task.isCancelled { isLoading = false } }

        let baseQuery: LogbookQuery
        switch dateRange {
        case .last24h:
            baseQuery = .last24h()
        case .last7d:
            baseQuery = .last7d()
        case .last30d:
            baseQuery = LogbookQuery(
                from: Date().addingTimeInterval(-30 * 24 * 3600),
                to: Date(),
                limit: 5000
            )
        }

        var query = baseQuery
        if let level = filterLevel { query.levels = [level] }
        if let category = filterCategory { query.categories = [category] }

        guard !Task.isCancelled else { return }
        let results = (try? await store.query(query)) ?? []
        guard !Task.isCancelled else { return }
        let size = await store.totalSize()
        guard !Task.isCancelled else { return }

        self.entries = results
        self.totalSize = size
    }
}
