# D1 — sing-box integration route

Date: 2026-06-02
Status: Accepted
Deciders: @G3niusYukki

## Context

Riptide's macOS engine today is a dual setup: a pure-Swift engine (covers ~5
protocols: HTTP/CONNECT, SOCKS5, Shadowsocks AEAD, Snell, Trojan) plus a
mihomo sidecar (covers the long tail: VMess/VLESS/Hysteria 2/TUIC/...).
The competitive analysis in `docs/analysis/2026-06-02-riptide-vs-surge-stash.md`
§1.1 identified **6 P0/P1 protocol gaps** that users ask for in 2024+:
- VLESS + Reality
- WireGuard (as proxy)
- ShadowTLS v3
- TUIC v5
- Hysteria 2 port hopping
- uTLS fingerprint

The cleanest path to closing most of these in one move is to add **sing-box**
as a third runtime (alongside Swift Engine + mihomo). Riptide already has
a `Sources/Riptide/SingBox/SingBoxCore.swift` scaffold but no integration
route has been chosen. This ADR picks that route.

## Considered Options

### Option A: sing-box as sidecar process (mirrors mihomo)

- Spawn `sing-box` binary as a child process; talk to it via its REST
  API (:9090) and log stream (stdout), exactly like mihomo today
- Reuse the existing `MihomoRuntimeManager` lifecycle pattern (start /
  health-check / restart) by generalizing it to a `SidecarRuntimeManager`
- Download via `Scripts/download-sing-box.sh` analogous to
  `Scripts/download-mihomo.sh`; pinned SHA-256 in repo
- Each protocol lives in sing-box's config; the Swift side generates
  the config and calls REST to switch nodes / flush DNS
- **Pros:**
  - Zero new Cgo / FFI / linking complexity — keeps the SwiftPM-only
    build working (important for CI and Homebrew distribution)
  - Reuses 100% of the mihomo runtime plumbing; we already proved
    this works (CI green, 8 P0 features shipped via mihomo)
  - Matches the existing `RiptideHelper` privilege model (helper
    spawns sidecar as root) — no new privilege boundary
  - sing-box binary is ~12MB; mihomo is ~9MB; net binary size hit
    +12MB (acceptable given DMG users already accept a 30MB app)
  - When sing-box has a security fix, just bump the pinned binary
- **Cons:**
  - Two processes running (mihomo + sing-box) when user has both
    enabled — extra ~30MB RAM and one extra restart surface
  - Latency tax of REST API roundtrip on every node switch (~5-15ms)
  - sing-box has its own quirks vs. mihomo (e.g. log format,
    config schema) — need to maintain a thin compatibility shim
- **Estimated effort:** 2-3 weeks (mostly reuses mihomo plumbing)

### Option B: sing-box statically linked via Cgo (Go as a library)

- Vendor sing-box as a Go package; build a `libsingbox.a` via `go build
  -buildmode=c-archive`; link into the Swift app via a `SingBox.xcframework`
  similar to the existing `GoCore.xcframework`
- Swift calls sing-box's C API directly: no REST, no process
- **Pros:**
  - No second process; lower RAM; faster node switches (no REST
    roundtrip)
  - Single binary to ship and notarize
  - Direct access to sing-box's internal state (better telemetry)
- **Cons:**
  - **Doubles build complexity**: now need to maintain a Go build
    pipeline alongside SwiftPM. CI matrix goes from 3 platforms to
    3 platforms × 2 toolchains
  - **Static linking + Swift 6 strict concurrency is fragile**: Go's
    runtime model (goroutines, GC) does not interop cleanly with
    Swift's actor model. The existing `GoCore.xcframework` exists
    but has known interop friction (see CLAUDE.md Known Limitations)
  - **Bumps minimum macOS to 14 for sure** (Go runtime needs modern
    toolchain) — actually no worse than today (`.macOS(.v14)` already)
  - sing-box updates require rebuilding the static lib; loses the
    "bump binary" simplicity of sidecar
  - If sing-box has a security vuln, must ship a new app version
    (no out-of-band binary patch)
- **Estimated effort:** 6-8 weeks (build pipeline + interop hardening)

### Option C: Defer — keep mihomo only, add protocols one at a time

- Don't add sing-box; instead add Reality / WireGuard / TUIC / etc. to
  mihomo one by one as mihomo adds them upstream
- **Pros:** Zero new integration work
- **Cons:**
  - mihomo's protocol roadmap is **slower** than sing-box's
    (e.g. mihomo got VLESS Reality ~6 months after sing-box)
  - Some protocols (uTLS fingerprint fine-tuning, certain
    Reality XTLS variants) are sing-box-first
  - Doesn't help if a future user wants a feature only sing-box has
- **Estimated effort:** 0 weeks, but accumulates technical debt

## Decision

**Option A: sing-box as sidecar process**, mirroring the existing mihomo
sidecar pattern. Reuse `MihomoRuntimeManager`'s lifecycle code by
generalizing it to a `SidecarRuntimeManager<Config, Stats>` generic,
parameterized on the sidecar kind. This gives us the 6 P0 protocols in
~2-3 weeks while preserving the proven CI/distribution pipeline. We
can revisit Option B in 12+ months if RAM or node-switch latency
becomes a real user complaint (we have telemetry to detect this).

## Consequences

**Enables:**
- W2-1: VLESS + Reality path working (sing-box 1.9+ has mature Reality)
- W2-1: WireGuard proxy (sing-box has native WireGuard outbound)
- W2-1: TUIC v5 (sing-box upstream)
- W2-1: ShadowTLS v3 (sing-box upstream)
- W2-1: Hysteria 2 port hopping (sing-box upstream)
- W2-1: uTLS fingerprint (sing-box has richer uTLS profile support
  than mihomo today)
- A `Kernels` settings tab where the user can pick mihomo / sing-box /
  both per protocol — natural extension of `ModeCoordinator`

**Forecloses:**
- We do not get a single-binary app. The DMG is now ~42MB instead
  of ~30MB. Users on macOS 12 (already unsupported) would have
  loved a smaller binary — but they're already dropped.
- Direct access to sing-box internals from Swift is more limited
  (must go through REST). For the diagnostics surface (Logbook, W3-2)
  this is fine.

**Follow-up actions:**
- T+1: Spike `Scripts/download-sing-box.sh` to verify we can pin a
  SHA-256 like we do for mihomo. If GitHub releases don't expose
  consistent SHA, fall back to signature-based verification.
- T+1: Refactor `MihomoRuntimeManager` into `SidecarRuntimeManager`
  with a `SidecarKind` enum (mihomo | singBox). This refactor
  is a prerequisite for W2-1.
- T+1: Decide kernel-switch UX in `Settings → Kernels` (separate
  ADR if it grows beyond a few lines; not needed for SP-1).
- T+2: Add a `KERNEL_SELECTION` config block so users can map
  protocols to kernels (e.g. "all Reality nodes go to sing-box,
  everything else to mihomo").

**Risks:**
- Two sidecars running at once = +30MB RAM. Mitigation: only start
  the second sidecar on demand (lazy) or when user enables a
  protocol that needs it. Default to mihomo-only.
- sing-box releases are more frequent than mihomo; we need an
  update cadence (quarterly?) to stay current. Mitigation: track
  sing-box releases in CI; auto-PR version bumps.
