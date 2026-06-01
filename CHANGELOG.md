# Changelog

## [3.0.0-dev] — Unreleased

> **Status:** In progress. Plans 06 (UI tests), 07 (macOS native integration), and
> 09 (cleanup & scoping) are merged. Plan 08 (network intelligence) and Plan 10
> are pending — items from those plans are **not** listed here until they land.
> This entry will be promoted to a final `3.0.0` GA tag once those plans ship
> and the cut-over passes `swift test` clean.

### Changed

- **Platform scope clarified:** iOS support is **out of scope for v3.0.0**.
  `RiptideApp_iOS` and `RiptideTunnel_iOS` stubs are archived under
  `docs/_archive/riptide-ios-stub/`. Windows (Tauri) ships alongside macOS
  releases; Linux is built by CI but not yet packaged.
- **Dead-code directories archived** to `docs/_archive/`:
  - `RiptideCore` (Go bridge scaffolding)
  - `RiptideGo` (experimental Go runtime)
  - `RiptideMac` (legacy macOS shell)
  - `AppExtensions` (unbuilt target)
- **Build hygiene:** removed obsolete `Package.swift.next`; added
  `Riptide.entitlements` (code-signing + App Sandbox) for the macOS app target.
- **Repository hygiene:** added common AI-tool artifact patterns to `.gitignore`.

### Added

#### Plan 06 — UI test coverage

- New `RiptideAppUITests` target with shared a11y identifiers and harness
  (`RiptideUITestCase`, `UITestHarness`).
- **38 UI tests across 11 suites** (was 0 before this plan):
  - `LaunchTests` — app launches, dashboard is default tab, all 5 tabs present
  - `DashboardSnapshotTests` — dashboard cards, diagnostics sheet trigger, mode card
  - `ConfigImportTests` — import button, subscription button, file picker
  - `ProxyTabTests` — group cards, latency button, node selection
  - `ConnectionTests` — traffic chart, connection list / empty state
  - `LogViewerTests` — all controls visible, search field accepts input
  - `LaunchAgentTests` — launch-at-login toggle exists and is tappable
  - `URLSchemeTests` — `riptide://` parser for switch-group / select-node / mode / import / diagnostics / unknown host
  - `TouchBarTests` — `makeTouchBar()` shape, customization identifier, delegate materialization
  - `MenuBarPopoverTests` — status item present, popover toggles, contains all sections
- CI: new `ui-tests` job in `.github/workflows/ci.yml` with single-retry on flake.

#### Plan 07 — macOS native integration

- `LaunchAgentManager` — `~/Library/LaunchAgents/com.riptide.client.plist` install /
  remove; `LaunchAtLoginToggle` view in Settings.
- `riptide://` URL scheme registered in `Info.plist` (CFBundleURLTypes) and
  routed via `URLRouter` (switch-group, select-node, set-mode, import-subscription,
  diagnostics, open-config).
- `TouchBarController` with `NSTouchBarDelegate` for node switching on Touch Bar
  MacBook Pros; `groupScrubber` segment + per-group popup.
- `StatusBarController` refactored from raw `NSMenu` to `NSPopover` hosting a
  SwiftUI `MenuBarPopoverView` (mode card, group card, speed card, shortcuts card).
- `NotificationCenterSpeedWidget` — `WidgetKit` scaffold (timeline provider
  rendering `MenuBarPopoverView` snapshot) for Notification Center live-speed
  widget. **Scaffolded; widget extension target not yet built.**
- `NotificationManager` — `UNUserNotificationCenter` wrapper for runtime
  alerts (helper install, mode switch errors, subscription expiry, config
  reload).
- `QuickLookPreview` — Finder Quick Look generator for `.yaml` / `.yml` Clash
  configs (renders sanitized YAML preview). **Scaffolded; generator extension
  target not yet built.**
- Additional UI tests for Touch Bar and menu bar popover (subsumed into the
  Plan 06 suite count above).

