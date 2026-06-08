# ADR-0010: Windows sing-box integration path

> **Status:** Accepted · **Date:** 2026-06-08 · **Deciders:** maintainers

## Context

macOS Riptide has two proxy engines: a pure-Swift in-process proxy
engine (for HTTP CONNECT, SOCKS5, and Shadowsocks) and a mihomo sidecar
(for everything else). Windows has only mihomo — the pure-Swift engine
has no Windows counterpart, and no Rust equivalent is planned.

v2.5.0 requires **sing-box** for protocols that mihomo either does not
implement or implements with lagging parity:

- **VLESS + Reality** — sing-box's Reality implementation leads mihomo's
  by several months on uTLS profile parity and XTLS-vision splice.
- **AnyTLS** — stable in sing-box, experimental in mihomo.
- **WireGuard-as-proxy** (WARP-style) — sing-box has a first-class
  WireGuard outbound; mihomo does not.
- **ShadowTLS v3**, **TUIC v5** with port hopping, **uTLS fingerprint
  fine-tuning** — all sing-box-first.

ADR-0007 (`0007-windows-kernel-router.md`) already decided the
**shape** — two-kernel sidecar model with an `EngineRouter` — but did
not commit to the concrete integration path for the sing-box binary
itself. This ADR closes that gap.

## Decision

**sing-box runs as a second sidecar process alongside mihomo, managed
by the same lifecycle pattern.** The `EngineRouter` dispatches to
either `MihomoEngine` or `SingBoxEngine` based on the active
`EnginePolicy` and the `ProxyKind` of the selected node.

### Binary management

The sing-box binary is downloaded from GitHub releases (the same
pattern `core/mihomo_bootstrap.rs` uses for mihomo):

- **Source**: `https://github.com/SagerNet/sing-box/releases/download/v{VERSION}/sing-box-{VERSION}-windows-amd64.zip`
- **Version pin**: `SINGBOX_VERSION = "1.13.0"` (the version macOS
  already validated in `Sources/Riptide/SingBox/SingBoxDownloader.swift`).
- **SHA-256 verification**: `SINGBOX_SHA256` constant, same pattern as
  `MIHOMO_SHA256` in `core/mihomo_bootstrap.rs`. Empty string disables
  verification (dev-only, release-blocking).
- **Storage location**: `%APPDATA%\Riptide\singbox\singbox.exe` (user
  scope) or `%PROGRAMDATA%\Riptide\singbox\singbox.exe` (machine scope
  for the SCM service). The path is resolved by
  `WindowsDirs::singbox_dir()` in `core/singbox/paths.rs`.
- **Download trigger**: lazy — the binary is fetched the first time a
  Reality or AnyTLS node is selected, not on app launch. This avoids
  +12 MB of download for users who never use these protocols.

### Runtime lifecycle

`SingBoxRuntimeManager` follows the same lifecycle as
`MihomoRuntimeManager` (`core/mihomo_manager.rs`):

