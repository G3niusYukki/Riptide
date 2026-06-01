# Archived: Riptide iOS App Stub

> Archived on 2026-06-01 as part of Plan 09 cleanup.
> Decision: iOS support is out of scope for the macOS-first v3.0.0 GA.

This directory contains the original iOS App scaffold (1.2 KB).
Code is preserved for future reference but is not compiled or shipped.

To revive:
1. Create new SwiftPM target `RiptideApp_iOS` with `path: "docs/_archive/riptide-ios-stub/App"`
2. Refactor `MainActor` and `Sendable` for iOS lifecycle
3. Add NetworkExtension entitlement and tunnel provider
4. Implement PacketTunnelProvider (currently TODO)
5. Estimate 6-8 weeks of focused work for production-quality
