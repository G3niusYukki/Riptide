# ADR-0007: Windows kernel router — mihomo primary, sing-box as a sidecar

> **Status:** Accepted · **Date:** 2026-06-05 · **Deciders:** maintainers

## Context

`riptide-windows/` currently has exactly one proxy kernel: **mihomo**
(spawned as a child process and driven through its REST API at
`127.0.0.1:9090`). mihomo covers the long tail of Clash-compatible
protocols — Shadowsocks, VMess, VLESS (non-Reality), Trojan, Hysteria 2,
Snell, TUIC, SOCKS5, HTTP CONNECT — which is the same kernel macOS
uses as its sidecar today.

v2.5.0 of Riptide will require **protocols that mihomo either does
not implement or implements behind a feature flag that lags the
upstream community**:

- **VLESS + Reality** — Reality is the dominant anti-censorship
  transport in 2024+. mihomo's Reality implementation has historically
  lagged sing-box's by several months on uTLS profile parity and
  XTLS-vision splice behaviour.
- **AnyTLS** — a newer transport that mihomo still classifies as
  experimental; sing-box ships it stable.
- **WireGuard-as-proxy** — used by WARP-style deployments. mihomo has
  no first-class WireGuard outbound; sing-box does.
- **ShadowTLS v3**, **TUIC v5** with port hopping, **uTLS fingerprint
  fine-tuning** — all are sing-box-first.

The Windows catchup plan
([`../WINDOWS-CATCHUP-PLAN.md`](../WINDOWS-CATCHUP-PLAN.md) §3
C5) and the macOS precedent (see
[`../decisions/0005-proxy-engine-protocol.md`](0005-proxy-engine-protocol.md)
and
[`../decisions/2026-06-02-d1-singbox-integration.md`](2026-06-02-d1-singbox-integration.md))
agree on the **direction** — multi-kernel with explicit per-protocol
routing — but neither has committed Windows to a specific integration
shape. This ADR closes that gap.

Three integration shapes are viable on Windows:

1. **Static link sing-box into `riptide.exe`** — mirrors
   macOS's `GoCore.xcframework`. Doubles the build pipeline, breaks
   Tauri 2's "one binary per process" model, and removes the ability
   to ship an out-of-band mihomo/sing-box security fix without a
   Riptide release. macOS already pays this tax; we should not
   replicate it on Windows for a v2.5.0 ramp.
2. **Defer all Reality/AnyTLS to "mihomo will catch up"** — historically
   false (Reality and uTLS are sing-box-first by ≥ 6 months). Forcing
   users to wait is a competitive regression vs. Surge / Stash /
   sing-box-for-Windows clients.
3. **Spawn sing-box as a second sidecar process**, mirroring the
   existing mihomo lifecycle, with a small Rust trait
   (`ProxyEngine`) and a router (`EngineRouter`) that picks a kernel
   per `ProxyKind`. This is the shape macOS picked in D1, and it is
   the only shape that keeps the Windows build pipeline simple
   (one Rust toolchain, two sidecar binaries, no FFI).

## Decision

**Windows adopts a two-kernel router with mihomo as the primary
(default) kernel and sing-box as a secondary sidecar that can be
enabled per-protocol.** The shape is identical to macOS's
`Sources/Riptide/SingBox/` + `Sources/Riptide/Engines/`:

- `riptide-windows/src-tauri/src/core/engines/proxy_engine.rs`
  defines a `ProxyEngine` trait (`Send + Sync`, with
  `kind() -> ProxyEngineKind`, `start()`, `stop()`, `reload()`,
  `status()`).
- `riptide-windows/src-tauri/src/core/engines/engine_router.rs`
  holds an `EngineRouter { policy: EnginePolicy }` that returns the
  engine for a given `ProxyKind`. The initial policy is
  `EnginePolicy::DefaultMihomo`, exactly mirroring
  `EngineRouter.Policy.defaultMihomo` from ADR-0005.
- `riptide-windows/src-tauri/src/core/singbox/` ships:
  - `paths.rs` — `WindowsDirs::singbox_dir()`, plus
    `singbox.exe` / `cache.db` location.
  - `config_generator.rs` — Clash `ProxyKind` → sing-box
    `outbound` JSON, with the same Reality / AnyTLS / WireGuard
    schemas macOS uses in
    `Sources/Riptide/SingBox/SingBoxConfigGenerator.swift`.
  - `downloader.rs` — pinned version + SHA-256, analogous to
    `core/mihomo_bootstrap.rs`. Initial pin is **v1.13.0** (the
    version the macOS side already validated).
  - `runtime_manager.rs` — process lifecycle (start / health-check /
    restart on crash), the same shape as `MihomoManager` and
    reusable via a future `SidecarRuntimeManager` generic.
  - `api_client.rs` — sing-box's REST surface (port `9091` to avoid
    colliding with mihomo's `9090`).

