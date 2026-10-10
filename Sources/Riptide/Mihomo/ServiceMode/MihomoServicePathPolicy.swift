import Foundation

/// Path validation for the mihomo service daemon.
///
/// The daemon runs as root and executes whatever core path a request carries,
/// so every path must be vetted before use (the same trust boundary Clash
/// Verge's service and Riptide's XPC helper enforce). Rules:
///
/// - **Core executable** must live under the admin-writable system root
///   (`/Library/Application Support/Riptide/`). Non-admin users cannot write
///   there, which prevents planting a binary for root execution.
/// - **Config files** must live under Riptide's managed mihomo directories
///   (either the system root or any user's
///   `~/Library/Application Support/Riptide/mihomo/`) and end in `.yaml`.
/// - **Core install sources** must be Riptide-managed locations an attacker
///   cannot use as an arbitrary-file oracle: the system root, any user's
///   Riptide app-support tree, or inside `/Applications`. The daemon copies
///   (never moves) from these paths into the system root.
///
/// All checks operate on symlink-resolved, standardized absolute paths and
/// reject `..` traversal.
public enum MihomoServicePathPolicy {

    /// Standardizes and resolves a path for prefix checks.
    static func normalized(_ path: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        let standardized = NSString(string: expanded).standardizingPath
        let resolved = NSString(string: standardized).resolvingSymlinksInPath
        return resolved
    }

    /// True when `path` (after normalization) equals or lies under `prefix`.
    static func hasPrefix(_ prefix: String, path: String) -> Bool {
        let normalizedPath = normalized(path)
        let normalizedPrefix = normalized(prefix)
        guard normalizedPath.hasPrefix(normalizedPrefix) else { return false }
        // Guard against sibling directories sharing a prefix
        // (e.g. "/RiptideOther" vs "/Riptide").
        guard normalizedPath.count > normalizedPrefix.count else {
            return true // exact match
        }
        return normalizedPath[normalizedPrefix.endIndex] == "/"
    }

    /// True when the core executable may be run as root.
    ///
    /// - Parameters:
    ///   - path: requested core executable path.
    ///   - systemRoot: admin-writable install root (tests inject a temp dir).
    public static func isAllowedCorePath(_ path: String, systemRoot: String) -> Bool {
        guard hasPrefix(systemRoot, path: path) else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized(path), isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }

    /// True when the config file may be passed to the core.
    ///
    /// - Parameters:
    ///   - path: requested config path.
    ///   - systemRoot: admin-writable install root.
    ///   - userRoots: per-user Riptide directories allowed to host configs
    ///     (e.g. the installing user's `~/Library/Application Support/Riptide`).
    public static func isAllowedConfigPath(_ path: String, systemRoot: String, userRoots: [String]) -> Bool {
        guard path.hasSuffix(".yaml") || path.hasSuffix(".yml") else { return false }
        if hasPrefix(systemRoot, path: path) { return true }
        for userRoot in userRoots where hasPrefix(userRoot, path: path) { return true }
        return false
    }

    /// True when the source path may be copied into the system root by
    /// `POST /v1/core/install`.
    ///
    /// - Parameters:
    ///   - path: user-readable source binary.
    ///   - systemRoot: admin-writable install root.
    ///   - userRoots: allowed per-user Riptide directories.
    public static func isAllowedCoreSource(_ path: String, systemRoot: String, userRoots: [String]) -> Bool {
        if hasPrefix(systemRoot, path: path) { return true }
        for userRoot in userRoots where hasPrefix(userRoot, path: path) { return true }
        if hasPrefix("/Applications", path: path) { return true }
        return false
    }
}
