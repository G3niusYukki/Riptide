# AGENTS.md

> Project context for any agent (human contributor, CI bot, or AI assistant)
> working in this repository. **AGENTS.md is the canonical project-shape
> doc** — `README.md` is the user-facing landing page and `CONTRIBUTING.md`
> covers contribution workflow. If this file disagrees with the source tree,
> trust the source tree and send a PR to fix it.

## 1. Project Summary

**Riptide** is a cross-platform Clash-compatible proxy client, distributed as
two apps that share the same Clash YAML profile format and the same upstream
proxy core ([mihomo](https://github.com/MetaCubeX/mihomo)):

- **macOS** — SwiftUI app (`RiptideApp`) + CLI (`riptide`) backed by the
  pure-Swift `Riptide` library. Can optionally delegate traffic to a mihomo
  sidecar for production TUN and broader protocol coverage.
- **Windows** — Tauri 2 app (`riptide.exe` + `riptide-tun-service.exe`)
  in `riptide-windows/`, written in Rust + React/TypeScript, driving mihomo
  directly via its REST API and a small SCM-registered service for
  unprivileged TUN.

Both platforms cut the same `vX.Y.Z` git tag and are bundled together in a
single GitHub release. Linux is built by CI but not yet packaged for
distribution.

**Current state (v2.4.0)** — 593 tests in 93 suites, all passing. SwiftLint
strict is green on the new code. The macOS app is the primary development
target; Windows and Linux track it. iOS is **explicitly out of scope** for
v3.0.0 — see the archived `docs/_archive/riptide-ios-stub/`.

## 2. Environment

| Item | Value |
|---|---|
| macOS deployment target | 14.0 (Sonoma) |
| macOS Swift toolchain | 6.2+ / Xcode 16+ |
| Windows toolchain | Node 20+, Rust 1.75+, Windows 10+, WebView2 |
| Package manager | SwiftPM (macOS), npm + Cargo (Windows Tauri) |
| macOS external deps | `Yams` (YAML parsing), `swift-argument-parser` (CLI) |
| Windows external deps | Tauri 2 (`@tauri-apps/api` JS + `tauri` Rust crate, minor versions must agree), React 18, TypeScript 5 |

## 3. Repository Layout

```
.version                            # canonical version, read by every bundler
Package.swift                       # macOS SwiftPM manifest
Sources/Riptide/                    # pure-Swift proxy library (macOS)
  AppShell/  Bridge/  Config/  Connection/  Control/  Core/
  DNS/       Diagnostics/  Groups/  HealthCheck/  LocalProxy/  Logbook/
  Logging/   MITM/   Mihomo/  Models/  NodeEditor/  Override/  Protocols/
  ProxyProvider/  QRCode/  Riptide.swift  Rules/  Scripting/  SingBox/
  Subscription/  Sync/  Traffic/  Transport/  Tunnel/  Utils/  VPN/  XPC/
Sources/RiptideApp/                 # SwiftUI macOS app target
  App/  Assets.xcassets/  Intents/  Localization/  MenuBarScene.swift
  RiptideApp.swift  SMJobBlessManager.swift  AppViewModel.swift
  ViewModels/  Views/
Sources/RiptideCLI/                 # `riptide` command-line tool
Sources/RiptideTunnel/              # NetworkExtension (macOS only)
RiptideHelper/                      # privileged XPC service (SMJobBless)
Tests/RiptideTests/                 # 72 files, 593 tests, 93 suites
Scripts/                            # build-release.sh, bump-version.sh, signing
.github/workflows/                  # release.yml, ci.yml, deploy-docs.yml, …
homebrew/                           # Homebrew Formula + auto-update workflow
riptide-windows/                    # Windows Tauri port (self-contained subtree)
  src/                              # React + TypeScript UI
  src-tauri/                        # Rust backend
    src/bin/tun_service.rs          # Windows service binary
    src/core/                       # mihomo lifecycle, mode coordinator, WARP,
                                    # kill switch, recovery watchdog, WebDAV,
                                    # region presets, geo assets, …
    src/config/                     # profile store, YAML parser, share URI
rules/                              # bundled rule-sets (cn-domain, geoip-cn, …)
site/                               # VitePress documentation site
docs/                               # public design docs and READMEs
docs/_archive/                      # archived iOS / Go stubs
```

## 4. Sources/Riptide/ — Core Library

| Directory | Responsibility |
|---|---|
| `Riptide.swift` | Module entry surface; do not add logic here. |
| `AppShell/` | App-facing coordinators: `ModeCoordinator` (actor), `ProfileStore`, system proxy guard, import service, stats pipeline, health checks. |
| `Bridge/` | `GoCoreBridge` — embedded GoCore / sing-box process bridge. |
| `Config/` | Clash YAML parsing (`ClashConfigParser`) and deep config merging (`ConfigMerger`). |
| `Connection/` | `ProxyConnector` — binds proxy nodes to transports with protocol handshake. |
| `Control/` | External controller surfaces: REST API + WebSocket streaming (traffic + connections). |
| `Core/` | `RiptideError` enum (`LocalizedError` conformance for 17 subsystems) + `LocalizedErrorExtensions`. |
| `Diagnostics/` | `DiagnosticReport` — one-button report generator (excludes credentials). |
| `DNS/` | Full DNS stack: UDP/TCP/DoH/DoT/DoQ, cache, FakeIP pool, pipeline orchestrator, nameserver-policy, hosts override. |
| `Groups/` | Proxy group resolution (select / url-test / fallback / load-balance), `LoadBalancer` with consistent-hash and round-robin. |
| `HealthCheck/` | `HealthChecker` + `GroupSelector` for latency-based proxy selection. |
| `LocalProxy/` | `LocalHTTPConnectProxyServer` — local HTTP CONNECT ingress with domain sniffing. |
| `Logbook/` | Persistent diagnostic event + closed-connection journal. JSONL-per-UTC-day files at `~/Library/Application Support/Riptide/logbook/YYYY-MM-DD.jsonl`. `LogbookStore` (actor) + `LogbookWriter` (facade) + `ClosedConnectionWatcher` (diff algorithm; runtime tick loop is W3-2b). |
| `Logging/` | `LogLevel`, `LogEntry`, parser, formatter. Real-time log surface; `Logbook` owns history. |
| `MITM/` | MITM framework: config, manager, HTTPS interceptor, CA scaffolding. Production status: 🟡 experimental. |
| `Mihomo/` | mihomo sidecar integration: `MihomoAPIClient` (actor), `MihomoConfigGenerator`, `MihomoCoreManager`, `MihomoDownloader`, `MihomoLogClient`, `MihomoPaths`, `MihomoRuntimeManager`, `SudoMihomoLauncher`. |
| `Models/` | Core data models: `ProxyNode`, `ProxyRule`, `RoutingPolicy`, `ProxyGroup`. |
| `NodeEditor/` | Proxy node editing with real-time validation. |
| `Override/` | Override data model: `Override` value type, `OverrideStore` actor (file-backed JSON sidecar + per-override YAML), `OverrideMerger` (meta.replace / removed: semantics), `OverrideApplyError`. |
| `Protocols/` | Outbound protocol framing: Shadowsocks (AEAD), VMess, VLESS, Trojan, Hysteria2, Snell, TUIC, SOCKS5, HTTP CONNECT. |
| `ProxyProvider/` | Proxy provider abstraction. |
| `QRCode/` | `QRCodeGenerator` — `CIQRCodeGenerator` wrapper, returns `NSImage`. Used by Node editor "Share as QR Code" + "Share All". |
| `Rules/` | `RuleEngine` (18-case match), GeoIP MMDB parser, GeoSite/ASN resolvers, RuleSet, SCRIPT (JavaScript). |
| `Scripting/` | JavaScript-based script engine for rule evaluation. |
| `SingBox/` | sing-box config generation + core integration (`SingBoxConfigGenerator`, `SingBoxCore`). |
| `Subscription/` | `SubscriptionManager` + `SubscriptionUpdateScheduler` + URI parser/serializer (ss/vmess/vless/trojan/hy2/tuic). |
| `Sync/` | WebDAV config sync. |
| `Traffic/` | Traffic monitoring providers and view models. |
| `Transport/` | Transport contracts + implementations: TCP, TLS, WebSocket, HTTP/2, QUIC, Multiplex, Connection Pool. |
| `Tunnel/` | `LiveTunnelRuntime` — runtime state machine, connection lifecycle, traffic recording. |
| `Utils/` | `SecureStorage` (Keychain-backed credential storage). |
| `VPN/` | TUN providers: `TUNRoutingEngine`, `UserSpaceTCP`, `PacketTunnelProvider`, TCP/UDP sessions. |
| `XPC/` | Privileged helper tool communication via XPC. |

## 5. Sources/RiptideApp/ — SwiftUI App

| Path | Responsibility |
|---|---|
| `App/Theme.swift` | Theme colors + light/dark adaptive background gradient. |
| `App/ThemeManager.swift` | Theme switching (System / Light / Dark). |
| `App/MainTabView.swift` | 8-tab container: Dashboard, Config, Proxy, Traffic, Rules, Logs, **诊断 (Diagnostics, v2.4.0)**, Settings. |
| `App/AccessibilityIdentifiers.swift` | Centralized `A11yID` namespace for UI tests. |
| `App/StatusBarController.swift` | Menu bar extra — `NSPopover` hosting SwiftUI `MenuBarPopoverView`. |
| `App/TouchBarProvider.swift` | `NSTouchBarDelegate` for node switching on Touch Bar MacBook Pros. |
| `App/URLSchemeHandler.swift` | `riptide://` URL scheme router (switch-group / select-node / mode / import / diagnostics). |
| `App/HotkeyManager.swift` | Global hotkey registration. |
| `App/ConfigDropDelegate.swift` | Drag-and-drop file import. |
| `AppViewModel.swift` | Central application state; holds the `LogbookContainer` and distributes `LogbookWriter` to business modules. |
| `RiptideApp.swift` | SwiftUI `@main` entry point. |
| `MenuBarScene.swift` | Menu bar extra scene wiring. |
| `SMJobBlessManager.swift` | Privileged helper install — `SMAppService` on macOS 13+, `SMJobBless` fallback. |
| `Intents/` | Apple Shortcuts Intents (`SwitchProxyMode`, `SelectProfile`). |
| `Localization/` | i18n: en, zh-Hans, ja, ru, es, ko, fa, pt-BR, vi + system auto-detect. |
| `ViewModels/` | `AppViewModel`, `ProxyViewModel`, `LogViewModel`, `LogbookViewModel` (v2.4.0), `NodeEditorViewModel`, `RuleEditorViewModel`, `MITMSettingsViewModel`, `ConfigMergeViewModel`, `WebDAVViewModel`. |
| `Views/` | All SwiftUI views. Subdirectories: `Dashboard/`, `Diagnostics/` (v2.4.0), `MenuBar/`, `Rules/`, `Scenes/`, `Settings/`, plus the top-level tab views. |

## 6. Sources/RiptideCLI/

`riptide` command-line tool — `validate`, `run`, `smoke` subcommands. Reads
the same `Riptide` library as the app, with no UI.

## 7. Tests — Tests/RiptideTests/

72 files, 593 tests in 93 suites. Coverage includes: config parsing and
merging, rule engine (15+ rule types), DNS (UDP/TCP/DoH/DoT/DoQ/FakeIP),
protocol framing (SS/VLESS/Trojan/Hy2/Snell), transports, tunnel runtime,
mihomo API + config generation, subscription URI parser + serializer,
override merging, logbook append/query/prune/concurrency, MITM config,
localization, system proxy guard integration, mode switching, health
checks, TUN recovery.

UI test target: `RiptideAppUITests/` — 38 tests across 11 suites covering
launch, dashboard, config import, proxy tab, connections, log viewer,
launch-at-login, URL scheme, Touch Bar, and menu bar popover.

## 8. Build & Test

### macOS

```bash
swift build                              # library + CLI + app
swift test                               # 593 tests, 93 suites
swift test --filter "RuleEngine"         # single suite
swift run RiptideApp                     # launch UI
swift run riptide --help                 # CLI
./Scripts/download-mihomo.sh             # fetch mihomo for sidecar mode
./Scripts/build-release.sh               # build + sign a release bundle
./Scripts/bump-version.sh 2.5.0         # coordinated version bump
```

### Windows

```bash
cd riptide-windows
npm install
npm run tauri dev                        # dev mode (hot-reload UI)
npm run tauri build                      # release NSIS + MSI bundle
```

Tauri version alignment is enforced: the JS `@tauri-apps/api` and the Rust
`tauri` crate must agree on minor versions or `tauri build` refuses to
bundle. Keep `riptide-windows/package.json` pinned to whatever crates.io
currently publishes (currently `~2.10`).

## 9. Architecture Notes

### macOS — Request Flow (System Proxy / TUN)

```
LocalHTTPConnectProxyServer / TUN packet
  → LiveTunnelRuntime.openConnection()
    → RuleEngine.resolve() → RoutingPolicy
    → ProxyConnector.connect(via: node, to: target)
      → Transport session (TCP / TLS / WS / QUIC / HTTP2)
      → Protocol handshake (SS / VMess / VLESS / Trojan / Hy2 / Snell / TUIC)
      → Bidirectional data relay
```

### Windows — TUN Mode (SYSTEM service)

```
User selects TUN → UI checks is_elevated; if not, install_tun_service
  → install_tun_service re-launches riptide.exe --install-service elevated
  → registers RiptideTUN with SCM
  → mode_switch_to_tun writes %PROGRAMDATA%\Riptide\service.conf
  → SCM starts riptide-tun-service.exe (running as SYSTEM)
  → service reads conf, spawns mihomo
  → recovery_watchdog health-probe loop restarts mihomo on 2 consecutive failures
```

### Concurrency Model

- **Swift (macOS):** Swift 6 strict concurrency enforced. Actors for
  stateful components: `MihomoRuntimeManager`, `HelperToolConnection`,
  `MihomoAPIClient`, `ModeCoordinator`, `ProfileStore`,
  `LiveTunnelRuntime`, `OverrideStore`, `LogbookStore`, `LogbookWriter`,
  `ClosedConnectionWatcher`, `LogbookViewModel` (`@MainActor`).
  Value types are `Equatable, Sendable, Codable`. `@unchecked Sendable`
  only on `NSXPCConnection` / `NSXPCListener` and on
  `LogbookContainer` (which holds actors).
- **Rust (Windows):** `tokio` for async work, `Mutex<T>` /
  `Arc<StdMutex<T>>` for cross-task state. Tauri commands are `async fn`
  returning `Result<T, String>` (strings flow to the JS layer as errors).

## 10. Key Design Principles

- **Library-first**: shared logic belongs in `Sources/Riptide/`, not CLI
  or app targets. The macOS app and the `riptide` CLI both consume the
  same library.
- **Strict concurrency**: follow Swift 6 `Sendable` and actor isolation
  throughout. If you add a stored property holding shared state, isolate
  it (actor, `@MainActor`, or a serial queue).
- **No silent fallbacks**: fail explicitly rather than silently degrading.
  The diagnostic Logbook is fire-and-forget (`try?` swallows IO errors)
  by design — that's the one allowed exception, and only because
  business paths must never block on diagnostic logging.
- **No force unwraps**: use proper error handling with typed error enums.
  `!` is allowed in tests only.
- **Dependency injection over globals**: prefer injection over hard-coded
  global behavior. The cross-cutting concern pattern for v2.4.0+ is
  `Module.setFoo(dependency) async` on actors + a single injection site
  in `AppViewModel.init`.
- **Separable units**: protocol streams, transport layers, and
  diagnostic surfaces have clear interfaces and can be tested in
  isolation.
- **No broadened support claims**: keep README + CHANGELOG precise about
  what is implemented vs scaffolded. If a feature is 🟡 or 🧱 in the
  README status table, do not market it as production-ready in commit
  messages or docs.

## 11. Coding Conventions

- Follow Swift 6 strict concurrency (`@MainActor`, `Sendable`, `actor`).
- Prefer `struct` / `enum` models with `Equatable, Sendable, Codable`.
- Error enums conform to `LocalizedError` (Swift) or
  `thiserror::Error` (Rust).
- Keep stateful runtime components isolated and concurrency-safe.
- Do not add logic to `Sources/Riptide/Riptide.swift` (module entry
  surface).
- Avoid force unwraps (`!`) in production code; tests may use them
  sparingly.
- Keep changes modular and consistent with surrounding folder patterns.
- On Windows, route everything through `WindowsDirs` so the app stays
  rooted at `%APPDATA%\Riptide\`. Never use Tauri's bundle-identifier
  path (`com.riptide.app`) — they don't match.
- On Windows, when editing user profiles round-trip through
  `serde_yaml::Value`, not `ClashRawConfig`, so unknown keys survive.
- SwiftLint strict mode: `identifier_name` minimum 2 chars;
  `cyclomatic_complexity` warning 18 / error 25. If you legitimately need
  a 1-character name, add it to `.swiftlint.yml`'s `excluded` list with
  justification, not a `swiftlint:disable` inline annotation.
- Tauri commands are `async fn` returning `Result<T, String>`; map errors
  at the boundary with `.map_err(|e| e.to_string())`. Use a single
  struct return so the TS side can type-check it via
  `src/services/tauri.ts`.

## 12. Change Guidance

- Fix the root cause rather than patching symptoms when practical.
- Add or update tests for behavior changes. TDD red-green-refactor:
  failing test first, then implementation, then refactor.
- Keep scaffolding and partially wired subsystems clearly separated from
  production-ready paths (e.g. `WIP-` file names, 🟡 status badges).
- Do not broaden support claims in docs or code unless the behavior is
  wired end-to-end.
- For new features, prefer dependency injection over hard-coded global
  behavior.
- When a feature ships across multiple sub-week deliverables (e.g.
  W3-2a data layer, W3-2b runtime loop), document the split in
  CHANGELOG.md and explicitly mark which side ships in this version.

## 13. Validation Expectations

- Run targeted tests first when changing a focused area:
  `swift test --filter "SuiteName"`.
- Run `swift test` before claiming the work is complete
  (593 / 593 must pass).
- If changing CLI behavior, verify with `swift run riptide ...`.
- If changing app-facing state or workflow code, sanity-check
  `swift run RiptideApp` builds and launches.
- Run `swiftlint lint --strict` on modified production files; CI
  enforces 0 violations on new code.
- On Windows changes, run `cargo check` (or `cargo build` for
  full verification) and `npm run tsc` before claiming done.
- Never push directly to `master` without a green CI on the prior
  commit. The release tag flow is: bump version → push --follow-tags →
  release workflow runs → GitHub Release published with 7 assets
  (macOS DMG + ZIP, Windows MSI + NSIS, Linux deb + AppImage).

## 14. Documentation

- Update `README.md` when user-visible behavior, commands, or supported
  capabilities change.
- Update `CHANGELOG.md` at the top of the file with a new entry for
  every version bump. Use the established template
  (`## [X.Y.Z] — YYYY-MM-DD`, `### Added`, `### Fixed`,
  `### Known limitations`).
- Update feature status tables in README when adding new capabilities
  or graduating a feature from 🟡 to ✅.
- When a new diagnostic surface ships, add an entry under
  `A11yID.Diagnostics.*` in `App/AccessibilityIdentifiers.swift` and
  write UI tests that exercise the new flow.
- When a new sub-week deliverable lands (W3-2a, W3-2b, …), reference
  it from both CHANGELOG.md and AGENTS.md so future readers can trace
  the design → plan → implementation chain via
  `docs/superpowers/specs/`.

## 15. Release Flow

```bash
./Scripts/bump-version.sh 2.5.0       # updates .version + per-platform files
# edit CHANGELOG.md to add the new entry at the top
git add -A && git commit -m "chore: bump version to 2.5.0"
git tag -a v2.5.0 -m "Riptide v2.5.0"
git push origin master --follow-tags
```

The release workflow (~26 minutes end-to-end) builds macOS + Windows +
Linux, then publishes a GitHub Release with all artifacts attached. The
top entry of CHANGELOG.md is used as the release notes.