### Per-`ProxyKind` routing table

Identical to the macOS table from ADR-0005:

| `ProxyKind` | Engine |
|---|---|
| `shadowsocks`, `vmess`, `vless` (non-Reality), `trojan`, `hysteria2`, `snell`, `tuic`, `socks5`, `httpConnect` | **mihomo** |
| `reality`, `anytls` | **sing-box** |
| any unknown `ProxyKind` | **mihomo** (fallback) |

The pure-Swift in-process engine on macOS is a separate code path in
`LocalHTTPConnectProxyServer` and is **not** relevant on Windows — it
has no counterpart. (See ADR-0005 § "Decision" for the full rationale.)

### Phase rollout

- **Phase 1 (status-only)**: `EngineRouter` ships behind a
  `Settings → Kernels` panel that **only displays** which engines
  are installed, their versions, and last error. The router is
  always in `DefaultMihomo` mode; sing-box is downloaded and
  ready, but no traffic is routed through it. This lets us ship
  the panel, the downloader, the SHA-256 check, and the test
  coverage in
  [`../WINDOWS-CATCHUP-PLAN.md`](../WINDOWS-CATCHUP-PLAN.md) §3
  C5.1–C5.3 without forcing a behaviour change on users.
- **Phase 2 (per-protocol open)**: when a user profile contains a
  Reality or AnyTLS node, the router transparently dispatches the
  connection to sing-box. mihomo continues to handle everything
  else. UI: a small "via sing-box" badge on Reality / AnyTLS
  nodes. Test coverage grows to cover the router's policy table
  and the sing-box start/stop/restart path.
- **Phase 3 (default-on)**: the v2.5.0 release target. The default
  policy becomes "sing-box for Reality / AnyTLS, mihomo for the
  rest" and the in-app `Settings → Kernels` panel becomes a power-
  user override (force-mihomo, force-singbox, auto). This phase
  also includes the cross-platform `EngineBenchmark` harness from
  §3 C6 to detect regressions before they ship.

The boundary between Phase 1 and Phase 2 is gated on the
[`../WINDOWS-CATCHUP-PLAN.md`](../WINDOWS-CATCHUP-PLAN.md) §9
"Phase C go criteria":

> *EngineRouter + Sing-box sidecar PoC 跑起来*

If sing-box on Windows fails to reliably start the Reality
outbound in a CI smoke test, we **stay in Phase 1** for an extra
release cycle rather than ship a broken v2.5.0 default.

## Consequences

**Enables:**

- v2.5.0 Reality / AnyTLS / WireGuard-as-proxy / uTLS fine-tuning
  on Windows in the same release cycle as macOS.
