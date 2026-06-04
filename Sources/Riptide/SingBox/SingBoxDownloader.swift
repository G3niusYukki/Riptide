import Foundation

public actor SingBoxDownloader {
    public struct ReleaseInfo: Sendable, Equatable {
        public let tag: String
        public let downloadURL: URL
        public let sha256: String
    }

    public init() {}

    /// Resolves the latest stable sing-box release metadata.
    ///
    /// Phase 1 (this skeleton) returns a hard-coded `v1.13.0` reference
    /// so the actor is constructable and testable without network I/O.
    /// The version matches the pin in `Scripts/download-singbox.sh`
    /// (line 7: `VERSION="1.13.0"`) — keep them in sync.
    ///
    /// Phase 2 replaces this with a live HTTP fetch from
    /// `https://api.github.com/repos/SagerNet/sing-box/releases/latest`
    /// and a real SHA-256 of the downloaded asset.
    public func resolveLatestStable() async throws -> ReleaseInfo {
        ReleaseInfo(
            tag: "v1.13.0",
            downloadURL: URL(
                string: "https://github.com/SagerNet/sing-box/releases/download/v1.13.0/sing-box-1.13.0-darwin-arm64.zip"
            )!,
            sha256: "PLACEHOLDER_SHA256"
        )
    }
}
