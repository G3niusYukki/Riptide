import Foundation
import WidgetKit
import XCTest
@testable import RiptideWidget

final class SharedTrafficSnapshotTests: XCTestCase {
    func testEmptyDefaults() {
        let snapshot = SharedTrafficSnapshot()
        XCTAssertEqual(snapshot.uploadBytesPerSec, 0)
        XCTAssertEqual(snapshot.downloadBytesPerSec, 0)
        XCTAssertNil(snapshot.activeNode)
    }

    func testRoundTripCodable() throws {
        let original = SharedTrafficSnapshot(
            uploadBytesPerSec: 1_234_567,
            downloadBytesPerSec: 987_654,
            activeNode: "Hong Kong – 01",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SharedTrafficSnapshot.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testReadWithoutContainerReturnsEmpty() {
        let snapshot = SharedTrafficSnapshot.read()
        // The container is unavailable in the test environment, so we expect
        // a zeroed snapshot. The timestamp is generated at read time, so we
        // only assert on the fields that carry the "empty" semantic.
        XCTAssertEqual(snapshot.uploadBytesPerSec, 0)
        XCTAssertEqual(snapshot.downloadBytesPerSec, 0)
        XCTAssertNil(snapshot.activeNode)
    }

    func testWriteWithoutContainerIsNoOp() {
        // Should not crash even when no App Group is configured.
        SharedTrafficSnapshot.write(
            SharedTrafficSnapshot(uploadBytesPerSec: 100, downloadBytesPerSec: 200)
        )
    }
}

final class SpeedProviderTests: XCTestCase {
    func testMakeEntryFromEmptySnapshotUsesPlaceholder() {
        let entry = SpeedProvider.makeEntry(from: SharedTrafficSnapshot(), at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(entry.upload, 0)
        XCTAssertEqual(entry.download, 0)
        XCTAssertEqual(entry.nodeName, "—")
        XCTAssertEqual(entry.date, Date(timeIntervalSince1970: 0))
    }

    func testMakeEntryPropagatesValues() {
        let snapshot = SharedTrafficSnapshot(
            uploadBytesPerSec: 1_024,
            downloadBytesPerSec: 4_096,
            activeNode: "Tokyo – 02"
        )
        let entry = SpeedProvider.makeEntry(from: snapshot, at: .now)
        XCTAssertEqual(entry.upload, 1_024)
        XCTAssertEqual(entry.download, 4_096)
        XCTAssertEqual(entry.nodeName, "Tokyo – 02")
    }

    func testNextRefreshDateIsOneMinuteLater() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let next = SpeedProvider.nextRefreshDate(after: base)
        XCTAssertEqual(next.timeIntervalSince(base), 60, accuracy: 0.5)
    }
}

final class SpeedWidgetViewFormattingTests: XCTestCase {
    func testBytesFormatting() {
        XCTAssertEqual(SpeedWidgetView.formatBytes(0), "0 B/s")
        XCTAssertEqual(SpeedWidgetView.formatBytes(512), "512 B/s")
        XCTAssertEqual(SpeedWidgetView.formatBytes(1_500), "1.5 KB/s")
        XCTAssertEqual(SpeedWidgetView.formatBytes(1_500_000), "1.4 MB/s")
    }
}