---

## [2.2.0] — 2026-05-29

> Version bumped in `3d9fdef`. CHANGELOG entry was never written — backfilling
> it here from git history. All items below are sourced from the v2.2 plan
> delivery commit (`937006e`) and the post-bump build fixups.

### Added

#### M1 — Open-source foundation

- `CONTRIBUTING.md` — contribution guide, dev setup, PR conventions.
- VitePress documentation site under `site/` (config-format, development,
  getting-started, mitm, rule-engine guides; deployed by
  `.github/workflows/deploy-docs.yml`).
- Rule repository under `rules/` with bundled rule-sets:
  `apple-services`, `cn-domain`, `geoip-cn`, `reject-ads`, plus `index.yaml`
  registry; surfaced in-app via `RuleMarketView`.

#### M2 — Dashboard & diagnostics

- `DiagnosticsRunner` — TCP-ping, DNS-leak, and MITM checks on top of the
  existing 6-check one-click diagnostics.
- `ConnectionListView` enhancements — filtering, sorting, waterfall view in
  `ConnectionDetailView`.

#### M3 — iOS skeleton & WireGuard (later scoped out)

- `RiptideApp_iOS` SwiftUI stub and `RiptideTunnel_iOS` `PacketTunnelProvider`
  scaffold (both **archived in v3.0.0-dev**, see above).
- `WireGuardConfig` / `WireGuardCrypto` / `WireGuardHandshake` /
  `WireGuardStream` — Noise IK + ChaCha20-Poly1305 implementation in pure
  Swift. **Removed in the v2.2.0 build-fixup pass** (`2282548`) because it
  did not compile cleanly under the Swift 6 toolchain at the time; the
  mihomo/sing-box sidecar remains the production WireGuard backend.

#### M4 — Linux platform & scene / per-app routing

- Linux Tauri platform modules: `tun_linux.rs`, `sysproxy_linux.rs`,
  `tray_linux.rs`, `autostart_linux.rs` under
  `riptide-windows/src-tauri/src/platform/`.
- `SceneEditorView` — visual editor for rule scenes (process / domain / IP-set
  matchers with mode override).
- `PerAppRuleEditor` — per-application routing rules (app bundle ID → proxy
  group) surfaced in the Rules tab.
- CI: new `linux-check` job in `.github/workflows/ci.yml`; Linux build wired
  into `.github/workflows/release.yml`.

### Fixed (post-bump build fixups, all between 937006e and 3d9fdef)

- Swift build — stub `ProxyConnector`, fix `fd_set` use, remove uncompiling
  WireGuard (see M3 above).
- Linux cross-compile — `WindowsDirs` made cross-platform,
  `creation_flags` → `no_window`, `#[cfg]` guards on platform-gated code.
- Linux `tun_linux` — restored real implementation with `tokio-tun`
  dependency after the temporary stub pass.
- Linux `cli` — add `OneShotResult::Exit` variant, gate `warp.rs` storage
  config, clone `system.rs` for the platform stub.
- Windows — resolve TypeScript build errors (unused imports, missing store
  prop, `RecoveryTab` props); use flat `RewriteAction` struct to avoid serde
  enum mismatch; `WindowsDirs::config_dir()` in `rewrite.rs`; gate gateway
  commands with `#[cfg(windows)]`; add Tauri commands to
  `services/tauri.ts`.
- CI — switch to `macos-15` + Xcode latest (drop `setup-swift` step); add
  `swift --version` debug step; temporarily disable Sparkle to isolate
  macOS build failure.

---

## [2.1.0] — 2026-05-27

### Added

#### Daily Usability
- **Dashboard home page** — status cards (mode / node / speed), subscription quota bar with expiry countdown, recent connections list
- **Connection detail panel** — expandable inline detail with 5-tuple addressing, rule hit tracing, proxy chain visualization, traffic + timing stats
- **Subscription quota display** — parse `subscription-userinfo` HTTP header, show traffic bar + expiry countdown with 72h notification

