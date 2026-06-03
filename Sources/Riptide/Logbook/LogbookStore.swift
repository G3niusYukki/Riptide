import Foundation

/// Persistent, append-only diagnostic log store. Writes one JSON object per line
/// to per-UTC-day files under `LogbookPaths.directory`.
///
/// `LogbookStore` is an actor — all file IO is serialized internally. Callers may
/// invoke `append(_:)` from any context; it is safe to use across tasks.
public actor LogbookStore {
    private let paths: LogbookPaths
    private var currentDate: Date?
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
        let data = try Self.encoder.encode(entry)
        try currentHandle?.write(contentsOf: data)
        try currentHandle?.write(contentsOf: Data([0x0A]))  // newline
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
        currentDate = nil
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

    // MARK: - Private

    /// Use the shared Task-2 codec so the on-disk date format is identical to
    /// what other components (and tests) read back. The custom strategy preserves
    /// fractional seconds, which the default `.iso8601` strategy does not.
    private static let encoder: JSONEncoder = JSONEncoder.iso8601

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
        currentDate = date
        currentDateString = dayString
    }
}
