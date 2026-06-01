import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// The bridge between Finder's Quick Look runtime and the preview UI.
///
/// The `.appex` target wraps this type as the `NSExtensionPrincipalClass`.
/// It is a thin layer that:
///   1. Reads the YAML file at the URL Finder passed us.
///   2. Parses it into `YAMLPreviewStats`.
///   3. Renders a `QuickLookPreviewView` into the bitmap context the
///      extension provides (or, on macOS 14+, into the
///      `QLPreviewView` via an `NSHostingController`).
///
/// This file does **not** import `QuickLook` on purpose: the framework
/// is a deprecated legacy API on modern macOS, and the Swift module
/// map for it is awkward to consume from SwiftPM. The principal
/// class file in the `.appex` target will add the conformance
/// (`QLPreviewProvider` or the legacy `QLGenerator` protocol) and
/// delegate to `QuickLookPreviewBuilder` for the actual work.
@available(macOS 14, *)
public enum QuickLookPreviewBuilder {

    public enum BuildError: Error, Equatable, Sendable {
        case fileUnreadable(URL)
    }

    /// Build a fully prepared preview view for the given file URL.
    /// Throws when the file cannot be read.
    public static func makeStats(for fileURL: URL) throws -> YAMLPreviewStats {
        do {
            return try YAMLPreviewParser.parse(fileURL: fileURL)
        } catch {
            throw BuildError.fileUnreadable(fileURL)
        }
    }

    /// Build a hosting controller that renders the preview.
    /// The `QLPreviewProvider` in the `.appex` target embeds this
    /// controller in its preview view.
    @MainActor
    public static func makeHostingController(for fileURL: URL) throws -> NSHostingController<AnyView> {
        let stats = try makeStats(for: fileURL)
        let view = QuickLookPreviewView(stats: stats)
        return NSHostingController(rootView: AnyView(view))
    }
}
