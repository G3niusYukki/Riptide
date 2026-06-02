# Changelog

## [2.3.0] — 2026-06-02

> **Status:** Released. 16 commits since v2.2.0. CI green (SwiftLint + Swift
> Build & Test + SwiftUI UI Tests + Windows Rust + Frontend tsc + Linux cargo).
> 560 tests / 88 suites passing.

### Added

- **Override (覆写) data model + storage** — new `Sources/Riptide/Override/`
  package: `Override` value type, `OverrideStore` actor (file-backed
  JSON sidecar + per-override `<UUID>.yaml`), `OverrideMerger` enum
  with `meta.replace` / `removed:` semantics, and `OverrideApplyError`.
  18-test suite in `ProxyURISerializerTests` covers the merge edge cases.
  Companion to the user-facing Override feature (UI is W3 territory;
  this commit ships the data layer).
- **Decision ADRs (SP-1 sub-week decisions)** — three lightweight ADRs
  in `docs/decisions/` that gate future P0 work:
  - D1: sing-box integration route (sidecar process)
  - D2: Override schema (YAML-on-YAML overlay, Stash-style)
  - D3: Service Mode route (SMAppService.daemon)
- **Visual rule editor hit preview** — `TargetStrip` (6 TextFields
  bound to `RuleTarget`) + `PolicyBadge` (resolved policy capsule)
  added to `RuleEditorView`. The user can type a domain/IP/port/process
  and see which rule matches + the resolved `RoutingPolicy`. Pure view
  change, no new tests (UI-only prototype).
- **Node QR code (W3-1)** — `ProxyURISerializer` (new) generates
  industry-standard share URIs for **6 protocols** (ss, vmess, vless,
  trojan, hysteria2, tuic); `ProxyURIParser` (existing) extended to
  parse the new hysteria2/tuic schemes. `QRCodeGenerator` wraps
  `CIQRCodeGenerator` to produce `NSImage`. New private `NodeQRSheet`
  view in `NodeEditorView` with a grid of scannable QRs + "Copy All
  URIs" + "Save All as PNGs" actions. Entry points: per-row
  "Share as QR Code" contextMenu + toolbar "Share All".

### Fixed

- **`RuleTarget` properties are now mutable** (`let` → `var`). Required
  for SwiftUI `Binding` setters in the W2-3 hit-preview helpers. Value
  type, no consumer-level semantics change.
- **`parseSS` unpadded-base64 bug** — the parser's
  `Data(base64Encoded:)` was rejecting URL-safe base64 whose length
  wasn't a multiple of 4, silently dropping credentials on
  `ss://...@host:port#name` URIs from share links. Extracted
  `decodeURLSafeBase64` helper that pads before decoding. Fixed in
  both `ProxyURIParser.swift` and `SubscriptionManager.swift` (which
  had a duplicate `parseSS` with the same bug).
- **`RuleEngine.matchedPolicy` cyclomatic complexity** — 33 in a
  pre-existing 18-case switch over `ProxyKind`. Disable comment added
  inline (`// swiftlint:disable:next cyclomatic_complexity`) since
  the function is irreducible as a single canonical match
  implementation. Unblocks CI which had been red on master for
  several weeks.

### Known limitations

- W3-1 (Node QR) is **macOS-only** in this release. Windows has
  `uri.rs` (parser, 4 schemes) but no serializer or QR generator.
  Cross-platform parity for share URIs is a future sub-project.
- `Override` UI (override list view, apply/preview actions) is **not**
  in this release. Data layer ships; UI work is W3 territory.

## [3.0.0-dev] — Unreleased

> **Status:** In progress. Plans 06 (UI tests), 07 (macOS native integration),
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
