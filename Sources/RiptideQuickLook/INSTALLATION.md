# RiptideQuickLook — Installation Notes

This directory contains the Swift source for a Finder **Quick Look
preview extension** that renders a Riptide-flavoured summary of a
Clash-style YAML configuration when the user selects a `.yaml` or
`.yml` file in Finder and presses Space.

## Status: scaffold (library target)

The preview compiles as a regular SwiftPM library and is unit-testable,
but it is **not** a real Quick Look extension today. Apple does not
allow SwiftPM to produce `.appex` extension bundles — extensions
require an Xcode project target with the correct `NSExtension` Info.plist
and an "Embed App Extensions" build phase. The migration path below
describes what is required to ship the preview.

## Files

| File | Role |
|------|------|
| `YAMLPreviewStats.swift` | Sendable summary model — proxy/group/rule counts, protocol breakdown, first N nodes, sanitized subscription URL |
| `YAMLPreviewParser.swift` | Lenient YAML→stats parser. Never throws; degrades to an empty summary on invalid YAML |
| `QuickLookPreviewView.swift` | SwiftUI body rendered in the preview pane (header, stat cards, protocol chips, node table) |
| `QuickLookPreviewBuilder.swift` | Bridge that reads a file URL and produces an `NSHostingController` ready to embed in the extension |

## Migration to a real `.appex`

1. **Add a Quick Look Preview Extension target** in an Xcode project
   that consumes this package. Set the target's `Info.plist` to declare:
   ```xml
   <key>NSExtension</key>
   <dict>
       <key>NSExtensionPointIdentifier</key>
       <string>com.apple.quicklook.preview</string>
       <key>NSExtensionAttributes</key>
       <dict>
           <key>QLSupportedContentTypes</key>
           <array>
               <string>public.yaml</string>
               <string>public.plain-text</string>
           </array>
           <key>QLPreviewMinimumVersion</key>
           <string>14.0</string>
       </dict>
       <key>NSExtensionPrincipalClass</key>
       <string>$(PRODUCT_MODULE_NAME).RiptideQuickLookProvider</string>
   </dict>
   ```
2. **Create the principal class** in the extension target. It
   conforms to `QLPreviewProvider` and delegates to
   `QuickLookPreviewBuilder`:
   ```swift
   import QuickLook
   import RiptideQuickLook

   @objc(RiptideQuickLookProvider)
   public final class RiptideQuickLookProvider: NSObject, QLPreviewProvider {
       public func providePreview(
           for request: QLFilePreviewRequest
       ) async throws -> QLPreviewReply {
           let url = request.fileURL
           let hosting = try await MainActor.run {
               try QuickLookPreviewBuilder.makeHostingController(for: url)
           }
           let reply = QLPreviewReply(contextSize: .init(width: 600, height: 800)) { _ in
               hosting.view
           }
           return reply
       }
   }
   ```
3. **Embed the extension** by adding `RiptideQuickLook.appex` to the
   host app's "Embed App Extensions" build phase. The extension does
   not need App Group access (it only reads the file Finder hands it).
4. **Register the file types** in the host app's Info.plist so the
   user can associate `.yaml` / `.yml` with Riptide. Quick Look
   supports the system-wide associations automatically once the
   extension is installed.
5. **Sign and notarize** the host app. Unsigned `.appex` bundles are
   not loaded by Finder.

## Why a library target is the right intermediate step

- The full preview implementation is in version control and reviewable.
- The parser is unit-testable on every CI run, which gives us a
  regression net for the data model and the URL sanitizer that the
  preview view consumes.
- The day someone wraps this in an `.appex` target, the code is ready —
  no "where did the Quick Look go?" archaeology required.

## Privacy notes

The preview **must not** surface credentials. The
`YAMLPreviewParser.sanitizeSubscriptionURL` helper strips userinfo
and redacts `token` / `password` / `secret` / `key` query
parameters; the `YAMLPreviewNode` projection intentionally drops
cipher, password, UUID, and all key material. The SwiftUI view never
receives those fields, so even a careless future code change in the
view layer cannot leak credentials into the preview pane.
