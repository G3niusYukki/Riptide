# RiptideWidget — Installation Notes

This directory contains the Swift source for a macOS Notification Center
widget that displays Riptide's current upload and download throughput
along with the name of the active proxy node.

## Status: scaffold (library target)

The widget compiles as a regular SwiftPM library and is unit-testable, but
it is **not** a runnable Notification Center widget today. Apple does not
allow SwiftPM to produce `.appex` extension bundles — extensions require an
Xcode project target with the correct `NSExtension` Info.plist, App Group
entitlements, and an "Embed App Extensions" build phase. The migration path
below describes what is required to ship the widget.

## Files

| File | Role |
|------|------|
| `RiptideWidgetBundle.swift` | `@main` `WidgetBundle` that publishes the widget |
| `RiptideSpeedWidget.swift` | The `Widget` declaration (kind, display name, supported families) |
| `SpeedProvider.swift` | `TimelineProvider` reading from the App Group container |
| `SpeedWidgetView.swift` | SwiftUI body — node name, ↑/↓ throughput, last-updated time |
| `SharedTrafficSnapshot.swift` | Codable snapshot exchanged via the App Group container |

## Migration to a real `.appex`

1. **Add a widget extension target** in an Xcode project that consumes this
   package. Set the target's `Info.plist` to declare:
   ```xml
   <key>NSExtension</key>
   <dict>
       <key>NSExtensionPointIdentifier</key>
       <string>com.apple.widgetkit-extension</string>
       <key>NSExtensionPrincipalClass</key>
       <string>$(PRODUCT_MODULE_NAME).RiptideWidgetBundle</string>
   </dict>
   ```
   (The principal class is set to the bundle type so we do not need a
   duplicate `@main` annotation inside the extension target.)
2. **Add the App Group capability** `group.com.riptide.app` to **both**
   the `RiptideApp` target and the new `RiptideWidget.appex` target.
3. **Embed the extension** by adding `RiptideWidget.appex` to the host
   app's "Embed App Extensions" build phase.
4. **Write from the host app.** `SharedTrafficSnapshot` is read-only from
   the widget's side. From `AppViewModel.refreshStats`, publish a snapshot
   on every tick (matching the `group.com.riptide.app` App Group already
   used by `AppGroupStateStore`):
   ```swift
   SharedTrafficSnapshot.write(
       SharedTrafficSnapshot(
           uploadBytesPerSec: currentSpeedUp,
           downloadBytesPerSec: currentSpeedDown,
           activeNode: activeNodeName
       )
   )
   ```
5. **Refresh cadence** is fixed at one minute by `SpeedProvider.getTimeline`.
   This is Mac power-friendly and satisfies WidgetKit's policy that user-
   facing widgets should not refresh more often than every minute without a
   `WidgetCenter.shared.reloadAllTimelines()` call from the host app.

## Why a library target is the right intermediate step

- The full widget implementation is in version control and reviewable.
- The Codable snapshot is unit-testable on every CI run, which gives us a
  regression net for the data model that is the contract between the host
  app and the widget.
- The day someone wraps this in an `.appex` target, the code is ready —
  no "where did the widget go?" archaeology required.