1. **Start**: spawn `singbox.exe run -c <generated-config>.json` as a
   child process. Bind REST API on `127.0.0.1:9091` (distinct from
   mihomo's `9090`). Wait for health check (`GET /`) with a 10-second
   timeout.
2. **Health check**: poll `GET /` every 30 seconds. If 3 consecutive
   checks fail, restart the process.
3. **Stop**: send `POST /stop` (graceful), wait 5 seconds, then
   `TerminateProcess` if still alive.
4. **Crash recovery**: if the process exits unexpectedly, restart
   automatically with exponential backoff (1s, 2s, 4s, max 30s). Log
   the exit code and stderr output.

### Config generation

`SingBoxConfigGenerator` (in `core/singbox/config_generator.rs`) converts
a Riptide `ProxyNode` into a sing-box JSON config. The generator is
independent from `MihomoConfigGenerator` — the two config schemas
diverge enough that a unified generator is not worth the complexity
(see ADR-0007 "Forecloses").

The generator produces:

```json
{
  "inbounds": [
    { "type": "mixed", "listen": "127.0.0.1", "listen_port": <port> }
  ],
  "outbounds": [
    { "type": "vless", "server": "...", "tls": { "reality": { ... } } },
    { "type": "direct", "tag": "direct" }
  ],
  "route": { "rules": [...], "final": "proxy" }
}
```

The outbound type and fields are determined by `ProxyKind`:

| `ProxyKind` | sing-box outbound type |
|---|---|
| `reality` | `vless` with `tls.reality` |
| `anytls` | `trojan` with `tls.anytls` |
| `wireguard` | `wireguard` |

All other `ProxyKind` values are routed to mihomo (see ADR-0007
routing table).

### Engine routing

`EngineRouter` (already defined in ADR-0007) picks the engine:

- `EnginePolicy::DefaultMihomo` — all traffic to mihomo (Phase 1
  default).
- `EnginePolicy::Auto` — Reality/AnyTLS to sing-box, everything else
  to mihomo (Phase 3 default).
- `EnginePolicy::ForceMihomo` / `EnginePolicy::ForceSingBox` —
  power-user overrides (Phase 3).

### Phase rollout

The rollout follows ADR-0007's three-phase plan:

- **Phase 1**: sing-box binary is downloaded and verified, but no
  traffic is routed through it. The `Settings → Kernels` panel shows
  sing-box as "installed, idle".
- **Phase 2**: when a user profile contains a Reality or AnyTLS node,
  the router transparently dispatches to sing-box. A "via sing-box"
  badge appears on the node.
- **Phase 3**: default policy becomes `Auto`. Power-user override
  picker in `Settings → Kernels`.

## Consequences

**Enables:**

- v2.5.0 Reality / AnyTLS / WireGuard-as-proxy on Windows, in the
  same release cycle as macOS and iOS.
- A single `EngineRouter` abstraction that makes adding future engines
  (e.g. a hypothetical pure-Rust kernel) a drop-in change.
- Lazy download — users who never use sing-box protocols never
  download the binary.
- SHA-256 verification on every download, preventing supply-chain
  tampering.

**Costs and trade-offs:**

- **Two binaries to manage.** mihomo and sing-box must both be
  downloaded, verified, updated, and cleaned up. The download/verify
  logic is duplicated (once for mihomo, once for sing-box). Mitigated
  by extracting a shared `SidecarDownloader` trait in a follow-up
  refactor (out of scope for v2.5.0).
- **+20-30 MB RAM when both kernels run concurrently.** Mitigated by
  lazy-starting sing-box (only when a Reality/AnyTLS node is selected)
  and stopping it after 5 minutes of idle.
- **+12-15 MB installer size** (sing-box binary compressed). Acceptable:
  the current NSIS bundle is ~28 MB.
- **Config generation must produce the right format for each engine.**
  Two independent generators (`MihomoConfigGenerator` and
  `SingBoxConfigGenerator`) must stay in sync on shared semantics
  (route rules, DNS config, geoip/geosite). A config-generation bug
  in one engine is invisible to the other engine's tests.
- **A second SHA-256 pin to maintain.** `SINGBOX_SHA256` in
  `core/singbox/downloader.rs` must be updated on every sing-box
  release bump, same as `MIHOMO_SHA256`. Forgetting to update it
  blocks the release (the empty-string check catches this).

**Forecloses (for now):**

- We do **not** statically link sing-box into `riptide.exe`. The
  sidecar model keeps the build pipeline simple (one Rust toolchain,
  two sidecar binaries, no FFI/cgo).
- We do **not** use a single unified config generator for both
  engines. The schemas are too different (Clash YAML vs sing-box JSON)
  and a unified generator would be more complex than two separate ones.
- We do **not** ship a Windows-only custom WireGuard kernel. All
  WARP-style traffic goes through sing-box's built-in WireGuard
  outbound.

**Follow-up actions (tracked under §3 C5 of the catchup plan):**

1. `core/singbox/paths.rs` — `WindowsDirs::singbox_dir()` returning
   `%APPDATA%\Riptide\singbox\` and the machine-scope equivalent.
2. `core/singbox/downloader.rs` — port SHA-256 + GitHub release fetch
   from `core/mihomo_bootstrap.rs`. Pin v1.13.0.
3. `core/singbox/config_generator.rs` — Clash `ProxyKind` → sing-box
   JSON outbound, mirroring macOS
   `Sources/Riptide/SingBox/SingBoxConfigGenerator.swift`.
4. `core/singbox/runtime_manager.rs` — process lifecycle (start /
   health-check / restart), same shape as `MihomoManager`.
5. `core/singbox/api_client.rs` — sing-box REST surface on port 9091.
6. `core/engines/engine_router.rs` — policy dispatch per ADR-0007
   routing table.
7. Tests: `tests/singbox_downloader.rs` (SHA-256 pass/fail/empty),
   `tests/singbox_config_generator.rs` (each `ProxyKind` → JSON),
   `tests/singbox_runtime.rs` (start/health-check/restart),
   `tests/engine_router.rs` (policy table, ≥ 8 cases).

**References:**

- ADR-0005 (`0005-proxy-engine-protocol.md`) — macOS `ProxyEngine`
  protocol and `EngineRouter` policy enum that this ADR mirrors.
- ADR-0006 (`0006-mihomo-sidecar-version-pin.md`) — version-pin
  policy applied to sing-box as well.
- ADR-0007 (`0007-windows-kernel-router.md`) — the two-kernel router
  architecture this ADR implements.
- macOS sing-box integration:
  [`2026-06-02-d1-singbox-integration.md`](2026-06-02-d1-singbox-integration.md)
  — the sidecar model we are copying.
- [`../WINDOWS-CATCHUP-PLAN.md`](../WINDOWS-CATCHUP-PLAN.md) §3 C5
  — implementation plan (6 person-days).
