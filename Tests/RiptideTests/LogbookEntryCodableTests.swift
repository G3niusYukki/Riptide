import Foundation
import Testing

@testable import Riptide

@Suite("Logbook entry codable")
struct LogbookEntryCodableTests {

    @Test("event round-trips through JSON")
    func eventRoundTrips() throws {
        let entry = LogbookEntry.event(LogEvent(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            level: .warning,
            category: .mihomoCore,
            message: "spawn failed",
            context: ["exit": "1"]
        ))
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(LogbookEntry.self, from: data)
        #expect(decoded == entry)
    }

    @Test("connectionClosed round-trips through JSON")
    func connectionClosedRoundTrips() throws {
        let record = ClosedConnectionRecord(
            id: "abc-123",
            host: "example.com",
            proxyName: "US-HK-01",
            protocol: "tcp",
            rule: "MATCH",
            sourceIP: "192.0.2.1",
            sourcePort: 54321,
            destinationIP: "203.0.113.5",
            destinationPort: 443,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            closedAt: Date(timeIntervalSince1970: 1_700_000_010),
            uploadBytes: 1024,
            downloadBytes: 2048,
            closeReason: .userClosed
        )
        let entry = LogbookEntry.connectionClosed(record)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(LogbookEntry.self, from: data)
        #expect(decoded == entry)
    }

    @Test("empty context encodes as empty object")
    func emptyContext() throws {
        let entry = LogbookEntry.event(LogEvent(
            id: UUID(),
            timestamp: Date(),
            level: .info,
            category: .appLifecycle,
            message: "x",
            context: [:]
        ))
        let data = try JSONEncoder().encode(entry)
        let s = String(data: data, encoding: .utf8)!
        #expect(s.contains("\"context\":{}"))
    }

    @Test("date precision is milliseconds in ISO 8601")
    func datePrecision() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)
        let entry = LogbookEntry.event(LogEvent(
            id: UUID(),
            timestamp: date,
            level: .info,
            category: .appLifecycle,
            message: "x",
            context: [:]
        ))
        let data = try JSONEncoder.iso8601.encode(entry)
        let s = String(data: data, encoding: .utf8)!
        // ISO 8601 with fractional seconds: ...20.123Z
        #expect(s.contains(".123Z"))
    }

    @Test("query factory helpers produce correct windows")
    func queryHelpers() {
        let last24 = LogbookQuery.last24h()
        let now = Date()
        #expect(last24.to.timeIntervalSince(now) < 5)
        #expect(last24.to.timeIntervalSince(last24.from) > 23 * 3600)

        let last7 = LogbookQuery.last7d(limit: 500)
        #expect(last7.limit == 500)
        #expect(last7.to.timeIntervalSince(last7.from) > 6 * 24 * 3600)
    }
}
