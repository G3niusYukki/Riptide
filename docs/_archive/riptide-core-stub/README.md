# Archived: RiptideCore Stub

> Archived on 2026-06-01 as part of Plan 09 cleanup.
> Decision: This directory was scaffolded for the planned iOS module split
> (see `docs/MODULE-SPLIT.md`) but the split was never executed. The single
> `Riptide` module in `Sources/Riptide/` is the production target.

## What was here

- `README.md` — placeholder for the cross-platform module.
- `Protocols/WireGuard/` — 4 Swift files implementing a WireGuard Noise IK
  handshake, transport encryption, configuration model, and stream wrapper.

## Why it was not promoted to production

1. The Riptide v3.0.0 GA targets macOS only. iOS is out of scope (see
   `README.md` → Platforms), so the cross-platform motivation for splitting
   `Riptide` into `RiptideCore` + `RiptideMac` no longer applies.
2. The `Riptide` module in `Sources/Riptide/` is the single source of truth
   and is referenced by `RiptideApp` and `RiptideCLI` via `Package.swift`.
   `RiptideCore` is **not** referenced anywhere in `Package.swift` and
   therefore was never compiled or tested as part of the build.

## WireGuard code — NOT production-grade

The WireGuard implementation in `Protocols/WireGuard/` is a **prototype**.
It is preserved here for reference but is **not** safe to use. Specific
issues (also documented in the source):

- `WireGuardCrypto.swift:91-95` — BLAKE2s is replaced with HMAC-SHA256, with
  an explicit comment: "In production this MUST be BLAKE2s-256 per the
  WireGuard spec." The BLAKE2s primitive is not in CryptoKit and would need
  to be vendored (e.g. swift-bcrypt or a hand-rolled reference impl).
- `WireGuardHandshake.swift:117` — "simplified Noise IK" comment; the full
  WireGuard Noise IK pattern with mixing, MAC verification, and timestamp
  semantics is not implemented.
- `WireGuardHandshake.swift:130-160` — Initiation message construction is
  not bit-compatible with a real WireGuard peer.
- `WireGuardStream.swift:57,60` — Force-unwraps on parsed endpoint parts
  (`peers.first!`, port string parsing with `??` on `UInt16`).
- No rekey timer beyond a `Task` scheduled on each send (`Handshake.swift:336`).
- No cookie / DoS mitigation (`mac1`/`mac2`) on the responder side.
- No test coverage. There is no test in `Tests/RiptideTests/` that imports
  or exercises this code.

## Follow-up (do not pick up casually)

If/when WireGuard support is required, the path forward is:

1. Open a follow-up plan item. Do not just wire this code into `Riptide`.
2. Either:
   - **Option A (recommended):** continue to delegate WireGuard to the
     mihomo sidecar (current behavior, see
     `Sources/Riptide/Connection/ProxyConnector.swift:286-296`).
   - **Option B:** build a real, spec-compliant implementation. Estimate
     3-4 weeks of focused work: BLAKE2s primitive, full Noise IK mixing,
     cookie machinery, rekey state machine, integration tests against
     `wireguard-go` or `wireguard-linux`.
3. Add tests under `Tests/RiptideTests/Protocols/WireGuard/` covering
   initiation/response bit-compat against a known-good peer, transport
   data round-trip, rekey after 120s, and rejection after 180s.

## Stale reference

`Sources/Riptide/Connection/ProxyConnector.swift` previously contained a
comment pointing to `Sources/RiptideCore/Protocols/WireGuard/`. That
comment was updated as part of this archive to point here.
