import Foundation

public actor SingBoxRuntimeManager {
    public enum State: Sendable, Equatable {
        case stopped
        case starting
        case running(pid: Int32)
        case failed(reason: String)
    }

    private(set) public var state: State = .stopped
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
            // FIXME: Phase 2 should make this init throwing and remove the
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
        // Ensure on-disk directories exist before we hand the config to
        // the (future) process spawn.
        try paths.ensureDirectories()
        // Phase 1: process spawn is mocked (skeleton). Phase 2 lands the
        // real Process invocation gated behind `.running` of the real
        // binary at `paths.binaryPath`.
        // Phase 1 sentinel: 99999 is intentionally not a real PID. Phase 2 will
        // populate this with the actual Process pid. Do NOT match on `99999` in
        // production code — use `case .running(pid:)` without binding to a value.
        state = .running(pid: 99999)
    }

    public func stop() async {
        state = .stopped
    }
}
