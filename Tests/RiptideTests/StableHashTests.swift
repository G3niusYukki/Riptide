import Foundation
import Testing
@testable import Riptide

/// FIX-3: process-independent hash + UUID derivation.
@Suite("StableHash")
struct StableHashTests {

    @Test("fnv1a of empty string is the FNV offset basis")
    func fnv1aEmptyStringIsFnvOffsetBasis() {
        // Reference: FNV-1a 64-bit offset basis.
        #expect(StableHash.fnv1a("") == 0xcbf29ce484222325)
    }

    @Test("fnv1a of \"a\" matches known FNV-1a test vector")
    func fnv1aKnownVector() {
        // Reference: FNV-1a test vector (64-bit).
        #expect(StableHash.fnv1a("a") == 0xaf63dc4c8601ec8c)
    }

    @Test("fnv1a is deterministic across calls")
    func fnv1aIsDeterministic() {
        let a = StableHash.fnv1a("hello world")
        let b = StableHash.fnv1a("hello world")
        #expect(a == b)
    }

    @Test("uuid is deterministic for the same input")
    func uuidIsDeterministic() {
        let a = StableHash.uuid(from: "provider-1")
        let b = StableHash.uuid(from: "provider-1")
        #expect(a == b)
    }

    @Test("uuid differs for different inputs")
    func uuidDiffersForDifferentInputs() {
        let a = StableHash.uuid(from: "provider-1")
        let b = StableHash.uuid(from: "provider-2")
        #expect(a != b)
    }

    @Test("uuid has RFC 4122 v4 version and variant bits")
    func uuidHasRfc4122VersionAndVariant() {
        let u = StableHash.uuid(from: "test")
        let s = u.uuidString
        // v4 UUIDs start with the version digit '4' in the third group.
        // Example: xxxxxxxx-xxxx-4xxx-Yxxx-xxxxxxxxxxxx where Y ∈ {8,9,a,b}.
        let parts = s.split(separator: "-")
        #expect(parts.count == 5)
        #expect(parts[2].first == "4")
        let variantChar = parts[3].first!
        #expect(variantChar == "8" || variantChar == "9" ||
                variantChar == "a" || variantChar == "b")
    }
}
