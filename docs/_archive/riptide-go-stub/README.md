# Archived: RiptideGo Stub

> Archived on 2026-06-01 as part of Plan 09 cleanup.
> Decision: superseded by the mihomo sidecar integration.

## What was here

A Go-based proxy core wrapping [`sagernet/sing-box`](https://sing-box.sagernet.org/),
exposed to Swift via a C-archive build of an XCFramework
(`Frameworks/GoCore.xcframework`).

| File | Purpose |
|------|---------|
| `main.go` | `//export` C entry points: `GoCoreStart`, `GoCoreStop`, `GoCoreGetTraffic`, `GoCoreSwitchProxy` |
| `go.mod` / `go.sum` | Go module pinning sing-box v1.9.0-rc.1 |
| `build.sh` | `go build -buildmode=c-archive` for macOS arm64 + amd64, then `lipo` and `xcodebuild -create-xcframework` |

## Why it was not used

The build script produces `../../Frameworks/GoCore.xcframework` — that
path is **not** referenced in `Package.swift`, and no Swift file imports
the generated `GoCore` module. The build itself was never run on a clean
clone (no `build/` artifacts, no `GoCore.xcframework` in version control).

The runtime proxy engine in production is the **mihomo** sidecar
(see `Sources/Riptide/Mihomo/`), not a vendored Go core. mihomo is shipped
as a separate executable downloaded at install time and is controlled over
its REST + WebSocket API.

## To revive (not recommended)

If a future plan item needs the embedded Go core approach:

1. Run `Sources/RiptideGo/build.sh` once to produce `Frameworks/GoCore.xcframework`.
2. Add `.xcframework` + `.systemLibrary` target to `Package.swift` with a
   `define` condition.
3. Replace or wrap the mihomo client surface
   (`Sources/Riptide/Mihomo/MihomoAPIClient.swift`) with a C-bridge to
   `GoCoreStart` / `GoCoreStop` / `GoCoreGetTraffic`.
4. Restore `RiptideGo` to `Sources/RiptideGo/`.
5. Re-pin `sing-box` (v1.9.0-rc.1 is unreleased; check current release
   branch before reviving).

Estimate 2-3 weeks to revive, plus ongoing maintenance of the Go module.

## Stale reference

None. No Swift file in `Sources/` imports the `GoCore` module.