#### DNS & Routing
- **Nameserver-policy DNS** — per-domain DNS resolver routing (e.g. `geosite:cn` → domestic DNS, default → DoH), supports Clash YAML `nameserver-policy` section
- DNSPipeline extended with `resolveNameserverPolicy()` for per-domain resolver selection

#### Configuration & Management
- **HTTP Rewrite engine** — URL regex-based reject / redirect / header-modify rules (Surge-compatible format), with CRUD UI in Settings
- **Config backup rotation** — 20-backup history in ConfigTabView, auto-backup on profile switch
- **Merge profile UX** — add merge sources, preview diffs, one-click apply (ConfigMergeView)

#### System Integration
- **One-click diagnostics** — 6 checks: helper installation, core binary availability, network connectivity, DNS resolution, proxy port listening, config integrity
- **Sparkle 2.9.2 auto-update** — Cmd+Shift+U menu item, UpdateSettingsView with channel selection
- **WiFi SSID auto-switch** — NetworkEnvironmentManager with CoreWLAN, auto-switches proxy mode + profile when joining different networks
- **Gateway mode backend** — GatewayEnabler: sysctl IP forwarding, pfctl NAT, bootpd DHCP configuration
- **Apple Shortcuts Intents** — SwitchProxyMode + SelectProfile discoverable in Shortcuts.app

#### MITM
- **MITM settings UI** — CA certificate download/install, host whitelist CRUD, exclude list, interception log
- HTTPRewriteEngine integrated with MITM pipeline

#### Surge JS Scripting
- **SurgeScriptBridge** — inject `$request`, `$response`, `$done`, `$persistentStore`, `$notification` into JavaScriptCore context for Surge-compatible script execution

#### Internationalization
- **10 languages** — en / zh-Hans / ja / ru / es + **new** ko / fa / pt-BR / vi + system auto-detect
- Language picker in Settings

#### UI / UX
- **Settings tab** — unified settings container with navigation to all sub-settings (Network, MITM, Rewrite, Updates, Core, Diagnostics, WebDAV, Language, Theme)
- **Theme switching** — System / Light / Dark with segmented picker; text colors use `Color.primary` for auto-adaptation; gradient background adapts to color scheme
- ConnectionListView: tap-to-expand rows with `ConnectionDetailView`

### Changed
- `ConnectionInfo` (MihomoAPIClient) extended with `rule`, `rulePayload`, `start`, `sourcePort`, `destinationPort` fields
- `ConnectionMetadata` extended with `sourcePort`, `destinationPort`
- `ModeCoordinator.getConnections()` now returns full `ConnectionInfo` structs instead of reduced tuples
- `ProxyMode` enum now conforms to `Codable`
- `SubscriptionUpdate` carries optional `SubscriptionUserinfo`
- `Subscription` model stores `SubscriptionUserinfo`

### Fixed
- SystemProxyControllerTests updated for new `ConnectionInfo.metadata.host` structure

---

## [2.0.0] — 2026-03

### Initial Release
- SwiftUI macOS app with 5 tabs (Config, Proxy, Traffic, Rules, Logs)
- Clash YAML config parsing + subscription management
- Protocol support: SS AEAD, VMess, VLESS, Trojan, Hysteria2, Snell, TUIC, SOCKS5, HTTP CONNECT, WireGuard (via sidecar)
- DNS: UDP, TCP, DoH, DoT, DoQ, FakeIP, Cache
- Rule engine: 15 rule types + GEOIP/GEOSITE/RULE-SET/SCRIPT
- Proxy groups: select, url-test, fallback, load-balance, relay
- TUN mode via mihomo sidecar
- mihomo + sing-box multi-core architecture
- WebDAV config sync
- Node editor + rule editor
- Menu bar extra with status + speed
- Global hotkeys
- Onboarding wizard
- 4 languages (en, zh-Hans, ja, ru)
