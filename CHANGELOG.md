# Changelog

## [2.7.0] — 2026-06-17

> **macOS — TUN mode lands, and the release actually launches.** Adds working TUN mode, fixes a long-standing bug that crashed every shipped build at launch, and polishes the menu bar / subscription UX. macOS-only release; Windows/Linux are unchanged.

### Added

- **TUN mode (macOS).** Full packet-level interception. Because an unentitled GUI app can't create a `utun` or change the routing table, Riptide runs a **standalone `riptide-singbox` core as root** via a launchd daemon (`com.riptide.tun`) installed once with a single administrator-password prompt (`osascript … with administrator privileges` — no Apple Developer account / Network Extension needed). The daemon uses `KeepAlive.PathState`, so enabling/disabling TUN afterwards just creates/removes a flag file — no further prompts — and stopping sends `SIGTERM` for clean route teardown. The standalone core is built from the *same* sing-box v1.9 (+`with_utls`) source as the in-process system-proxy core (`gocore/cmd/riptide-singbox`, `Scripts/build-singbox-bin.sh`), so configs match exactly. Verified end-to-end against a live `vless`+REALITY subscription.
- **Minimal menu-bar indicator.** While the proxy is running the menu bar shows a small green arrow; live up/down speed still appears in the popover on click.

### Fixed

- **Every shipped build crashed at launch — fixed.** The app links Sparkle dynamically, but no release since ~v2.1.0 bundled `Sparkle.framework`, so downloaded `.dmg`/`.zip` builds died immediately with `Library not loaded: @rpath/Sparkle.framework` (only `swift run` worked). Now the framework is bundled into `Contents/Frameworks/` with the matching rpath, and the bundle is always code-signed (ad-hoc when no Developer ID is configured — Apple Silicon refuses to run an unsigned/invalidated binary).
- **Subscription profiles survive relaunch.** A subscription's profile was held in memory only, so after every relaunch it vanished and you had to click 更新 once to get a usable profile. It's now recreated automatically on launch. Refreshing a subscription that has no profile also creates one.
- **Menu-bar item no longer overlaps adjacent apps.** The old live-speed display was a custom subview that overflowed the status item's slot and drew over neighbouring icons; the item now renders a single image-only symbol sized to the icon.

### Changed

- **Removed the dead mihomo "Helper" UI.** Deleted `SMJobBlessManager` and `HelperSetupView`, the onboarding "install helper" step, and the unused `AppViewModel` helper plumbing. The shipped engine is in-process sing-box (system-proxy) + the elevated launchd daemon (TUN); the SMJobBless helper was never used at runtime. The privileged-helper backend (XPC protocol, diagnostics check) is retained.

## [2.6.0] — 2026-06-16

> **macOS — a proxy core that actually proxies.** Fixes system-proxy mode (it previously started the core but never pointed the OS at it), adds REALITY/uTLS support by rebuilding the in-process sing-box core, and broadens protocol coverage. macOS-only release; Windows/Linux are unchanged.

### Added

- **REALITY / uTLS support (macOS).** Rebuilt the in-process sing-box core (`libgocore.a`) with `-tags with_utls`, so `vless` + REALITY nodes negotiate uTLS and connect instead of being rejected/degraded to plain TLS. The previously-opaque Cgo wrapper is now checked in at `gocore/` with a reproducible universal-binary build script (`Scripts/build-gocore.sh`); `GenerationOptions.supportsUTLS` is enabled on the GoCore path. Verified end-to-end against a live `vless`+REALITY subscription.
- **Broader sing-box protocol coverage (macOS).** `SingBoxConfigGenerator` now emits correct sing-box v1.9 outbounds for `vmess` (ws/grpc transports), `vless` (REALITY, `flow`, ws/grpc), `hysteria2`, and `tuic` (with `congestion-control`). Clash YAML parsing and base64 share-URI subscriptions gained REALITY fields (`pbk`/`sid`/`fp`/`sni`/`flow`), `tls`, and `congestion-control`.

### Fixed

- **System-proxy mode now sets the OS proxy (macOS).** `GoCoreTunnelRuntime` points the macOS system proxy at sing-box's mixed listener (`127.0.0.1:6152`) via `networksetup` on start — no root/helper/sudo needed for an admin user — and clears it on stop. Previously the core started but the OS proxy was never configured, so traffic was not actually routed through it.
- **Stale system-proxy cleanup on launch (macOS).** A leftover `127.0.0.1:6152` system proxy from a prior run is cleared on startup when the app isn't running.
- **Honest traffic counters.** Removed the hard-coded mock traffic values; `GoCoreGetTraffic` now reports real counters (0 until the clash-api traffic manager is wired).
- **Test robustness.** `AppGroupStateStore` falls back to Application Support when the app-group container exists but rejects writes (unentitled test/CLI runs), fixing two environment-dependent test failures and hardening state persistence in production.

