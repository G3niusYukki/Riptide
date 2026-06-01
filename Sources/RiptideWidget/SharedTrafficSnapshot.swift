import Foundation

/// A point-in-time snapshot of Riptide's traffic statistics.
///
/// The host app writes this snapshot to the App Group shared container on
/// every stats tick. The widget extension reads it from the same container
/// to render a current speed display.
public struct SharedTrafficSnapshot: Codable, Sendable, Equatable {
    public var uploadBytesPerSec: Int64
    public var downloadBytesPerSec: Int64
    public var activeNode: String?
    public var timestamp: Date

    public init(
        uploadBytesPerSec: Int64 = 0,
        downloadBytesPerSec: Int64 = 0,
        activeNode: String? = nil,
        timestamp: Date = .now
    ) {
        self.uploadBytesPerSec = uploadBytesPerSec
        self.downloadBytesPerSec = downloadBytesPerSec
        self.activeNode = activeNode
        self.timestamp = timestamp
    }

    public static let appGroupIdentifier = "group.com.riptide.app"
    private static let fileName = "traffic-snapshot.json"

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Read the latest snapshot from the App Group container.
    ///
    /// Returns an empty snapshot when the container is unavailable (for example
    /// during unit tests, or when the widget extension is not properly
    /// entitled for App Group access) or when the file does not yet exist.
    public static func read() -> SharedTrafficSnapshot {
        guard let url = sharedFileURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(SharedTrafficSnapshot.self, from: data) else {
            return SharedTrafficSnapshot()
        }
        return snapshot
    }

    /// Write the snapshot to the App Group container. Silently no-ops when
    /// the container is unavailable so callers do not have to check.
    public static func write(_ snapshot: SharedTrafficSnapshot) {
        guard let url = sharedFileURL() else { return }
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func sharedFileURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )?.appendingPathComponent(fileName)
    }
}
