# Riptide Windows

A native Windows proxy client built on **Tauri + React + TypeScript + Rust**. Wraps the [mihomo](https://github.com/MetaCubeX/mihomo) proxy core with a modern UI, subscription management, system proxy / TUN modes, recovery automation, and WebDAV sync.

> **Status**: Phase 0–3 complete, Phase 4–5 partially landed. See [Phase Status](#phase-status) below.

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

Two binaries ship:
- `riptide.exe` — Tauri UI
- `riptide-tun-service.exe` — minimal Windows service that runs mihomo as SYSTEM for unprivileged TUN

## Features

### Phase 0 — Foundation
- **Profile system** unified on disk-backed storage with stable UUIDs embedded in filenames; metadata sidecar (`.meta.json`) tracks subscription URL, refresh interval, last update, and traffic/expiry from `Subscription-Userinfo` headers
- **Active profile** persisted to `active.json`; survives restarts
- **mihomo config generation** merges profile YAML with runtime settings (mixed-port, external-controller, log-level, ipv6, TUN, DNS overlays)
- **mihomo binary auto-download** on first launch (SHA-256 verified) with progress events
- **Single-instance guard** — second launch focuses existing window
- **Centralised logging** via `tracing` + daily rolling file at `%APPDATA%\Riptide\logs\riptide.log`

### Phase 1 — Modes & Service
- **TUN mode** via mihomo's gVisor stack (no custom wintun driver); `tun:` block injected on demand
- **Windows service** (`RiptideTUN`): `riptide-tun-service.exe` registered with SCM, reads `%PROGRAMDATA%\Riptide\service.conf`, runs mihomo as SYSTEM
- **One-shot UAC elevation** via `ShellExecuteEx(verb=runas)` + CLI flags (`--install-service` / `--uninstall-service`); UI itself stays unelevated
- **System proxy guard** — 3-second drift detector that auto-restores Windows proxy settings when external apps change them
- **Mode Coordinator** — single `Mutex<AppMode>` serializes Off / SystemProxy / TUN transitions, emits `mode_state` events

### Phase 2 — Configuration & Subscriptions
- **Subscription auto-update scheduler** (default 24h, per-profile interval)
- **Subscription-Userinfo header parsing** (upload/download/total/expire)
- **GeoIP / GeoSite** automatic download to `%APPDATA%\Riptide\` (geoip.metadb, geosite.dat)
- **DNS policy overlay** (`DnsPolicy`): user-managed DoH/DoT/DoQ nameservers, FakeIP mode, per-domain policy, applied on top of profile YAML
- **WebDAV sync** — HTTPS-only, Basic Auth, password DPAPI-encrypted; uploads zip backup of profiles + sidecars + DNS policy
- **Clipboard import** — auto-detect ss/vmess/vless/trojan/hysteria2/tuic URI or subscription URL
- **Deep link** — `riptide://import?url=...` / `riptide://import?uri=...`

### Phase 3 — Resilience
- **Graceful degradation** — mihomo crash watcher emits `mihomo_crashed` (vs deliberate `mihomo_exited`)
- **Kill switch** — installs `0.0.0.0/0 → 127.0.0.1` blackhole route on TUN crash (opt-in); manual release via UI
- **Sleep/wake & network-change recovery** — `recovery_watchdog` detects clock jumps and default-gateway changes, health-probes mihomo, restarts after 2 consecutive failures
- **Diagnostics report** — one-button collection: Riptide/mihomo versions, mode, TUN service status, kill switch, geo asset state, log tail; explicitly **excludes** profile YAML, active connections, WebDAV credentials

### Phase 4 — Anti-censorship (partial)
- **Region presets** — China / Iran / Russia one-click rule + DNS overlays
- **TLS tricks (partial)** — global `client-fingerprint` stamping; TLS fragment plumbing stubbed pending mihomo build verification
- **WARP integration** — deferred (requires WireGuard keypair + Cloudflare API)
- **AnyTLS / ShadowTLS / TUIC node editor UI** — deferred pending node editor work

### Phase 5 — UX & Release (partial)
- **Autostart + silent start** — `tauri-plugin-autostart` wired; `--minimized` flag hides window on launch
- **System tray menu** — show/hide window, mode switch, quit
- **Global hotkeys** — `Ctrl+Alt+P` toggle proxy, `Ctrl+Alt+M` cycle modes; emit Tauri events handled in App.tsx
- **Theme infrastructure** — light/dark/system preference plumbed; full light styling pending
- **i18n** — zh-CN, en-US fully translated; fa-IR, ru-RU, ja-JP seeded with English fallback
- **Update check** — GitHub Releases API + open download in browser (full auto-installer deferred; requires signing keypair)
- **NSIS installer** — deferred (already in `tauri.conf.json` bundle targets)

## Build & Run

Requirements:
- Node.js 20+
- Rust 1.75+
- Windows 10+ with WebView2 (modern Windows ships it; older needs the bootstrapper, which `tauri.conf.json` is configured to auto-install)

```bash
cd riptide-windows
npm install
npm run tauri dev      # dev mode
npm run tauri build    # production build → src-tauri/target/release/bundle/
```

Two binaries are produced:
- `riptide.exe` — main UI
- `riptide-tun-service.exe` — service wrapper for TUN

## Configuration directories

```
%APPDATA%\Riptide\                    # user-scope state
├── profiles\
│   ├── <name>__<uuid>.yaml           # profile YAML
│   └── <name>__<uuid>.meta.json      # sidecar metadata
├── active.json                       # selected profile id
├── dns_policy.json                   # DNS overrides
├── region_preset.json
├── tls_tricks.json
├── kill_switch.json
├── webdav_config.json                # DPAPI-encrypted password
├── mihomo\
│   ├── mihomo.exe
│   └── config.yaml                   # generated, do not edit
├── logs\
│   └── riptide.log.<date>
└── geoip.metadb / geosite.dat

%PROGRAMDATA%\Riptide\                # machine-scope (SYSTEM-readable)
└── service.conf                      # service launch params
```

## Tauri commands

The frontend talks to Rust through `services/tauri.ts` wrappers. Notable invokeable commands:

| Category | Commands |
|----------|----------|
| **Modes** | `mode_current`, `mode_switch_to_system_proxy`, `mode_switch_to_tun`, `mode_switch_off` |
| **Profiles** | `list_profiles`, `create_profile`, `update_profile`, `delete_profile`, `import_profile_from_url`, `import_share_uri`, `import_profile_from_file`, `export_profile`, `validate_config`, `get_active_profile`, `set_active_profile`, `refresh_profile`, `set_profile_subscription`, `get_profile_metadata` |
| **TUN service** | `install_tun_service`, `uninstall_tun_service`, `start_tun_service`, `stop_tun_service`, `get_tun_service_status`, `is_elevated` |
| **TUN mode** | `start_tun_mode`, `stop_tun_mode`, `get_tun_status`, `set_tun_options`, `get_tun_options` |
| **DNS** | `get_dns_policy`, `set_dns_policy` |
| **Geo assets** | `get_geo_assets`, `download_geo_assets` |
| **WebDAV** | `webdav_get_config`, `webdav_set_config`, `webdav_test_connection`, `webdav_backup_now`, `webdav_restore_now` |
| **Kill switch** | `get_kill_switch_state`, `set_kill_switch_enabled`, `kill_switch_release` |
| **Region/TLS** | `get_region_preset`, `set_region_preset`, `get_tls_tricks`, `set_tls_tricks` |
| **Diagnostics** | `collect_diagnostic_report` |
| **Lifecycle** | `download_mihomo`, `check_update`, `start_proxy`, `stop_proxy`, `restart_proxy` |

## Events emitted to the UI

| Event | Payload | Triggered by |
|-------|---------|--------------|
| `mode_state` | `{ mode, transitioning, error? }` | Mode coordinator transitions |
| `system_proxy_drift` | `{ observed, expected, reapply_count, gave_up }` | Drift guard |
| `mihomo_crashed` / `mihomo_exited` | `{ exit_code, mode }` | Process watcher |
| `mihomo_bootstrap_progress` | `{ stage, downloaded_bytes, total_bytes, message }` | Binary downloader |
| `geo_asset_progress` | `{ asset, downloaded_bytes, total_bytes, done }` | Geo asset downloader |
| `profile_refreshed` / `profile_refresh_error` | `{ profile_id, ... }` | Subscription scheduler |
| `recovery_health_ok` / `recovery_restarted` / `recovery_failed` | `{ reason, restarted }` | Recovery watchdog |
| `kill_switch_armed` | `()` | mihomo crash in TUN with kill switch enabled |
| `hotkey-toggle-proxy` / `hotkey-toggle-mode` | `()` | Global hotkeys |

## Release-blocking TODOs

- `MIHOMO_SHA256` in `core/mihomo_bootstrap.rs` is empty — fill before tagging a release
- Auto-updater requires a Tauri signing keypair to be generated and pinned in `tauri.conf.json`
- 4.2 WARP and 4.4 protocol-specific node editor UI are deferred

## License

Same as upstream Riptide (TBD).