## [2.5.0] — 2026-06-12

> **macOS UI Enhancement** — major UX pass closing the feature gap with ClashX Pro / Surge / Stash. Adds 14 new view files, modifies 15 existing files; ~1,900 net lines.

### Added (P0 — Foundation)

- **Menu bar persistent speed display** — live `↑ 1.2M ↓ 3.4M` text replaces the static shield icon when the proxy is running; format helper compactifies `<1K / 1.0K / 1.0M / 1.0G`.
- **Country flags on proxy nodes** — `RegionMapping` table covers 50+ Chinese/English keywords → ISO codes; `CountryFlagView` renders Unicode regional-indicator flag emojis (fallback: 🌐).
- **Protocol badges on proxy rows** — colored capsule (SS cyan, VMess purple, VLESS blue, Trojan orange, Hy2 green, etc.) covers all 14 `ProxyKind` cases.
- **Sort/filter/search in proxy tab** — `NavigationStack` wrapper enables `.searchable`; sort (default/delay↑/delay↓/name), filter (all/available), and free-text search compose cleanly.

### Added (P1 — Core UX)

- **Traffic chart auto-collect with time range** — `TrafficTimeRange` enum (1min/5min/1h/24h) replaces hardcoded 60-point cap; auto-start in `.task`, manual toggle removed, x-axis now uses real timestamps.
- **Global hotkey deep integration** — 3 new actions (toggle system proxy, switch next node, test all delay); `HotkeySettingsView` with live key recording and conflict detection; known-conflict documentation.
- **Rule match testing tool** — `RuleMatchTesterView` sheet parses domain/IP input, runs `RuleEngine.resolve`, displays matched rule/policy/latency, persists 10-entry history.
- **Drag-and-drop + clipboard import** — `ConfigTabView` accepts `.yaml`/`.yml`/`.txt` drops, routes URLs/URIs/YAML to appropriate handlers, plus a "从剪贴板导入" button.
- **Network scene auto-switching enhancement** — `NetworkEnvironmentSettingsView` shows current SSID + active scene, full edit sheet (proxy mode, connection mode, profile binding, enable toggle), 5s auto-refresh.

### Added (P2 — Polish)

- **Dashboard enrichment** — `MiniTrafficChart` (60pt pulse), `TrafficHistoryCard` (today/week/month via `LogbookStore.trafficByDate`), `NodeHealthCard` (per-group healthy ratio bars), `QuickActionsRow` (4 shortcut buttons).
- **`LogbookStore.trafficByDate` aggregation** — new actor method scans UTC-day `.jsonl` files, aggregates `uploadBytes`/`downloadBytes` per day; 3 Swift-Testing tests.
- **Context menus on rows** — proxy nodes (test delay, copy info), connections (close, copy host), rules (copy text).
- **Traffic history view** — `TrafficHistoryView` with day/week/month segmented picker and stacked bar chart.
- **Notification system expansion** — 3 new types (`notifyTrafficThreshold`, `notifyConfigUpdateSuccess`, `notifyConfigUpdateFailed`); `NotificationSettingsView` with 5 toggles + threshold slider; `SubscriptionUpdateScheduler.onUpdateResult` callback for wiring.

### Added (P3 — Advanced)

- **Visual rule editor** — `VisualRuleEditorView` with 9 rule type pickers, dynamic value inputs, policy selector, "Add" and "Add & Continue" actions; persists via `AppViewModel.appendRule(_:)`.
- **Basic YAML editor** — `YAMLEditorView` sheet with monospaced `TextEditor`, `ClashConfigParser`-backed validation, re-parse on save via `updateProfileYAML`.
- **Visual polish** — `Theme` gains `cardBackground`/`elevatedCard`/`cardBorder` NSColor-adapted tokens; spring animations on proxy card expand/collapse, ease-in-out on node selection.
- **Drag-and-drop node sorting** — `.draggable` + `.dropDestination` for `.select` groups; order persisted to `UserDefaults` via `vm.nodeOrder` dict.

### Changed

- `TrafficViewModel.maxHistoryPoints` removed; replaced by per-instance `timeRange: TrafficTimeRange` and `setTimeRange(_:)`.
- `TrafficChartView` controls simplified: "Start/Stop" button removed, replaced by segmented `Picker`.
- `ProxyNodeRow` API extended: takes `group` and `vm` for context menu and drag/drop.

### Test surface

- New test files: `RegionMappingTests`, `CountryFlagViewTests`, `ProtocolBadgeTests`, `MenuBarSpeedViewTests`, `ProxyTabFilterTests`, `RuleMatchTesterTests`, `HotkeyManagerTests`, extended `LogbookStoreTests` (3 new), extended `UserNotificationManagerTests`.
- 622 tests in 96 suites. 2 pre-existing `AppGroupStateStoreTests` failures are environmental (no App Group container in dev env), unrelated to this work.

