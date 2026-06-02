# Archived: RiptideApp App Extension Stub

> Archived on 2026-06-01 as part of Plan 09 cleanup.
> Decision: this directory was a placeholder for a future macOS app
> extension (Share Extension, Finder Sync, or similar). It contains a
> single entitlements file and is not referenced by any build target.

## What was here

`AppExtensions/RiptideApp/RiptideApp.entitlements` — a 4 KB stub
entitlements plist. No `*.swift` source, no `Info.plist`, no
extension-point identifier. The file is not referenced in
`Package.swift` and is not embedded in any product.

## Why it was not used

- The `RiptideApp` SwiftUI client in `Sources/RiptideApp/` ships as a
  regular `.app` bundle and does not currently include any app
  extensions.
- Entitlements files without a corresponding extension target are inert
  and would be ignored by codesign at packaging time.

## To revive (when needed)

If a future plan item adds an app extension:

1. Create a new SwiftPM target in `Package.swift` with
   `type: .executableTarget` or `.target`, depending on extension type.
2. Add an `Info.plist` with `NSExtension` dictionary
   (`NSExtensionPointIdentifier`, `NSExtensionPrincipalClass`).
3. Add an `*.entitlements` file (or restore this one) with the required
   app-sandbox / network-client / network-server entries.
4. Add `Sources/RiptideApp/<ExtensionName>/` next to the main app target
   rather than reviving this top-level layout.

Estimate < 1 day once the extension design is decided.
