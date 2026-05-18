# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Riptide is a cross-platform proxy client shipped as two apps that share the same
**Clash-compatible profile format** and the same upstream proxy core
([mihomo](https://github.com/MetaCubeX/mihomo)):

- **macOS** — SwiftUI app (`RiptideApp`) + CLI (`riptide`) backed by the
  pure-Swift `Riptide` library, plus an optional mihomo sidecar for TUN.
- **Windows** — Tauri 2 app (`riptide.exe` + `riptide-tun-service.exe`)
  written in Rust + React/TypeScript, driving mihomo directly via its REST
  API and a small SCM-registered service for unprivileged TUN.

Both platforms cut the same `vX.Y.Z` git tag and are bundled together in a
single GitHub release. Current version is **v2.0.0** (`.version` at repo root).

## Repository Layout

```
.version                            # canonical version, read by every bundler
Package.swift                       # macOS SwiftPM manifest
Sources/Riptide/                    # pure-Swift proxy library
  Protocols/  Transport/  DNS/  Rules/  Tunnel/  LocalProxy/
  Mihomo/     XPC/        AppShell/  Subscription/
Sources/RiptideCLI/                 # `riptide` command-line tool
Sources/RiptideApp/                 # SwiftUI macOS app target
Sources/RiptideTunnel/              # NetworkExtension (macOS only)
RiptideHelper/                      # privileged XPC service (SMJobBless)
Tests/RiptideTests/                 # 53 test suites
Scripts/
  build-release.sh                  # macOS release packaging
  bump-version.sh                   # updates .version + all per-platform files
.github/workflows/
  release.yml                       # builds macOS + Windows on tag push
riptide-windows/                    # Windows port — self-contained subtree
  src/                              # React + TypeScript UI
    components/  hooks/  i18n/  services/tauri.ts  stores/
  src-tauri/
    src/                            # Rust backend
      bin/tun_service.rs            # Windows service binary
      cli.rs                        # one-shot CLI flags (--install-service etc.)
      cmds/                         # Tauri command handlers
      config/                       # profile store, YAML parser, share URI
      core/                         # mihomo lifecycle, mode coordinator,
                                    # WARP, kill switch, recovery watchdog,
                                    # subscription scheduler, geo assets,
                                    # WebDAV, region presets, TLS tricks…
      utils/                        # dirs, hotkeys, logger, windows_dirs
    Cargo.toml                      # default-run = "riptide-windows"
    tauri.conf.json                 # NSIS + MSI bundle targets
```

## Build & Test

### macOS

```bash
swift build                                    # Library + CLI + App
swift test                                     # Runs 53 suites
swift test --filter "RuleEngine"               # Single suite
swift run RiptideApp                           # Launch UI
swift run riptide --help                       # CLI
./Scripts/download-mihomo.sh                   # Fetch mihomo for sidecar mode
./Scripts/build-release.sh                     # Build + sign a release bundle
./Scripts/bump-version.sh 2.1.0                # Coordinated version bump
```

Requirements: macOS 14+, Swift 6.2+ (Xcode 16+).

### Windows

```bash
cd riptide-windows
npm install
npm run tauri dev                              # Dev mode (hot-reload UI)
npm run tauri build                            # Release NSIS + MSI bundle
npm run tauri build -- --debug                 # Debug build with devtools
```

Requirements: Node 20+, Rust 1.75+, Windows 10+ with WebView2.

**Two binaries are produced:**
- `riptide-windows.exe` — main UI (Tauri shell)
- `riptide-tun-service.exe` — Windows service that runs mihomo as SYSTEM
  for unprivileged TUN

**Tauri version alignment is enforced:** the JS `@tauri-apps/api` and the
Rust `tauri` crate must agree on minor versions or `tauri build` refuses to
bundle. Keep `package.json` pinned to whatever crates.io currently publishes
(currently `~2.10`).

## Architecture

### macOS — Dual-engine library

```
┌──────────────────────────────────────────────────────────┐
│                    RiptideApp (SwiftUI)                   │
│  ┌─────────────────┐   ┌──────────────────────────────┐  │
│  │ Config/Proxy UI │   │ ModeCoordinator (actor)     │  │
│  └────────┬────────┘   │  Swift Engine | mihomo | TUN│  │
│           │            └──────────────────────────────┘  │
│           ▼                                              │
│   ┌──────────────────────────────────────────────────┐   │
│   │  MihomoRuntimeManager (actor — orchestrator)    │   │
│   └──────────────┬───────────────────────────────────┘   │
└──────────────────┼──────────────────────────────────────┘
                   │
       ┌───────────┴────────────┐
       ▼                        ▼
┌──────────────┐        ┌────────────────────┐
│ Swift Proxy  │        │  mihomo sidecar    │
│ Engine       │        │  (REST :9090, TUN) │
│ (built-in)   │        └─────────┬──────────┘
└──────┬───────┘                  │ XPC (root)
       │                ┌─────────▼──────────┐
       └───────────────►│ RiptideHelper       │
                        │ (SMJobBless)        │
                        └─────────────────────┘
```

The `Riptide` library implements the full proxy stack in pure Swift, so the
app can serve traffic without any external binary. The mihomo sidecar is
opt-in (used for production TUN and broader protocol coverage).

### Windows — Tauri shell over mihomo

```
┌──────────────────────────────────────────────────────┐
│              Riptide Tauri UI (React + TS)           │
│  Dashboard · Proxies · Profiles · Rules · Logs ·     │
│  Connections · Settings · NodeEditor                 │
└────────────┬──────────────────────────────┬──────────┘
             │ Tauri commands               │ events
             ▼                              ▲
┌──────────────────────────────────────────────────────┐
│            Rust backend (src-tauri/src)              │
│  ModeCoordinator (Off / SystemProxy / TUN)           │
│  MihomoManager — process + config-merge + watcher    │
│  SystemProxyController + drift guard                 │
│  KillSwitch · RecoveryWatchdog · GeoAssets           │
│  SubscriptionScheduler · WebDAV · WARP · Diagnostics │
└────────────┬─────────────────────────────────────────┘
             │ spawn / SCM
             ▼
┌────────────────────────┐    ┌─────────────────────────┐
│   mihomo.exe (sidecar) │    │ riptide-tun-service.exe │
│   REST :9090           │◄───┤ (Windows service, SYSTEM)│
└────────────────────────┘    └─────────────────────────┘
```

The Windows app does *not* embed a Swift-style native engine — it leans on
mihomo for everything proxy-related and focuses on UX, profile management,
and the privileged-service plumbing Windows needs.

### Concurrency Model

- **Swift (macOS):** Swift 6 strict concurrency enforced. Actors for stateful
  components: `MihomoRuntimeManager`, `HelperToolConnection`, `MihomoAPIClient`,
  `ModeCoordinator`, `ProfileStore`, `LiveTunnelRuntime`. Value types are
  `Equatable, Sendable, Codable`. `@unchecked Sendable` only on `NSXPCConnection` /
  `NSXPCListener`.
- **Rust (Windows):** `tokio` for async work, `Mutex<T>` / `Arc<StdMutex<T>>`
  for cross-task state. Tauri commands are `async fn` returning `Result<T, String>`
  (strings flow to the JS layer as errors).

## Component Map

### macOS — request pipeline (Swift Engine)
| Component | File | Role |
|-----------|------|------|
| `LocalHTTPConnectProxyServer` | `Sources/Riptide/LocalProxy/` | HTTP CONNECT ingress, domain sniffing |
| `LiveTunnelRuntime` | `Sources/Riptide/Tunnel/` | Connection lifecycle, traffic recording |
| `RuleEngine` | `Sources/Riptide/Rules/` | DOMAIN/GEOSITE/GEOIP/RULE-SET/SCRIPT routing |
| `ProxyConnector` | `Sources/Riptide/Connection/` | Binds proxy node to transport |
| `HealthChecker` | `Sources/Riptide/HealthCheck/` | Latency probing for url-test/fallback groups |
| `FakeIPPool` | `Sources/Riptide/DNS/` | CIDR-based IP allocation for HTTPS interception |
| `MihomoConfigGenerator` | `Sources/Riptide/Mihomo/` | YAML config gen with `yamlEscape()` |
| `MihomoRuntimeManager` | `Sources/Riptide/Mihomo/` | Process lifecycle, XPC, REST health checks |
| `HelperToolProtocol` | `Sources/Riptide/XPC/` + `RiptideHelper/` | `@objc` XPC protocol |
| `ModeCoordinator` | `Sources/Riptide/AppShell/` | Switching Swift Engine ↔ mihomo ↔ TUN |
| `ProfileStore` | `Sources/Riptide/AppShell/` | Disk-backed profiles |
| `SubscriptionManager` | `Sources/Riptide/Subscription/` | Remote config auto-update |

### Windows — backend
| Component | File | Role |
|-----------|------|------|
| `MihomoManager` | `src-tauri/src/core/mihomo.rs` | Spawn / watch / restart mihomo, generate merged config |
| `mihomo_bootstrap` | `src-tauri/src/core/mihomo_bootstrap.rs` | First-run binary download with pinned SHA-256 |
| `ModeCoordinator` | `src-tauri/src/core/mode_coordinator.rs` | Serialized Off/SystemProxy/TUN transitions, `mode_state` events |
| `SystemProxyController` | `src-tauri/src/core/sysproxy.rs` | Windows proxy setting + 3s drift guard |
| `service` | `src-tauri/src/core/service.rs` + `src-tauri/src/bin/tun_service.rs` | SCM install/uninstall + service entrypoint |
| `subscription_scheduler` | `src-tauri/src/core/subscription_scheduler.rs` | Per-profile auto-refresh |
| `recovery_watchdog` | `src-tauri/src/core/recovery_watchdog.rs` | Sleep/wake + network-change detection |
| `kill_switch` | `src-tauri/src/core/kill_switch.rs` | Optional blackhole route on TUN crash |
| `diagnostics` | `src-tauri/src/core/diagnostics.rs` | One-button report (excludes credentials) |
| `warp` | `src-tauri/src/core/warp.rs` | x25519 keypair + Cloudflare register → wireguard profile |
| `region_presets` | `src-tauri/src/core/region_presets.rs` | China / Iran / Russia rule + DNS overlays |
| `webdav` | `src-tauri/src/core/webdav.rs` | HTTPS WebDAV sync; DPAPI-encrypted password |
| `secrets` | `src-tauri/src/core/secrets.rs` | DPAPI wrappers |
| `geo_assets` | `src-tauri/src/core/geo_assets.rs` | GeoIP / GeoSite auto-download |
| `dns_policy` | `src-tauri/src/config/dns_policy.rs` | User DNS overlay applied on top of profile YAML |
| `parser` / `uri` | `src-tauri/src/config/` | Clash YAML round-trip + share-URI parser |
| `cmds::proxy_editor` | `src-tauri/src/cmds/proxy_editor.rs` | In-profile proxy CRUD (preserves unknown keys via `serde_yaml::Value`) |
| `WindowsDirs` | `src-tauri/src/utils/windows_dirs.rs` | All paths rooted at `%APPDATA%\Riptide\` |

### Windows — frontend
| Path | Role |
|------|------|
| `src/App.tsx` | Router, mode/event listeners, deep-link handling, hotkey forwarding |
| `src/main.tsx` | React root; `QueryClientProvider` wraps `App` |
| `src/components/Dashboard.tsx` | Status cards + live traffic chart |
| `src/components/Sidebar/` | 208px labelled nav with mode indicator |
| `src/components/Layout/Header.tsx` | Local-proxy tag + start/stop button + status badges |
| `src/components/Profiles/` | Profile CRUD, clipboard import, WARP register, share URI |
| `src/components/NodeEditor/` | Per-protocol forms: SS (+ shadow-tls plugin), VMess, VLESS (+ Reality), Trojan, Hy2, TUIC, AnyTLS, Snell, HTTP, SOCKS5 |
| `src/components/Settings/` | 6-tab settings: Network / DNS / Sync / Assets / Recovery / About (theme + i18n) |
| `src/services/tauri.ts` | Typed wrappers around every Tauri command + payload types |
| `src/stores/riptide.ts` | Zustand store; `theme` + `selectedProxy` etc. persisted to localStorage |
| `src/i18n/` | zh-CN, en-US fully translated; fa-IR, ru-RU, ja-JP seeded with EN fallback |
| `src/App.css` | Tailwind v4 + light/dark token blocks + `.light` utility override layer |

## Key Workflows

### macOS — HTTP CONNECT proxy (Swift Engine)
1. App sets system proxy to `127.0.0.1:6152`
2. `LocalHTTPConnectProxyServer` receives HTTP CONNECT
3. `RuleEngine` resolves routing policy
4. `ProxyConnector` → transport → protocol → remote server
5. Response relayed back through proxy server

### macOS — TUN mode (mihomo sidecar)
1. User selects TUN mode → `ModeCoordinator` checks `RiptideHelper` installation
2. If not installed, `SMJobBlessManager` prompts for admin password
3. `MihomoRuntimeManager.start(mode: .tun)`:
   - `MihomoConfigGenerator` writes YAML with `tun.enable: true`
   - XPC call to `launchMihomo(configPath:)`
   - REST API health check (10 retries, 500ms delay)
4. mihomo creates gVisor TUN device

### Windows — TUN mode (SYSTEM service)
1. User selects TUN → UI checks `is_elevated`; if not, calls `install_tun_service`
2. `install_tun_service` re-launches `riptide.exe --install-service` elevated via
   `ShellExecuteEx(verb=runas)`; that child registers `RiptideTUN` with SCM
3. `mode_switch_to_tun` writes `%PROGRAMDATA%\Riptide\service.conf` and calls
   SCM `start`; `riptide-tun-service.exe` reads the conf and spawns mihomo as SYSTEM
4. Health probe loop in `recovery_watchdog` restarts mihomo on 2 consecutive failures

### Windows — anonymous WARP registration
1. UI button → `register_warp_profile` command
2. `core::warp` generates a Curve25519 keypair via `x25519-dalek`
3. POSTs the public key to `api.cloudflareclient.com/v0a2158/reg` with anonymous-tier headers
4. Decodes `client_id` → first 3 bytes become the `reserved` field
5. Materialises a Clash profile using mihomo's `wireguard` proxy type

### Proxy switching (both platforms)
1. UI selects node in a group
2. `MihomoAPIClient.switchProxy(...)` → `PUT http://127.0.0.1:9090/proxies/<group>`
3. mihomo immediately switches active proxy

## Conventions

- **Force unwraps banned.** macOS uses `guard` / `if let` / `throw`; Rust uses
  `?` and explicit `match`. CI greps for `.first!` / `.unwrap()` regressions.
- **Dependency injection** via constructors (no singletons except where intentional).
- **TDD-ish.** Swift tests live in `Tests/RiptideTests/`; Rust tests live alongside
  source under `#[cfg(test)] mod tests`. Always add tests for new behavior that
  isn't covered.
- **Model types** are `struct` / `enum` with `Equatable, Sendable, Codable` (Swift)
  and `#[derive(Debug, Clone, Serialize, Deserialize)]` (Rust). Error enums add
  `LocalizedError` (Swift) / `thiserror::Error` (Rust).
- **Tauri commands** are `async fn` returning `Result<T, String>`; map errors at
  the boundary with `.map_err(|e| e.to_string())`. Use a single struct return so
  the TS side can type-check it via `src/services/tauri.ts`.
- **YAML on Windows:** when editing user profiles, round-trip through
  `serde_yaml::Value`, not `ClashRawConfig`, so unknown keys survive.
- **Paths on Windows:** route everything through `WindowsDirs` so the app stays
  rooted at `%APPDATA%\Riptide\`. Never use Tauri's bundle-identifier path
  (`com.riptide.app`) — they don't match.

## Security Practices

### YAML injection prevention (macOS mihomo config gen)
All user-provided strings in mihomo configs are escaped via `yamlEscape()`:
```swift
private static func yamlEscape(_ string: String) -> String {
    let specialChars = CharacterSet(charactersIn: "#\"'{}[]\n,&*?|<>!=%@")
    if string.rangeOfCharacter(from: specialChars) == nil { return string }
    var escaped = string.replacingOccurrences(of: "\\", with: "\\\\")
                      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}
```

### Path validation
The macOS privileged helper validates config paths are within
`~/Library/Application Support/Riptide/mihomo/` before operating — prevents access
to arbitrary files as root.

### Windows secrets
`webdav_config.json` stores the WebDAV password DPAPI-encrypted via
`CryptProtectData` (`core::secrets`) so it never sits in plaintext on disk.

### Diagnostics safety
`collect_diagnostic_report` (Windows) and the macOS equivalent **explicitly omit**:
profile YAML contents, active connection list, WebDAV credentials. The report is
safe to attach to a bug.

## File System Layout

### macOS
```
~/Library/Application Support/Riptide/
├── mihomo/              # mihomo sidecar
│   ├── config.yaml
│   ├── config.yaml.bak
│   ├── cache/GeoIP.dat, GeoSite.dat
│   └── logs/mihomo.log
└── profiles/            # User profile YAMLs

/Library/PrivilegedHelperTools/        # RiptideHelper (SMJobBless)
/Library/Application Support/Riptide/  # Installed mihomo binary
```

### Windows
```
%APPDATA%\Riptide\                     # user-scope state (everything)
├── profiles\
│   ├── <name>__<uuid>.yaml            # profile YAML
│   └── <name>__<uuid>.meta.json       # sidecar metadata
├── active.json                        # selected profile id
├── dns_policy.json                    # DNS overrides
├── region_preset.json
├── tls_tricks.json
├── kill_switch.json
├── webdav_config.json                 # DPAPI-encrypted password
├── mihomo\
│   ├── mihomo.exe                     # pinned via SHA-256
│   └── config.yaml                    # generated, do not edit by hand
├── logs\
│   └── riptide.log.<date>
└── geoip.metadb, geosite.dat

%PROGRAMDATA%\Riptide\                 # machine-scope (SYSTEM-readable)
└── service.conf                       # launch params for tun service
```

## Releases

Tags follow `vX.Y.Z`. `.github/workflows/release.yml` triggers on tag push and:
1. Builds macOS universal binary on `macos-15`, packages a `.dmg` + universal
   `.zip`
2. Builds Windows NSIS + MSI on `windows-latest`
3. Creates a GitHub Release via `softprops/action-gh-release@v2` with all
   artifacts attached. CHANGELOG.md's top entry is used as the release notes.

To cut a new release:
```bash
./Scripts/bump-version.sh 2.1.0       # Updates .version + all per-platform files
# Edit CHANGELOG.md to add the new entry at the top
git add -A && git commit -m "chore: bump version to 2.1.0"
git tag -a v2.1.0 -m "Riptide v2.1.0"
git push origin master --follow-tags
```

The workflow takes ~25 minutes end-to-end.

## Known Limitations

1. **macOS helper signing:** `RiptideHelper/Resources/Info.plist` requires a valid
   Apple Developer Team ID for SMJobBless. Without it, TUN still works via the
   sudo + mihomo gVisor fallback path, but the system-proxy guard isn't available.
2. **QUIC transport (Swift Engine):** requires macOS 14+ (`NWProtocolQUIC`).
3. **Windows auto-updater:** infrastructure is in place but the Tauri signing
   keypair isn't pinned in `tauri.conf.json` yet, so the in-app update check
   surfaces a "download new version" button rather than auto-installing.
4. **Windows MITM:** scaffolded but not production-ready.
5. **Cloudflare WARP API** on Windows is unofficial and can drift; we log the
   HTTP body on failure so changes are easy to diagnose.

## References

- [mihomo documentation](https://wiki.metacubex.one/)
- [Clash configuration format](https://github.com/Dreamacro/clash/wiki/configuration)
- [SMJobBless sample](https://developer.apple.com/library/archive/samplecode/SMJobBless/)
- [Tauri 2 docs](https://v2.tauri.app/)