## [2.4.1] — 2026-06-04

> **Status:** Unreleased. Phase 1 closeout — closes a helper-LPE-class
> issue pattern, ships the EngineBenchmark harness + the Swift-vs-mihomo
> perf doc, and lands the sing-box skeleton (not enabled by default).
> Test suite: 590 → 593.

### Security (P0)

- **Helper caller validation** — `RiptideHelper` XPC listener now
  validates the caller audit token and code-signing identifier before
  accepting connections. Closes a helper-LPE-class issue pattern
  (CVE-style disclosure forthcoming — see ADR-0004 and
  `docs/security/2026-06-04-helper-cve.md`). Helper rejects
  unsigned / foreign callers; the client side declares its
  code-signing requirement via `setCodeSigningRequirement`.
- **`audit-policy.plist`** — new `RiptideHelper/Resources/audit-policy.plist`
  declares the caller allowlist and the `SMAuthorizedClients`
  placeholder (awaits a real Apple Developer Team ID).

### Performance

- **EngineBenchmark harness** — `Sources/Riptide/Performance/EngineBenchmark.swift`
  compares the pure-Swift engine against the mihomo sidecar across 5
  dimensions: HTTP CONNECT p50/p99, throughput, idle memory, CPU,
  startup. First CI run lives at `.github/workflows/bench.yml`.
- **mihomo sidecar version pin policy** — `Scripts/download-mihomo.sh`
  now pins `MIHOMO_VERSION="v1.18.5"` and the policy is documented
  in ADR-0006. (Pin was already in place on master; the ADR is new.)

### Foundation (no user-visible default change)

- **Sing-box skeleton** — added `SingBoxRuntimeManager` and
  `SingBoxDownloader` in `Sources/Riptide/SingBox/`. (`SingBoxPaths`,
  `SingBoxConfigGenerator`, and `SingBoxAPIClient` already existed on
  master since 5/27.) Sing-box is **not** enabled by default; the
  skeleton exists to support new protocols (Reality, AnyTLS) in
  v2.5.0.
- **`ProxyEngine` protocol + `EngineRouter`** — new
  `Sources/Riptide/Engines/ProxyEngine.swift` and `EngineRouter.swift`
  with default-mihomo policy. Visible in 设置 → 内核管理 as a
  read-only status panel (status-only in Phase 1).
- **`download-singbox.sh`** — `Scripts/download-singbox.sh` (already
  on master, 5/27) pins `v1.13.0`; the `SingBoxDownloader` skeleton
  hard-codes the same version so the two stay in sync.
- **Tests:** 4 new test suites / 3 new tests (EngineRouter suite).
  590 → 593.

## [W3-2a] — 2026-06-03

> **Status:** Unreleased. W3-2a ships the data layer + Diagnostics tab. W3-2b
> (ClosedConnectionWatcher runtime loop + ConnectionHistorySection data) is a
> follow-up spec. ~32 new tests; full suite 560 → ~593.

### Added

- **Logbook data layer** — `Sources/Riptide/Logbook/LogbookPaths.swift`,
  `LogbookEntry.swift`, `LogbookStore.swift`, `LogbookWriter.swift`,
  `ClosedConnectionWatcher.swift`. JSONL-per-UTC-day format at
  `~/Library/Application Support/Riptide/logbook/YYYY-MM-DD.jsonl`. Fire-and-forget
  writes; reads skip malformed lines.
- **"诊断" (Diagnostics) tab** — 7th tab between 日志 and 设置. Contains
  "事件" (EventLogSection) and "连接历史" (ConnectionHistorySection, empty state
  in W3-2a). Filter by level / category / date range; clear + export actions.
- **LogbookContainer + LogbookViewModel** — `AppViewModel.logbook` holds the
  trio. Distributed to 5 business modules (ModeCoordinator, SubscriptionManager,
  HelperToolConnection, MihomoRuntimeManager, OverrideStore) via
  `logbookWriter: LogbookWriter?` injection with async `setLogbookWriter` setters.
- **ClosedConnectionWatcher diff algorithm** — actor detects connections that
  disappeared between two ticks. Runtime loop is W3-2b.

### Known limitations

- W3-2a's connection-history section is empty; the data model + diff algorithm
  land in W3-2a, but the runtime tick loop that wires into the tunnel runtime is
  W3-2b.
- App lifecycle (launch / quit) events are not yet wired to the Logbook
  (the SwiftUI app has no AppDelegate; lifecycle hooks are deferred).
- Pre-existing SwiftLint violation in `OverrideStore.swift:45` (`var o` short
  identifier) is unrelated to this work.

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
