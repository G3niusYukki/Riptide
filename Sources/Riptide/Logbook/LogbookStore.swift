import Foundation

/// Persistent, append-only diagnostic log store. Writes one JSON object per line
/// to per-UTC-day files under `LogbookPaths.directory`.
///
/// `LogbookStore` is an actor — all file IO is serialized internally. Callers may
/// invoke `append(_:)` from any context; it is safe to use across tasks.
public actor LogbookStore {
    private let paths: LogbookPaths
    private var currentHandle: FileHandle?
    private var currentDateString: String = ""

    public init(paths: LogbookPaths = .default) {
        self.paths = paths
    }

    // MARK: - Public

    /// Append a single entry to the file for the entry's date.
    ///
    /// - For `.event`, the file is selected by `LogEvent.timestamp`.
    /// - For `.connectionClosed`, the file is selected by `ClosedConnectionRecord.closedAt`.
    public func append(_ entry: LogbookEntry) throws {
        try ensureHandle(for: dateOf(entry))
        let data = try Self.encoder.encode(entry) + Data([0x0A])
        try currentHandle?.write(contentsOf: data)
    }

    /// Append a batch. Same semantics as repeated `append` but reuses the
    /// `currentHandle` across entries.
    public func appendBatch(_ entries: [LogbookEntry]) throws {
        for entry in entries { try append(entry) }
    }

    /// Force flush + close the current day's file handle. After this call, the
    /// next `append` re-opens the appropriate daily file on demand.
    public func flush() {
        try? currentHandle?.synchronize()
        try? currentHandle?.close()
        currentHandle = nil
        currentDateString = ""
    }

    /// Total size in bytes across all `.jsonl` files in the directory.
    public func totalSize() -> Int64 {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: paths.directory, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return urls.reduce(Int64(0)) { acc, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return acc + Int64(size)
        }
    }

    /// Query entries matching the filter across a date range (inclusive).
    ///
    /// Reads every `.jsonl` file whose UTC day falls within `filter.from..filter.to`,
    /// parses each line as a `LogbookEntry` (silently skipping malformed lines), and
    /// returns up to `filter.limit` entries that pass `matches(_:filter:)`.
    ///
    /// Uses the shared Task-2 `JSONDecoder.iso8601` so timestamps written by `append`
    /// round-trip even with fractional seconds.
    public func query(_ filter: LogbookQuery) throws -> [LogbookEntry] {
        // Ensure the current file's latest bytes are visible to a fresh `Data(contentsOf:)`.
        try? currentHandle?.synchronize()
        let urls = try enumerateDateURLs(from: filter.from, to: filter.to)
        var results: [LogbookEntry] = []
        for url in urls {
            let entries = try readEntries(from: url)
            for entry in entries where matches(entry, filter: filter) {
                results.append(entry)
                if results.count >= filter.limit { return results }
            }
        }
        return results
    }

    /// Delete log files whose UTC day is strictly before `cutoff`'s UTC start-of-day.
    /// Returns the count of files removed. Only files with a `.jsonl` extension that
    /// match the `yyyy-MM-dd` filename convention are considered; anything else is
    /// left untouched so we never accidentally clobber unrelated data.
    public func prune(olderThan cutoff: Date) throws -> Int {
        let cutoffDay = Self.utcCalendar.startOfDay(for: cutoff)
        let urls = try FileManager.default.contentsOfDirectory(
            at: paths.directory, includingPropertiesForKeys: nil
        )
        var removed = 0
        for url in urls where url.pathExtension == "jsonl" {
            let name = url.deletingPathExtension().lastPathComponent
            // Malformed names are left alone — safer than guessing.
            if let fileDay = Self.dayFormatter.date(from: name), fileDay < cutoffDay {
                try? FileManager.default.removeItem(at: url)
                removed += 1
            }
        }
        return removed
    }

    /// Delete every `.jsonl` file in the directory and reset the actor's current
    /// handle state. After this call, the next `append` re-opens a fresh daily file.
    public func purgeAll() throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: paths.directory, includingPropertiesForKeys: nil
        )
        for url in urls where url.pathExtension == "jsonl" {
            try FileManager.default.removeItem(at: url)
        }
        try? currentHandle?.synchronize()
        try? currentHandle?.close()
        currentHandle = nil
        currentDateString = ""
    }

    // MARK: - Private

    /// Use the shared Task-2 codec so the on-disk date format is identical to
    /// what other components (and tests) read back. The custom strategy preserves
    /// fractional seconds, which the default `.iso8601` strategy does not.
    private static let encoder: JSONEncoder = JSONEncoder.iso8601

    /// Read-side decoder. Public from Task 2; shared so writes and reads always
    /// agree on timestamp format (with a fallback chain for non-fractional input).
    private static let decoder: JSONDecoder = JSONDecoder.iso8601

    /// UTC calendar reused for date-range enumeration. Local-time `Calendar` would
    /// put each day's "start of day" in the wrong zone and double-skip some files.
    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private static let dayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt
    }()

    private func dateOf(_ entry: LogbookEntry) -> Date {
        switch entry {
        case .event(let event): return event.timestamp
        case .connectionClosed(let record): return record.closedAt
        }
    }

    private func ensureHandle(for date: Date) throws {
        try paths.createDirectoryIfNeeded()
        let dayString = Self.dayFormatter.string(from: date)
        if dayString == currentDateString, currentHandle != nil { return }
        try? currentHandle?.synchronize()
        try? currentHandle?.close()
        let url = paths.fileURL(for: date)
        let handle: FileHandle
        if FileManager.default.fileExists(atPath: url.path) {
            handle = try FileHandle(forUpdating: url)
            try handle.seekToEnd()
        } else {
            let created = FileManager.default.createFile(atPath: url.path, contents: nil)
            guard created else {
                throw NSError(
                    domain: "LogbookStore", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create \(url.path)"]
                )
            }
            handle = try FileHandle(forUpdating: url)
        }
        currentHandle = handle
        currentDateString = dayString
    }

    /// Enumerate every daily file URL whose UTC day lies in `[from..to]` (inclusive
    /// of both endpoints), in chronological order. Missing days are simply skipped.
    private func enumerateDateURLs(from: Date, to: Date) throws -> [URL] {
        var urls: [URL] = []
        var current = Self.utcCalendar.startOfDay(for: from)
        let end = Self.utcCalendar.startOfDay(for: to)
        while current <= end {
            let url = paths.fileURL(for: current)
            if FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            }
            guard let next = Self.utcCalendar.date(byAdding: .day, value: 1, to: current) else {
                break
            }
            current = next
        }
        return urls
    }

    /// Read every line of a JSONL file and parse each as `LogbookEntry`.
    /// Malformed lines are silently dropped (the read path is lenient by design).
    private func readEntries(from url: URL) throws -> [LogbookEntry] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var entries: [LogbookEntry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8) else { continue }
            if let entry = try? Self.decoder.decode(LogbookEntry.self, from: lineData) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// Apply the user-supplied filter to a parsed entry. Tuple destructuring keeps
    /// the optional `LogLevel?` / `LogbookCategory?` / `host?` shape uniform across
    /// `.event` and `.connectionClosed` variants.
    private func matches(_ entry: LogbookEntry, filter: LogbookQuery) -> Bool {
        let timestamp: Date
        let level: LogLevel?
        let category: LogbookCategory?
        let host: String?
        switch entry {
        case .event(let event):
            timestamp = event.timestamp
            level = event.level
            category = event.category
            host = nil
        case .connectionClosed(let record):
            timestamp = record.closedAt
            level = nil
            category = nil
            host = record.host
        }
        if timestamp < filter.from || timestamp > filter.to { return false }
        if !filter.levels.isEmpty {
            if let entryLevel = level, !filter.levels.contains(entryLevel) { return false }
        }
        if !filter.categories.isEmpty {
            if let entryCategory = category, !filter.categories.contains(entryCategory) { return false }
        }
        // hostContains only applies to .connectionClosed; .event entries pass through (no host to filter).
        if let want = filter.hostContains, let entryHost = host, !entryHost.contains(want) {
            return false
        }
        return true
    }
}
