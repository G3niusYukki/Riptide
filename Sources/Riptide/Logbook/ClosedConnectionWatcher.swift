import Foundation

/// Abstract source of "current connections" for the watcher.
///
/// Implementations are expected to be backed by a live snapshot of the
/// proxy core's connection list (e.g. the mihomo REST API). Each call to
/// `currentConnections()` should reflect the state at the moment it is
/// invoked; the watcher diffs successive snapshots.
public protocol ConnectionProvider: Sendable {
    func currentConnections() async -> [ConnectionInfo]
}

/// Detects connections that disappeared between two ticks and records them
/// as `ClosedConnectionRecord` entries through the `LogbookWriter`.
///
/// The runtime loop (a timer or task that drives `tick()` periodically)
/// is out of scope for W3-2a and will be wired in W3-2b. This actor
/// exposes the diff algorithm so it can be tested in isolation and so
/// future driver code can `await watcher.tick()` from any context.
///
/// Algorithm:
/// 1. Fetch the current connection list from `provider`.
/// 2. If we have a prior snapshot (`hasSeed`), the closed IDs are the
///    set difference `snapshot.keys \ current.keys`.
/// 3. For each closed ID, build a `ClosedConnectionRecord` from the
///    last-seen `ConnectionInfo` and forward it to the writer.
/// 4. Replace the snapshot with the current set and seed for next time.
public actor ClosedConnectionWatcher {
    private let provider: ConnectionProvider
    private let writer: LogbookWriter
    private var snapshot: [String: ConnectionInfo] = [:]
    private var hasSeed: Bool = false
    /// Test-only override; when set, the next `tick()` returns this list
    /// (and clears the override) instead of calling the provider.
    private var testOverride: [ConnectionInfo]?

    public init(provider: ConnectionProvider, writer: LogbookWriter) {
        self.provider = provider
        self.writer = writer
    }

    /// One step: fetch current connections, diff vs prior snapshot,
    /// record any closures, then update the snapshot.
    public func tick() async {
        let current: [ConnectionInfo]
        if let override = testOverride {
            current = override
            testOverride = nil
        } else {
            current = await provider.currentConnections()
        }

        var next: [String: ConnectionInfo] = [:]
        for conn in current {
            next[conn.id] = conn
        }

        if hasSeed {
            let closedIds = Set(snapshot.keys).subtracting(next.keys)
            for closedId in closedIds {
                guard let conn = snapshot[closedId] else { continue }
                await writer.recordConnectionClosed(makeRecord(from: conn))
            }
        }

        snapshot = next
        hasSeed = true
    }

    /// Test-only backdoor. Sets the connection list the **next** `tick()`
    /// should observe, bypassing `provider.currentConnections()`.
    /// Not intended for production use.
    public func setConnectionsForTest(_ conns: [ConnectionInfo]) async {
        testOverride = conns
    }

    // MARK: - Record construction

    private func makeRecord(from conn: ConnectionInfo) -> ClosedConnectionRecord {
        let meta = conn.metadata
        return ClosedConnectionRecord(
            id: conn.id,
            host: meta.host ?? "",
            proxyName: conn.chains.first ?? "Direct",
            protocol: meta.type,
            rule: conn.rule,
            sourceIP: meta.sourceIP,
            sourcePort: meta.sourcePort.flatMap { Int($0) },
            destinationIP: meta.destinationIP,
            destinationPort: meta.destinationPort.flatMap { Int($0) },
            startedAt: parseStart(conn.start) ?? Date(),
            closedAt: Date(),
            uploadBytes: conn.upload,
            downloadBytes: conn.download,
            closeReason: .idleTimeout
        )
    }

    private func parseStart(_ start: String?) -> Date? {
        guard let start else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: start) ?? ISO8601DateFormatter().date(from: start)
    }
}
