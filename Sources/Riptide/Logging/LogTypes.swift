import Foundation

// MARK: - Log Level

/// Log severity levels, ordered from least to most severe
public enum LogLevel: Int, Equatable, Sendable, Comparable, CaseIterable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Display name for the log level
    public var displayName: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }

    /// Parse a log level from a string
    public static func from(string: String) -> LogLevel? {
        let lowercased = string.lowercased()
        switch lowercased {
        case "debug": return .debug
        case "info": return .info
        case "warning", "warn": return .warning
        case "error": return .error
        default: return nil
        }
    }
}

// MARK: - Log Entry

/// A single log entry with metadata
public struct LogEntry: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

// MARK: - Log Entry Parser

/// Parser for log entries from various formats
public struct LogEntryParser {

    public init() {}

    /// Parses a log line into a LogEntry
    /// - Parameter line: The log line to parse
    /// - Returns: A LogEntry with extracted level and message
    public func parse(_ line: String) -> LogEntry {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract log level from [LEVEL] format
        let levelPattern = #"\[(DEBUG|INFO|WARNING|WARN|ERROR)\]"#
        let regex = try? NSRegularExpression(pattern: levelPattern, options: [.caseInsensitive])
        let range = NSRange(location: 0, length: trimmed.utf16.count)

        if let match = regex?.firstMatch(in: trimmed, options: [], range: range) {
            let levelRange = match.range(at: 1)
            if let swiftRange = Range(levelRange, in: trimmed) {
                let levelString = String(trimmed[swiftRange]).lowercased()
                let level = LogLevel.from(string: levelString) ?? .info

                // Extract message (everything after the level tag)
                let levelTagEnd = match.range.upperBound
                if levelTagEnd < trimmed.utf16.count {
                    let messageRange = NSRange(location: levelTagEnd, length: trimmed.utf16.count - levelTagEnd)
                    if let swiftMessageRange = Range(messageRange, in: trimmed) {
                        let message = String(trimmed[swiftMessageRange])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return LogEntry(level: level, message: message)
                    }
                }

                return LogEntry(level: level, message: trimmed)
            }
        }

        // No level found, default to info
        return LogEntry(level: .info, message: trimmed)
    }
}

// MARK: - Log Formatter

/// Formats log entries for display
public struct LogFormatter {
    private let dateFormatter: DateFormatter

    public init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    /// Formats a log entry for display
    public func format(_ entry: LogEntry) -> String {
        let timeString = dateFormatter.string(from: entry.timestamp)
        return "[\(timeString)] [\(entry.level.displayName)] \(entry.message)"
    }

    /// Formats a log entry with full date for file export
    public func formatFull(_ entry: LogEntry) -> String {
        let fullFormatter = DateFormatter()
        fullFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timeString = fullFormatter.string(from: entry.timestamp)
        return "[\(timeString)] [\(entry.level.displayName)] \(entry.message)"
    }
}
