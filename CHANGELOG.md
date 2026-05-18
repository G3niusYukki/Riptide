# Changelog

All notable changes to Riptide are documented here.

## [2.0.0] - Unified GA across macOS + Windows

First release where the macOS app and the Windows port carry the same
version number, are both built from one tree, and both actually run
end-to-end. The previous "[2.0.0] GA" entry below refers to the macOS
foundation hardening pass; this 2.0.0 elevates the Windows port to the
same standard and re-cuts the release together.

### 🪟 Windows port — first installable release

Everything under `riptide-windows/` was built up across Phase 0–5 over
the past month and is now packaged in a single NSIS + MSI installer:

- **Foundation**: disk-backed profile store with stable UUIDs in
  filenames, persisted active-profile pointer, real `generate_config`
  merge, mihomo binary auto-download (SHA-256 pinned to
  `1ae6eeec…ec15b0f` for v1.18.10), single-instance guard, centralised
  `tracing` logging at `%APPDATA%\Riptide\logs\`.
- **Modes & Service**: TUN via mihomo's gVisor stack, dedicated
  `riptide-tun-service.exe` SCM binary, one-shot UAC elevation for
  install/uninstall, system-proxy drift guard, single-mutex Mode
  Coordinator with `mode_state` events.
- **Subscriptions & Config**: auto-refresh scheduler with per-profile
  intervals, `Subscription-Userinfo` header parsing, GeoIP / GeoSite
  auto-download, DNS policy overlay (DoH/DoT/DoQ + FakeIP), WebDAV
  sync (HTTPS-only, DPAPI-encrypted credentials), clipboard import,
  `riptide://import?...` deep links.
- **Resilience**: graceful degradation watcher distinguishing
  deliberate vs unexpected mihomo exits, opt-in kill switch (blackhole
  route on TUN crash), sleep/wake + network-change recovery with health
  probes, one-button diagnostics report (excludes credentials).
- **Anti-censorship**: one-click China / Iran / Russia region presets,
  global `client-fingerprint` stamping, anonymous Cloudflare WARP
  registration (local Curve25519 keypair → CF API → saved as a mihomo
  `wireguard` profile with derived `reserved` bytes).
- **Node editor**: visual proxy CRUD per profile covering Shadowsocks
  (with shadow-tls / v2ray-plugin / restls plugin options), VMess,
  VLESS (with Reality), Trojan, Hysteria2, TUIC, AnyTLS, Snell, HTTP,
  SOCKS5. Round-trips through `serde_yaml::Value` so unknown profile
  keys survive edits.
- **UX**: light + dark theme (with a CSS override layer so existing
  utilities flip palette without per-component rewrites), 5-language
  i18n (zh-CN, en-US, fa-IR, ru-RU, ja-JP), system tray menu, global
  hotkeys (Ctrl+Alt+P / Ctrl+Alt+M, fault-tolerant when conflicting),
  autostart with `--minimized`, update check.

### 🚧 Build pipeline unblocked

Three latent issues had been silently keeping `tauri build` from
producing real artifacts for weeks (the script exited 0 after the
precheck):

- `@tauri-apps/api` (2.11) was ahead of the Rust `tauri` crate (2.10);
  Cargo refused to bundle when there were two binaries without
  `default-run`; the React tree wasn't wrapped in `QueryClientProvider`
  so the first hook call killed the layout.

All three are fixed and the produced exe boots end-to-end.

### 🧹 Polish

- Sidebar widened to a labelled column with mode indicator at the
  bottom; Header refined with a local-proxy address tag and softer
  status badges; Dashboard cards gained tonal halos and a LIVE pulse
  when traffic is active.
