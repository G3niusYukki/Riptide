import Foundation

/// Business facade for writing logbook entries. Fire-and-forget; never throws.
///
/// Callers `await writer.logInfo(...)` from any actor / `Task`; the call is
/// serialized on the `LogbookWriter` actor and forwards to the underlying
/// `LogbookStore.append(_:)`. IO errors are intentionally swallowed via
/// `try? await` — the contract for business modules is that logging never
/// interferes with the main code path.
public actor LogbookWriter {
    private let store: LogbookStore

    public init(store: LogbookStore) {
        self.store = store
    }

    public func logInfo(
        _ message: String,
        category: LogbookCategory,
        context: [String: String] = [:]
    ) async {
        let entry = LogbookEntry.event(LogEvent(
            level: .info, category: category, message: message, context: context
        ))
        try? await store.append(entry)
    }

    public func logWarning(
        _ message: String,
        category: LogbookCategory,
        context: [String: String] = [:]
    ) async {
        let entry = LogbookEntry.event(LogEvent(
            level: .warning, category: category, message: message, context: context
        ))
        try? await store.append(entry)
    }

    public func logError(
        _ message: String,
        category: LogbookCategory,
        context: [String: String] = [:]
    ) async {
        let entry = LogbookEntry.event(LogEvent(
            level: .error, category: category, message: message, context: context
        ))
        try? await store.append(entry)
    }

    public func recordConnectionClosed(_ record: ClosedConnectionRecord) async {
        try? await store.append(.connectionClosed(record))
    }
}
