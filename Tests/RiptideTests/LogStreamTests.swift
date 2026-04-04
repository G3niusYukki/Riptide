import Foundation
import Testing
@testable import Riptide

// MARK: - Log Stream Tests

@Suite("Log Stream")
struct LogStreamTests {

    @Test("parses log entry with level")
    func testParsesLogEntryWithLevel() throws {
        let parser = LogEntryParser()

        let entry = try parser.parse("2024-01-15 10:30:45 [INFO] Starting mihomo...")

        #expect(entry.level == .info)
        #expect(entry.message.contains("Starting mihomo"))
    }

    @Test("parses log entry with debug level")
    func testParsesDebugLogEntry() throws {
        let parser = LogEntryParser()

        let entry = try parser.parse("2024-01-15 10:30:45 [DEBUG] Verbose logging enabled")

        #expect(entry.level == .debug)
        #expect(entry.message.contains("Verbose logging"))
    }

    @Test("parses log entry with warning level")
    func testParsesWarningLogEntry() throws {
        let parser = LogEntryParser()

        let entry = try parser.parse("2024-01-15 10:30:45 [WARNING] Connection timeout")

        #expect(entry.level == .warning)
    }

    @Test("parses log entry with error level")
    func testParsesErrorLogEntry() throws {
        let parser = LogEntryParser()

        let entry = try parser.parse("2024-01-15 10:30:45 [ERROR] Failed to start proxy")

        #expect(entry.level == .error)
    }

    @Test("handles log entry without level")
    func testHandlesLogEntryWithoutLevel() throws {
        let parser = LogEntryParser()

        let entry = try parser.parse("Some plain log message")

        #expect(entry.level == .info)
        #expect(entry.message == "Some plain log message")
    }

    @Test("filters by log level")
    func testFiltersByLogLevel() throws {
        let entries = [
            LogEntry(timestamp: Date(), level: .debug, message: "Debug message"),
            LogEntry(timestamp: Date(), level: .info, message: "Info message"),
            LogEntry(timestamp: Date(), level: .warning, message: "Warning message"),
            LogEntry(timestamp: Date(), level: .error, message: "Error message")
        ]

        let filtered = entries.filter { $0.level >= .warning }

        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.level == .warning || $0.level == .error })
    }

    @Test("log level comparison works correctly")
    func testLogLevelComparison() {
        #expect(LogLevel.debug < LogLevel.info)
        #expect(LogLevel.info < LogLevel.warning)
        #expect(LogLevel.warning < LogLevel.error)

        #expect(LogLevel.error > LogLevel.warning)
        #expect(LogLevel.warning > LogLevel.info)
        #expect(LogLevel.info > LogLevel.debug)
    }

    @Test("parses log level string correctly")
    func testParsesLogLevelString() {
        #expect(LogLevel.from(string: "debug") == .debug)
        #expect(LogLevel.from(string: "DEBUG") == .debug)
        #expect(LogLevel.from(string: "info") == .info)
        #expect(LogLevel.from(string: "INFO") == .info)
        #expect(LogLevel.from(string: "warning") == .warning)
        #expect(LogLevel.from(string: "warn") == .warning)
        #expect(LogLevel.from(string: "error") == .error)
        #expect(LogLevel.from(string: "invalid") == nil)
    }
}

// MARK: - Log Entry Tests

@Suite("Log Entry")
struct LogEntryTests {

    @Test("is equatable")
    func testIsEquatable() {
        let date = Date()
        let id = UUID()
        let entry1 = LogEntry(id: id, timestamp: date, level: .info, message: "Test")
        let entry2 = LogEntry(id: id, timestamp: date, level: .info, message: "Test")
        let entry3 = LogEntry(id: UUID(), timestamp: date, level: .error, message: "Test")

        #expect(entry1 == entry2)
        #expect(entry1 != entry3)
    }

    @Test("is sendable")
    func testIsSendable() {
        let entry = LogEntry(timestamp: Date(), level: .info, message: "Test")
        // Compile-time check that LogEntry is Sendable
        Task {
            let _: LogEntry = entry
        }
    }
}

// MARK: - Mihomo Log Client Tests

@Suite("Mihomo Log Client")
struct MihomoLogClientTests {

    @Test("constructs correct log URL")
    func testConstructsCorrectLogURL() async throws {
        let baseURL = URL(string: "http://127.0.0.1:9090")!
        let client = MihomoLogClient(baseURL: baseURL)

        let url = await client.logURL(level: "info", lines: 100)

        #expect(url.absoluteString.contains("/logs"))
        #expect(url.absoluteString.contains("level=info"))
        #expect(url.absoluteString.contains("lines=100"))
    }
}