- All Windows data now lives under `%APPDATA%\Riptide\` (previously
  mihomo landed under `%APPDATA%\com.riptide.app\` while logs/profiles
  used the canonical path).

### 🍎 macOS

No behavioural changes from 1.7.0; the macOS app inherits the version
bump so both platforms ship in sync.

---

## [Windows port v1.2.0] - Phase 0–5 build-out

### 🏗️ Foundation (Phase 0)
- **Profile system unified**: removed legacy in-memory `Mutex<Vec<Profile>>` commands; everything now disk-backed with stable UUIDs embedded in filenames (`<name>__<uuid>.yaml`) so IDs survive reloads
- **Active profile persisted** to `%APPDATA%\Riptide\active.json` via atomic write
- **`generate_config` real merge**: `MihomoManager.write_config` now actually injects profile YAML + runtime settings into mihomo's config path before launch (previously dead-code)
- **mihomo auto-download** on first run with SHA-256 verification + progress events
- **Single-instance guard** via `tauri-plugin-single-instance`
- **Centralised logging** through `tracing` + daily rolling file appender

### 🔀 Modes & Service (Phase 1)
- **TUN via mihomo's gVisor stack** (deleted dead `windows_tun.rs` + `wintun` crate dep)
- **Windows service**: new `riptide-tun-service.exe` binary registers with SCM, reads launch config from `%PROGRAMDATA%`, runs mihomo as SYSTEM
- **One-shot UAC elevation**: `ShellExecuteEx(verb=runas)` + `--install-service`/`--uninstall-service` CLI flags
- **System proxy drift guard**: auto-restores Windows proxy settings every 3s when external apps tamper with them
- **Mode Coordinator**: single mutex serializes Off/SystemProxy/TUN transitions, emits `mode_state` events

### 📡 Subscriptions & Configuration (Phase 2)
- **Subscription auto-refresh scheduler** (default 24h, per-profile interval, configurable)
- **`Subscription-Userinfo` header parsing** for traffic/expiry tracking
- **GeoIP / GeoSite auto-download** with progress events
- **DNS policy overlay** (`DnsPolicy`): user-managed DoH/DoT/DoQ nameservers, FakeIP mode, per-domain policy
- **WebDAV sync**: HTTPS-only, Basic Auth, DPAPI-encrypted credential storage; zip backup of profiles + sidecars
- **Clipboard import** with auto-detect for share URI vs subscription URL
- **Deep link** `riptide://import?url=…` / `riptide://import?uri=…`

### 🛡️ Resilience (Phase 3)
- **Graceful degradation**: mihomo crash watcher distinguishes deliberate vs unexpected exits, emits `mihomo_crashed`/`mihomo_exited`
- **Kill switch**: optional blackhole route on TUN crash (`route add 0.0.0.0/0 → 127.0.0.1`), manual release
- **Sleep/wake & network-change recovery**: clock-jump and default-gateway change detection, mihomo health probe, auto-restart on 2 consecutive failures
- **Diagnostics report**: one-button collection of versions/mode/service status/asset state/log tail with explicit exclusions (no profile YAML, no connections, no credentials)

### 🪨 Anti-censorship (Phase 4, partial)
- **Region presets**: China / Iran / Russia one-click rule + DNS overlays
- **TLS tricks**: global `client-fingerprint` stamping (TLS fragment plumbing stubbed)

### 🎨 UX & Release Engineering (Phase 5, partial)
- **Autostart + silent start** with `--minimized` flag handling
- **System tray menu**: show/hide, mode switch, quit
- **Global hotkeys**: `Ctrl+Alt+P` toggle proxy, `Ctrl+Alt+M` cycle modes
- **Theme infrastructure** (light/dark/system preference; visual light theme pending)
- **i18n**: zh-CN + en-US translated, fa-IR/ru-RU/ja-JP seeded with English fallback
- **Update check** with open-in-browser flow
- **Settings page**: tabbed (Network / DNS / Sync / Assets / Recovery / About)

### 🧹 Cleanup
- Deleted `core/windows_tun.rs` (wintun-direct approach abandoned in favor of mihomo TUN)
- All pre-existing build warnings cleared; `cargo check --bins --lib` produces zero warnings

### Known Limitations
- `MIHOMO_SHA256` placeholder must be filled before release tagging
- Full auto-updater requires Tauri signing keypair
- Cloudflare WARP integration deferred (requires WireGuard keygen + CF registration API)
- Node editor UI for Reality / AnyTLS / ShadowTLS / TUIC deferred

## [1.6.0] - TUN Mode UI Unlocked

- **TUN mode UI unlocked**: removed `tunUnavailable` warning block, added start/stop toggle button with keyboard shortcut (Return key) and visual state indicators (cf4b129)
- **TUN fallback guidance**: info message in UI explains sudo-based privilege escalation when helper is not installed (cf4b129)
- **SwiftLint compliance**: resolved trailing newline, vertical whitespace, and line length violations (e6f9dcb)

## [2.0.0] - GA Release

### 🎉 General Availability

Riptide exits Beta with a comprehensive GA push covering foundation hardening,
error unification, XPC maturation, test coverage, and visual editors.

