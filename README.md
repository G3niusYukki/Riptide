# Riptide

macOS 14+ proxy client. SwiftUI app, a Swift library, and a mihomo core for TUN.

Clash-compatible profiles. System proxy does not need root. TUN uses a launchd daemon that you install once.

## Requirements

- macOS 14 or later
- Swift 6.2+ / Xcode 16+

## Build and run

```bash
swift test
swift run RiptideApp
./Scripts/build-release.sh
```

The release script writes `.build/release-dmg/RiptideApp.app` and, when the volume is free, `Riptide.dmg`. It signs with a local identity whose Team ID is `39Q4M52XNQ` when one is installed. Otherwise it ad-hoc signs. Certificates and private keys are never committed.

## TUN

`connectionMode == .tun` starts only through `riptide-mihomo-service` (launchd + a Unix socket). The first install asks for an administrator password. Later start and stop do not. DNS stays inside mihomo (fake-ip). The app does not rewrite system DNS with `networksetup`.

## Layout

```
Sources/Riptide/          library
Sources/RiptideApp/       SwiftUI app
Sources/RiptideCLI/       riptide CLI
Sources/RiptideMihomoService/
RiptideHelper/            privileged helper
Tests/RiptideTests/
Scripts/build-release.sh
```

## Docs

- Agents and contributors: `AGENTS.md`
- Signing: `docs/signing-setup.md`
- Why the helper checks a team ID: `docs/decisions/0004-helper-trust-model.md`
- Why TUN is a launchd service: `docs/decisions/2026-06-02-d3-service-mode.md`
- macOS-only decision: `docs/decisions/0012-macos-only-direction-and-signing-identity.md`
