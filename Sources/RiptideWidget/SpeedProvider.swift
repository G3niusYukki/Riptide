import Foundation
import WidgetKit

/// A single timeline entry describing a moment of traffic state.
public struct SpeedEntry: TimelineEntry, Sendable {
    public let date: Date
    public let upload: Int64
    public let download: Int64
    public let nodeName: String

    public init(date: Date, upload: Int64, download: Int64, nodeName: String) {
        self.date = date
        self.upload = upload
        self.download = download
        self.nodeName = nodeName
    }
}

/// A timeline provider that reads the latest ``SharedTrafficSnapshot`` from the
/// App Group container and emits a single entry that the widget refreshes
/// after one minute.
public struct SpeedProvider: TimelineProvider, Sendable {
    public typealias Entry = SpeedEntry

    public init() {}

    public func placeholder(in context: Context) -> Entry {
        Self.makeEntry(from: SharedTrafficSnapshot(), at: .now)
    }

    public func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Self.makeEntry(from: SharedTrafficSnapshot.read(), at: .now))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Self.makeEntry(from: SharedTrafficSnapshot.read(), at: .now)
        let nextUpdate = Self.nextRefreshDate(after: entry.date)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    /// Build a timeline entry from a snapshot. Exposed for unit testing —
    /// the WidgetKit `Context` type has no public initializer, so provider
    /// methods cannot be exercised directly from XCTest.
    static func makeEntry(from snapshot: SharedTrafficSnapshot, at date: Date) -> Entry {
        Entry(
            date: date,
            upload: snapshot.uploadBytesPerSec,
            download: snapshot.downloadBytesPerSec,
            nodeName: snapshot.activeNode ?? "—"
        )
    }

    /// Compute the next refresh date — one minute after `date`.
    static func nextRefreshDate(after date: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: 1, to: date)
            ?? date.addingTimeInterval(60)
    }
}
