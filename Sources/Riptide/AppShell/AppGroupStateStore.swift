import Foundation

/// Errors from app group state store operations.
public enum AppGroupStateStoreError: Error, Equatable, Sendable {
    case encodingFailed
    case decodingFailed(String)
    case writeFailed(String)
}

/// A store for sharing runtime state between the host app and the packet-tunnel
/// extension via the app group shared container.
public actor AppGroupStateStore {
    private let fileURL: URL
    private var cached: RuntimeSharedState?

    public init(appGroupIdentifier: String = "group.com.riptide.app") throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            // Fallback to application support when app group is unavailable (e.g. tests)
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            let dir = appSupport.appendingPathComponent("Riptide", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("shared-state.json")
            return
        }
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        self.fileURL = containerURL.appendingPathComponent("runtime-state.json")
    }

    /// Write the current shared state snapshot.
    public func write(_ state: RuntimeSharedState) throws {
        cached = state
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw AppGroupStateStoreError.writeFailed(String(describing: error))
        }
    }

    /// Read the latest shared state, using cache if available.
    public func read() throws -> RuntimeSharedState? {
        if let cached {
            return cached
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try JSONDecoder().decode(RuntimeSharedState.self, from: data)
            cached = state
            return state
        } catch {
            throw AppGroupStateStoreError.decodingFailed(String(describing: error))
        }
    }

    /// Update specific fields and persist.
    public func update(
        status: TunnelRuntimeStatus? = nil,
        mode: RuntimeMode? = nil,
        recentErrors: [RuntimeErrorSnapshot]? = nil
    ) throws {
        var current = try read() ?? RuntimeSharedState(
            status: TunnelRuntimeStatus(),
            mode: .systemProxy,
            recentErrors: []
        )
        if let status { current.status = status }
        if let mode { current.mode = mode }
        if let recentErrors { current.recentErrors = recentErrors }
        try write(current)
    }

    /// Clear the cached state.
    public func clearCache() {
        cached = nil
    }
}

/// The runtime state shared between the host app and the tunnel extension.
public struct RuntimeSharedState: Sendable, Codable, Equatable {
    public var status: TunnelRuntimeStatus
    public var mode: RuntimeMode
    public var recentErrors: [RuntimeErrorSnapshot]

    public init(
        status: TunnelRuntimeStatus = TunnelRuntimeStatus(),
        mode: RuntimeMode = .systemProxy,
        recentErrors: [RuntimeErrorSnapshot] = []
    ) {
        self.status = status
        self.mode = mode
        self.recentErrors = recentErrors
    }
}
