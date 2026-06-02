# Archived: RiptideMac Stub

> Archived on 2026-06-01 as part of Plan 09 cleanup.
> Decision: this directory was a placeholder for the planned
> macOS-specific module in the iOS cross-platform split. The split was
> never executed (iOS is out of scope for v3.0.0 GA — see `README.md` →
> Platforms).

## What was here

A single 9-line `README.md` documenting what the planned `RiptideMac`
module would have contained: VPN/NetworkExtension, XPC helper, Mihomo
lifecycle, TUN bridge, LocalProxy, AppShell, SingBox config generator.

In practice, **all of these components already live inside
`Sources/Riptide/`**:

| README claim | Actual location |
|--------------|-----------------|
| VPN / NetworkExtension | `Sources/Riptide/VPN/` |
| XPC helper integration | `Sources/Riptide/XPC/` |
| Mihomo lifecycle | `Sources/Riptide/Mihomo/` |
| Tunnel runtime | `Sources/Riptide/Tunnel/` |
| LocalProxy | `Sources/Riptide/LocalProxy/` |
| AppShell | `Sources/Riptide/AppShell/` |

## Why it was not promoted

1. The original motivation was a separate target so iOS could depend on
   the cross-platform subset. With iOS out of scope, the split has no
   payoff and would only add build complexity (two targets, two module
   graphs, more `@testable import` boilerplate).
2. `RiptideMac` is **not** referenced anywhere in `Package.swift`.

## To revive (not recommended)

If/when iOS support is reintroduced (post-v3.0.0), revisit
`docs/MODULE-SPLIT.md` and re-run the migration plan there. The current
`Sources/Riptide/` directory layout already mirrors the proposed
`RiptideCore` / `RiptideMac` split at the folder level (see table above);
the actual SwiftPM target split is the missing piece.

Estimate 4-6 weeks of refactoring to make the split cleanly: introduce
platform-conditionals (`#if os(macOS)`), split `Package.swift` targets,
and verify all 491 tests still pass under the new module graph.
