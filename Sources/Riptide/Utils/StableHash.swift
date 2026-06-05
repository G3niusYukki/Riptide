import Foundation

/// FIX-3: process-independent hash + UUID derivation.
///
/// Swift's `String.hashValue` is randomized per execution (per-process
/// hash seed), which means the same input string produces different
/// `Int` values across app launches. Anywhere we need a stable identifier
/// derived from a human-readable name (provider IDs, cache keys, etc.),
/// we must use a deterministic hash like FNV-1a.
public enum StableHash {

    /// FNV-1a 64-bit hash. Identical inputs always produce identical
    /// outputs across processes and platforms.
    public static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037 // FNV offset basis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211 // FNV prime
        }
        return hash
    }

    /// Derives a deterministic UUID from a string. Two calls with the same
    /// input produce the same UUID across processes — this is required
    /// when the same logical name must map to the same identifier across
    /// app restarts (e.g. `ModeCoordinator`'s registered provider IDs).
    ///
    /// Uses two FNV-1a runs (one on the input, one on `input + "\0"`) to
    /// populate the 128-bit UUID space, then sets the RFC 4122 v4
    /// version and variant bits.
    public static func uuid(from string: String) -> UUID {
        let h1 = fnv1a(string)
        let h2 = fnv1a(string + "\u{0000}")
        // RFC 4122 v4 + variant 10.
        let high = (h1 & 0xFFFFFFFFFFFF0FFF) | 0x0000000000004000
        let low  = (h2 & 0x3FFFFFFFFFFFFFFF) | 0x8000000000000000
        let bytes: [UInt8] = (0..<16).map { i in
            let word = i < 8 ? high : low
            let shift = (8 - 1 - (i % 8)) * 8
            return UInt8((word >> shift) & 0xff)
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