### ✅ Foundation Hardening (P0)

- **Eliminated all force unwraps** — 4 unsafe `.first!` calls replaced with safe fallbacks
  in `MihomoPaths`, `MihomoDownloader`, `AppGroupStateStore`, `ProfileStore`
- **Eliminated all placeholder implementations** — `UDPSessionManager.process()` now forwards
  data through the proxy connection; `WebSocketExternalController.handlePutConfigs()` now
  parses and applies config changes
- **Removed self-import** — `TunnelProviderMessages.swift` no longer imports its own module

### 🔧 Error Handling Unification (P1)

- **New `RiptideError` unified error enum** — covers 17 subsystems with `LocalizedError`
  conformance, Chinese/English descriptions, and recovery suggestions
- **11 error enums with `LocalizedError`** — `TransportError`, `RuntimeError`,
  `CoreManagerError`, `MihomoAPIError`, `ClashConfigError`, `ProfileStoreError`,
  `SubscriptionError`, `SystemProxyError`, `VPNManagerError`, `AppGroupStateStoreError`,
  `NodeValidationError`

### 🔌 XPC Maturation (P1)

- **Automatic reconnection** — exponential backoff (3 attempts) on connection invalidation
  or interruption
- **Heartbeat monitoring** — 30-second periodic health checks with automatic reconnection
- **Timeout protection** — `verifyConnection()` and `fetchHelperVersion()` have 3-second
  timeouts to prevent hangs
- **Version check** — `getHelperVersion()` added to `HelperToolProtocol`; version is fetched
  and stored on connection establishment
- **New error cases** — `ConnectionError.versionMismatch` and `.timedOut`
- **XPC tests** — `HelperToolConnectionTests` covering error types and RiptideError wrapping

### 🧪 Test Coverage (P2)

- **71 new tests** across 5 test suites:
  - `HelperToolConnectionTests` (4) — XPC error types
  - `TUNRoutingEngineTests` (26) — VPN errors, config, PacketHandler, TCP/UDP parsing
  - `UserSpaceTCPTests` (18) — TCP state machine, connection IDs, handshake lifecycle
  - `WebDAVClientTests` (6) — WebDAV error types, file model
  - `ConfigMergerTests` (17) — merge logic, proxy/rule/DNS/group merging

### 🎨 Visual Editors (P2)

- **Node Editor fixes** — `parseProxiesFromYAML` now uses `ClashConfigParser`;
  `generateYAMLWithNode`, `generateUpdatedYAML`, `generateYAMLWithoutNode` now use Yams
  for proper YAML manipulation
- **Rule Editor** (new) — `RuleEditorView` with drag-to-reorder, add/delete rules,
  10 supported rule types, policy picker from available proxies/groups
- **Config Merge UI** (new) — `ConfigMergeView` for managing merge sources (file/manual),
  previewing diffs (added/modified/removed proxies + rule changes), and one-click apply
- **Config Import Preview** (new) — `ConfigImportPreviewView` shows proxy/rule/group counts
  and details before importing; integrated into ConfigTabView's import flow
- **Rule Set Auto-Update** (new) — `RuleSetProvider` lifecycle integrated into `AppViewModel`;
  providers start/stop with profile activation; UI section shows sources with manual refresh

### 📦 Infrastructure

- Added `Yams` dependency to `RiptideApp` target for YAML manipulation
- `Swift 6 concurrency` — ~12 compiler warnings fixed in RiptideApp (NodeEditorViewModel,
  AppViewModel, ConfigDropDelegate, ConfigMerger, SystemProxyGuard, SystemProxyController,
  ModeCoordinator)

### 📋 Known Limitations

- VPN/TUN tests require NetworkExtension (not available in test environment)
- Swift 6 strict concurrency warnings remain in some actor-isolated views
- Deprecated API warnings in `SMJobBlessManager` and `StatusBarController` (fallback paths)
- MITM framework is scaffolded but not production-ready

---

## [1.3.0] - Previous Beta

- mihomo TUN integration with gVisor stack
- SMAppService migration (macOS 13+)
- First-run onboarding wizard
- Atomic mode switching with 500ms cooldown
- TUN auto-recovery with 10-second health monitoring
- System proxy guard with 5-second violation detection
- Subscription auto-update (5-minute interval)
- WebDAV config sync
- 4-language localization (en, zh-Hans, ja, ru)
- Menu bar extra with traffic monitoring
- 491 tests in 76 suites
