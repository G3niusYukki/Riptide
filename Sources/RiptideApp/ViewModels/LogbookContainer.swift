import Foundation
import Riptide

/// Holds the three Logbook collaborators (`LogbookStore`, `LogbookWriter`,
/// `LogbookViewModel`) so callers can wire them in one shot.
///
/// `@unchecked Sendable` is safe here: `store` and `writer` are Swift
/// actors (Sendable by construction) and `viewModel` is `@MainActor`
/// isolated, so cross-task access already goes through the actor's
/// executor. The container itself never mutates these references after
/// `init`.
public final class LogbookContainer: @unchecked Sendable {
    public let store: LogbookStore
    public let writer: LogbookWriter
    public let viewModel: LogbookViewModel

    public init(paths: LogbookPaths = .default) {
        let store = LogbookStore(paths: paths)
        let writer = LogbookWriter(store: store)
        self.store = store
        self.writer = writer
        self.viewModel = MainActor.assumeIsolated {
            LogbookViewModel(store: store, writer: writer)
        }
    }

    /// Flush the underlying store's open file handle. Safe to call from
    /// any context (the call hops onto the store's actor).
    public func flush() async {
        await store.flush()
    }
}