- A `Kernels` settings tab that matches macOS's `Settings →
  Kernels` 1:1 — users on the same Riptide version see the same
  controls regardless of platform.
- A `proxy.engine` field in diagnostics reports, so bug reports
  name the engine, the version, and the last error. This is
  critical for the catchup plan's C6 `EngineBenchmark` harness
  (you can't compare two kernels if you don't know which one
  handled the connection).
- A future "second-sidecar" model in which we can hot-swap in
  future engines (e.g. a hypothetical pure-Rust kernel) without
  re-architecting the router.

**Costs and trade-offs:**

- +12-15 MB installer size (sing-box binary). Acceptable: the
  current NSIS bundle is already ~28 MB.
- +20-30 MB RAM when both kernels are running concurrently
  (mihomo + sing-box). Phase 1 mitigation: do **not** start
  sing-box on app launch. Lazy-start it the first time a Reality
  / AnyTLS node is selected, and stop it after 5 minutes of
  idle.
- The Rust trait `ProxyEngine` adds one level of indirection over
  the current direct call to `MihomoManager`. The cost is one
  virtual dispatch per node select (microseconds); the benefit is
  a clean cut-point for testing and for adding engines later.
- A second SHA-256 pin to maintain
  (`core/singbox/downloader.rs::SINGBOX_SHA256`). Like
  `MIHOMO_SHA256` (see ADR-0006), the empty string disables
  verification and is only acceptable during development.

**Forecloses (for now):**

- We do **not** statically link sing-box into `riptide.exe`. If
  RAM usage or the lazy-start lag becomes a user complaint, we
  revisit this (the macOS D1 ADR keeps the same escape hatch).
- We do **not** ship a Windows-only custom WireGuard kernel. All
  WARP-style traffic goes through sing-box's built-in WireGuard
  outbound.
- We do **not** re-design `MihomoConfigGenerator` to also emit a
  sing-box config in one pass. The two generators are independent
  on purpose — sing-box's config schema diverges from Clash YAML
  in ways that make a unified generator more trouble than it is
  worth.

**Follow-up actions (tracked under §3 C5 of the catchup plan):**

1. `core/singbox/paths.rs` — add `WindowsDirs::singbox_dir()`
   returning `%APPDATA%\Riptide\singbox\` and the corresponding
   `service.conf`-style machine-scope path for the SCM service
   (`%PROGRAMDATA%\Riptide\singbox\`). Update the
   `riptide-windows/AGENTS.md` § 6.1 path map accordingly.
2. `core/singbox/downloader.rs` — port the SHA-256 + GitHub
   release fetch pattern from `core/mihomo_bootstrap.rs`.
   Pin v1.13.0 initially. Treat an empty `SINGBOX_SHA256` the
   same way `MIHOMO_SHA256` is treated: dev-only, release-
   blocking.
3. `core/engines/{proxy_engine,engine_router}.rs` — port the
   Swift `ProxyEngine` protocol and `EngineRouter` from
   `Sources/Riptide/Engines/`. Keep the same `defaultMihomo`
   initial policy; do not invent a Windows-specific default.
4. `cmds/engines.rs` — Tauri commands: `engine_current()`,
   `engine_set_policy(EnginePolicy)`, `engine_supported_kinds()`,
   `engine_status()`. All return `Result<T, String>`.
5. Settings UI: `src/components/Settings/KernelsTab.tsx` — read-
   only panel in Phase 1 (status + version + last error), power-
   user override picker in Phase 3.
6. Tests: `tests/engine_router.rs` covering the policy table
   (≥ 8 cases), `tests/singbox_downloader.rs` covering SHA-256
   pass / fail / empty cases, and `tests/singbox_runtime.rs`
   covering start / health-check / restart.

**Risks:**

- sing-box on Windows is a moving target; the macOS side has had
  one Reality regression in the last 6 months. We track sing-box
  releases in CI (Phase B §3 B2.4 `bench.yml` already runs
  nightly) and bump our pin on a quarterly cadence.
- The Phase 1 "status-only" panel adds a small UI surface that
  the user cannot act on. We mitigate by labeling the panel
  "Kernels (read-only — v2.5.0 enables per-protocol switching)"
  and hiding it behind a "Show advanced" toggle by default.
- A buggy `EngineRouter` that always returns the wrong engine
  would be silent — users would see "connection failed" without
  knowing whether mihomo or sing-box handled it. Mitigation:
  `proxy.engine` and `proxy.engine_version` are mandatory fields
  in the diagnostic report (see C5.3 Tauri command `engine_status`)
  and the `proxy.engine` field is logged at `info!` level for
  every outbound connection.

**References:**

- [`0005-proxy-engine-protocol.md`](0005-proxy-engine-protocol.md) —
  the macOS `ProxyEngine` protocol and `EngineRouter.defaultMihomo`
  policy that this ADR mirrors on Windows. **The per-`ProxyKind`
  routing table in this ADR is the Windows projection of that
  table**; any future change to that table must be made in ADR-0005
  and re-stated here.
- [`0006-mihomo-sidecar-version-pin.md`](0006-mihomo-sidecar-version-pin.md)
  — the version-pin policy we apply to sing-box as well (separate
  `SINGBOX_SHA256` constant, same bump cadence).
- [`2026-06-02-d1-singbox-integration.md`](2026-06-02-d1-singbox-integration.md)
  — the macOS ADR that established the sidecar model we are
  copying. The "Risks" and "Two sidecars running at once = +30MB
  RAM" sections of D1 apply verbatim.
- [`../WINDOWS-CATCHUP-PLAN.md`](../WINDOWS-CATCHUP-PLAN.md) §3
  C5 — the implementation plan (1.5 + 1.5 + 0.5 + 1 + 1.5 = 6
  person-days) that this ADR authorises.
- `Sources/Riptide/SingBox/` (directory on disk:
  `Sources/Riptide/SingBox/`) — macOS reference implementation.
  File layout: `SingBoxCore.swift`, `SingBoxConfigGenerator.swift`,
  `SingBoxDownloader.swift`, `SingBoxRuntimeManager.swift`. The
  Windows port mirrors the same four-file split under
  `riptide-windows/src-tauri/src/core/singbox/`.
- `Sources/Riptide/Engines/` (directory on disk:
  `Sources/Riptide/Engines/`) — contains
  `ProxyEngine.swift` and `EngineRouter.swift`, the canonical
  trait shape and policy enum that the Windows
  `core/engines/proxy_engine.rs` and
  `core/engines/engine_router.rs` mirror.
