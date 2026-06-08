// ⚠️ SKELETON — DO NOT ENABLE ⚠️
//
// SingBoxRuntimeManager is a v2.4.1 Phase 1 skeleton. The actor
// compiles and is constructable, but `start(...)` throws
// `.notImplemented` — there is no Process spawn, no binary
// download, no health probe. `SingBoxDownloader.resolveLatestStable()`
// returns a `PLACEHOLDER_SHA256` with no integrity check.
//
// The EngineRouter (.reality / .anytls → .singbox) is wired
// defensively: the default policy is `.defaultMihomo`, so the
// router only picks sing-box when a `.reality` or `.anytls` node
// is present. The KernelSwitcherView is status-only — there is no
// user-facing toggle to enable the sing-box engine in v2.4.1.
//
// Phase 2 lands:
//   • real Process spawn gated on `paths.binaryPath` existence
//   • SHA-256 verification of the downloaded binary
//   • stdout/stderr pipes + health probe
//   • throwing init (no synthetic-fallback path)
//
// If `start(...)` is called in v2.4.1, it throws `.notImplemented`
// and `state` stays in `.starting` / `.stopped` — the engine never
// pretends to be running.

import Foundation

public enum SingBoxRuntimeManagerError: Error, Equatable, Sendable {
    case notImplemented
}

public actor SingBoxRuntimeManager {
    public enum State: Sendable, Equatable {
        case stopped
        case starting
        case running(pid: Int32)
        case failed(reason: String)
    }

    public private(set) var state: State = .stopped
    private let paths: SingBoxPaths
    private let api: SingBoxAPIClient

    public init(paths: SingBoxPaths? = nil, api: SingBoxAPIClient? = nil) {
        // The SingBoxPaths.init(fileManager:) is throwing. Construct the
        // default lazily and store it; if construction fails, fall back
        // to a synthetic paths anchored at the user's home directory.
        if let paths {
            self.paths = paths
        } else if let resolved = try? SingBoxPaths() {
            self.paths = resolved
        } else {
            // NOTE: Phase 2 should make this init throwing and remove the
            // synthetic-fallback branch. Silent fallbacks mask real
            // `applicationSupportDirectoryNotFound` errors from CI/dev.
            // Last-resort synthetic path so the manager is still constructable
            // for tests and previews without an Application Support directory.
            let fallback = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Riptide/singbox", isDirectory: true)
            self.paths = SingBoxPaths(baseDirectory: fallback)
        }
        self.api = api ?? SingBoxAPIClient(session: .shared)
    }

    public func start(config _: Data) async throws {
        state = .starting
        try paths.ensureDirectories()
        // Phase 1: process spawn is mocked. The Phase 2 implementation
        // gates the real Process invocation on `paths.binaryPath`
        // existing and SHA-256-verified. Throwing here means a stray
        // call (e.g. from a future UI toggle) fails loudly instead of
        // pretending the engine is running with pid 99999.
        throw SingBoxRuntimeManagerError.notImplemented
    }

    public func stop() async {
        state = .stopped
    }
}
