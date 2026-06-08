# Windows Platform

Riptide Windows is a Tauri 2 app (React + TypeScript frontend, Rust backend) wrapping the [mihomo](https://github.com/MetaCubeX/mihomo) Clash-YAML proxy core. It ships two binaries:

- **`riptide.exe`** — the Tauri UI app. Runs unelevated as the current user.
- **`riptide-tun-service.exe`** — a minimal Windows service registered with SCM that runs mihomo as `SYSTEM` for unprivileged TUN.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│              Riptide Tauri UI (React + TS)           │
│  Settings · Profiles · Proxies · Logs · Diagnostics  │
└────────────┬──────────────────────────────┬──────────┘
             │ Tauri commands               │ events
             ▼                              ▲
┌──────────────────────────────────────────────────────┐
│            Rust backend (src-tauri/src)              │
│  ┌────────────────────────────────────────────────┐  │
│  │ ModeCoordinator — serialized mode transitions  │  │
│  ├────────────────────────────────────────────────┤  │
│  │ MihomoManager — process lifecycle, watcher,    │  │
│  │   config merge (TUN/DNS/Region/TLS overlays)   │  │
│  ├────────────────────────────────────────────────┤  │
│  │ SystemProxyController (+ drift guard)          │  │
│  │ KillSwitch · RecoveryWatchdog · GeoAssets      │  │
│  │ SubscriptionScheduler · WebDAV · Diagnostics   │  │
│  └────────────────────────────────────────────────┘  │
└────────────┬─────────────────────────────────────────┘
             │ spawn / SCM
             ▼
┌────────────────────────┐    ┌─────────────────────────┐
│   mihomo.exe (sidecar) │    │ riptide-tun-service.exe │
│   REST API :9090       │◄───┤ (Windows service, SYSTEM)│
└────────────────────────┘    └─────────────────────────┘
```

## SCM-Registered TUN Service

The TUN service (`riptide-tun-service.exe`) is a proper Windows service registered with the Service Control Manager. It runs mihomo as `SYSTEM` so the TUN interface works without per-launch UAC prompts.

### Lifecycle

1. **Install** — `riptide.exe --install-service` triggers `ShellExecuteEx(verb=runas)` for one-time UAC elevation. The binary copies itself to `%PROGRAMDATA%\Riptide\` and registers the `RiptideTUN` service via SCM.
2. **Configuration** — the service reads `%PROGRAMDATA%\Riptide\service.conf` for launch parameters.
3. **Runtime** — the service spawns `mihomo.exe` with the generated config, monitors the process, and reports status back to the UI via named pipe / Tauri events.
4. **Uninstall** — `riptide.exe --uninstall-service` (elevated) stops and removes the SCM registration.

::: tip
The UI itself never needs admin rights. Only the one-time service install requires UAC approval.
:::

## Kill Switch

The kill switch prevents traffic leaks when TUN mode is active and mihomo crashes or stops unexpectedly.

### How it works

When enabled and a mihomo crash is detected (distinct from a deliberate exit):

1. A `0.0.0.0/0 → 127.0.0.1` blackhole route is installed in the Windows routing table.
2. All outbound traffic is silently dropped — no DNS, no HTTP, nothing leaks.
3. The `kill_switch_armed` event is emitted to the UI.
4. The user must manually release the kill switch via the UI (`kill_switch_release` command).

### Configuration

- Opt-in: enable via Settings → Network → Kill Switch, or set `kill_switch.json`.
- The `get_kill_switch_state` / `set_kill_switch_enabled` commands manage persistence.
- On TUN crash, the system distinguishes `mihomo_crashed` (unexpected) from `mihomo_exited` (user-initiated stop) — the kill switch only arms on the former.

## Recovery Watchdog

The recovery watchdog handles two Windows-specific failure modes:

### Sleep/wake detection

When the system resumes from sleep, the watchdog detects the clock jump and health-probes mihomo. After 2 consecutive failures, it automatically restarts the proxy.

### Network change detection

When the default gateway changes (Wi-Fi → Ethernet, VPN connect/disconnect, network adapter reset), the watchdog triggers a health probe and restart cycle.

### Events

| Event | Meaning |
|---|---|
| `recovery_health_ok` | Health probe succeeded — mihomo is alive |
| `recovery_restarted` | Watchdog restarted mihomo after consecutive failures |
| `recovery_failed` | Restart attempts exhausted — manual intervention needed |

## Gateway / ICS Mode

Riptide can share its proxy connection with other devices on the local network via Windows Internet Connection Sharing (ICS). This is useful for:

- Routing a phone or tablet through the PC's proxy
- Sharing a VPN/proxy connection with IoT devices
- Testing from a VM or container that can't run its own proxy client

Enable via Settings → Network → Gateway.

## WARP Integration

Riptide supports Cloudflare WARP as an anonymous proxy transport:

- **Registration** — automatic x25519 keypair generation and anonymous WARP account registration via the Cloudflare API.
- **Configuration** — WireGuard config is generated and injected into mihomo's proxy chain.
- **Region presets** — CN/Iran/Russia presets can route WARP traffic through specific endpoints.

::: warning
WARP integration is currently in Phase 4 (partial). Full WireGuard keypair management and Cloudflare API integration are deferred.
:::

## Region Presets

One-click region presets apply curated rule + DNS overlays for users in censored regions:

| Preset | Rules | DNS |
|---|---|---|
| **China** | Direct domestic, proxy international | DoH to non-polluted resolvers |
| **Iran** | Direct domestic, proxy international | DoH with fallback |
| **Russia** | Direct domestic, proxy international | DoH with fallback |

Presets are stored in `region_preset.json` and applied as overlays on top of the active profile's YAML. They never modify the original profile file.

## TLS Tricks

Anti-censorship TLS features:

- **Client fingerprint stamping** — global `client-fingerprint` field injected into mihomo config. Options: `chrome`, `firefox`, `safari`, `random`.
- **TLS fragment plumbing** — stubbed pending mihomo build verification.

Stored in `tls_tricks.json`. Applied as config overlay, not profile mutation.

## System Proxy Drift Guard

Windows system proxy settings are volatile — apps like Spotify, OneDrive, and various "optimizers" silently reset the WinHTTP proxy. Riptide's drift guard:

1. **Polls** the system proxy every 3 seconds.
2. **Compares** the current value against the expected Riptide-managed settings.
3. **Auto-restores** if drift is detected.
4. **Emits** `system_proxy_drift` events with `{ observed, expected, reapply_count, gave_up }`.
5. **Gives up** after a configurable number of reapplications to avoid infinite loops with aggressive proxy-resetting software.

Tunable in Settings → Network.

## DPAPI-Encrypted WebDAV Credentials

WebDAV sync stores credentials using Windows DPAPI (Data Protection API):

- Passwords are encrypted with the current user's credentials — only decryptable by the same user on the same machine.
- Stored in `webdav_config.json` alongside the WebDAV endpoint URL.
- HTTPS-only connections enforced — no plaintext HTTP to WebDAV servers.
- Backup contents: profiles + sidecars + DNS policy, packaged as a zip.

## DELAYLOAD comctl32 Fix

Test binaries built without a manifest may fail to load `comctl32.dll` v6 (required by some Tauri/Windows API calls). The project uses a `DELAYLOAD` linker directive for `comctl32` in test builds, ensuring test binaries don't crash on import resolution in headless CI environments.

This is transparent to end users — it only affects `cargo test` runs in CI.
