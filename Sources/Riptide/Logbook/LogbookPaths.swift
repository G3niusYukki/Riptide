import Foundation

/// Resolves on-disk locations for the diagnostic Logbook.
///
/// Files are partitioned by UTC day under `directory` as
/// `YYYY-MM-DD.jsonl` (one JSON object per line).
public struct LogbookPaths: Sendable {
    /// The directory that holds daily `*.jsonl` files.
    public let directory: URL

    /// Creates an instance rooted at the given directory.
    public init(directory: URL) {
        self.directory = directory
    }

    /// The canonical location: `~/Library/Application Support/Riptide/logbook/`.
    public static var `default`: LogbookPaths {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let base = appSupport.appendingPathComponent("Riptide", isDirectory: true)
        return LogbookPaths(directory: base.appendingPathComponent("logbook", isDirectory: true))
    }

    /// Creates the directory if it does not already exist. Safe to call repeatedly.
    public func createDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    /// Returns the JSONL file URL for the UTC day containing `date`.
    public func fileURL(for date: Date) -> URL {
        let name = Self.fileNameFormatter.string(from: date) + ".jsonl"
        return directory.appendingPathComponent(name)
    }

    private static let fileNameFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()
}
