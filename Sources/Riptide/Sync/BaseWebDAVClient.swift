import Foundation

/// FIX-5: shared building blocks for the project's WebDAV clients.
///
/// Both `WebDAVClient` (Sync/) and `ConfigSyncWebDAVClient` (Config/) need
/// the same path normalization logic. Free functions avoid forcing both
/// actors onto a single protocol while still keeping the two
/// implementations in lockstep.
public enum WebDAVShared {
    /// Normalizes `path` and resolves it against `baseURL`. Mirrors the
    /// private `resolvedURL(for:)` logic that used to live in both clients.
    /// Returns `nil` only if `URL(string:relativeTo:)` itself fails — the
    /// legacy implementations did not propagate that failure mode either,
    /// so we keep the same forgiving contract here.
    public static func resolveURL(baseURL: URL, for path: String) -> URL? {
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.isEmpty { return baseURL }
        var base = baseURL
        if !base.absoluteString.hasSuffix("/") {
            base = base.appendingPathComponent("")
        }
        return URL(string: normalizedPath, relativeTo: base)?.absoluteURL
    }

    /// Standard PROPFIND body for a directory listing. Property set matches
    /// what `WebDAVClient` already used; kept as a single source of truth so
    /// a future property addition (e.g. `getetag` for conditional GETs)
    /// lands in both clients simultaneously.
    public static let propfindBody: Data = Data("""
    <?xml version="1.0" encoding="utf-8"?>
    <D:propfind xmlns:D="DAV:">
        <D:prop>
            <D:displayname/>
            <D:getcontentlength/>
            <D:getlastmodified/>
            <D:resourcetype/>
        </D:prop>
    </D:propfind>
    """.utf8)
}
