<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20Windows%2010%2B%20%7C%20Linux-blue?logo=apple" alt="Platforms" />
  <img src="https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/tests-593%20passed-brightgreen" alt="Tests" />
  <img src="https://img.shields.io/badge/version-2.8.0-blue" alt="Version" />
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="License" />
  <img src="https://img.shields.io/badge/status-stable-brightgreen" alt="Status" />
</p>

<h1 align="center">⚡ Riptide</h1>

<p align="center">
  <strong>A Clash-compatible proxy client, built once in Swift and shipped on macOS, Windows, and Linux.</strong><br/>
  Library-first architecture · mihomo-powered runtime · Cross-platform packaging
</p>

> **What ships today (v2.8.0):** macOS is the primary development target with a SwiftUI app + Swift-first proxy library; Windows is a Tauri 2 port (`riptide-windows/`) sharing the same Clash YAML profile format; Linux is built by CI but not yet packaged. iOS support is **not** planned — see the archived `docs/_archive/riptide-ios-stub/`.

<p align="center">
  <a href="#-why-riptide">Why Riptide?</a> ·
  <a href="#-features">Features</a> ·
  <a href="#-architecture">Architecture</a> ·
  <a href="#-getting-started">Getting Started</a> ·
  <a href="#-building--testing">Building &amp; Testing</a> ·
  <a href="#-contributing">Contributing</a>
</p>

---

## Why Riptide?

Most Clash-compatible clients wrap a Go core (mihomo / sing-box) in Electron or Tauri. Riptide takes a different path: a **Swift-first** library implements protocol framing, DNS, rule matching, and connection orchestration natively — while production traffic can delegate to the battle-tested [mihomo](https://github.com/MetaCubeX/mihomo) sidecar (macOS) or to the mihomo REST API directly (Windows) where a protocol needs it.

This gives you:

- **Native look & feel** — SwiftUI interface on macOS, ~15 MB bundle, instant startup
- **Cross-platform packaging** — one `vX.Y.Z` tag builds a 7-asset release: macOS DMG + ZIP, Windows MSI + NSIS, Linux deb + AppImage
- **Library-first** — the `Riptide` Swift package is usable standalone, independent of the GUI; the macOS app, the `riptide` CLI, and the Windows service all share the same proxy profile format
- **Clash-compatible** — drop in your existing `.yaml` configs and subscriptions
- **Transparent boundaries** — Swift-native code and delegated sidecar/runtime paths are called out explicitly in the feature status table

> **Mode recommendation (macOS):** **System Proxy** is the rock-solid daily driver — the proxy core (an in-process sing-box) runs entirely in user space and points the macOS system proxy at itself via `networksetup`, so it needs **no root, helper, or password**. **TUN mode** captures *all* traffic at the packet level (covers apps that ignore the HTTP proxy, UDP, games) but creating the `utun` + routes requires root: Riptide installs a small launchd daemon on first use (one administrator-password prompt), after which TUN toggles with no further prompts. See [macOS TUN mode](#macos-tun-mode) below.

---

## ✨ Features

**Status key:** ✅ native Swift path · 🔵 delegated to a production core (mihomo or embedded GoCore/sing-box) · 🟡 partial / experimental · 🧱 scaffold only

### Proxy Protocols

Shadowsocks AEAD ✅ · VLESS / Reality ✅ · Trojan ✅ · Snell v2/v3 ✅ · SOCKS5 ✅ · HTTP CONNECT ✅ · VMess 🔵 (production via mihomo; native implementation incomplete) · Hysteria2 🔵/🟡 (production via mihomo; native QUIC path experimental) · TUIC 🔵/🟡 (production via mihomo; native path experimental, single-stream) · WireGuard 🔵/🟡 (Clash fields parsed and embedded GoCore/sing-box JSON generated; pure Swift protocol handler not implemented)

### Transport

TCP (`NWConnection`) ✅ · TLS ✅ · WebSocket ✅ · HTTP/2 🟡 (URLSession stream / TLS wrapper; true H/2 CONNECT and multiplexing planned) · QUIC ✅ (macOS 14+) · Connection Pool ✅ · Multiplex 🟡 (client-initiated only)

### DNS (fully self-developed)

UDP · TCP · DNS-over-HTTPS · DNS-over-TLS · DNS-over-QUIC (RFC 9250) · FakeIP · Cache · Domain Sniffing · Pipeline with Fallback · Hosts Override · **Nameserver-policy** (per-domain DNS resolver routing)

### Rule engine

`DOMAIN` / `DOMAIN-SUFFIX` / `DOMAIN-KEYWORD` · `IP-CIDR` / `IP-CIDR6` · `SRC-IP-CIDR` · `SRC-PORT` / `DST-PORT` · `PROCESS-NAME` · `GEOIP` (native MMDB parser) · `GEOSITE` · `IP-ASN` · `RULE-SET` · `SCRIPT` (JavaScript) · `NOT` / `REJECT` / `MATCH` · visual rule editor with hit preview (W2-3) · config merger

### Proxy groups

`select` · `url-test` · `fallback` · `load-balance` (consistent-hash / round-robin) · `relay` (chain)

### macOS app GUI (8 tabs)

- **Dashboard** — at-a-glance status cards (mode / node / speed), subscription quota bar with expiry countdown, recent connections, one-click diagnostics button
- **Config** — file picker / drag-and-drop / subscription URL with **import preview**; per-profile backup rotation (20 snapshots)
- **Proxy** — group cards with latency testing and one-click switching
- **Traffic** — Swift Charts traffic chart (60s/10m/1h) and connection list with **expandable detail panel** (5-tuple, rule hit tracing, proxy chain, timing)
- **Rules** — visual rule editor with drag-to-reorder, 10 rule types, policy picker, hit preview
- **Logs** — live mihomo log streaming with level filter, search, and export
- **诊断 (Diagnostics, v2.8.0)** — persistent diagnostic event journal (Logbook) with level / category / date filters, JSONL export, and clear. Closes the gap between "what's happening right now" (Logs) and "what happened across restarts" (Diagnostics)
- **Settings** — unified settings container for Network, MITM, Rewrite, Updates, Core, Diagnostics, WebDAV, Language, Theme

### Node editor

- Real-time validation, protocol-specific forms, add/edit/delete/duplicate
- **Override schema (v2.8.0)** — per-profile YAML overlays with `meta.replace` and `removed:` semantics, applied at runtime via `OverrideStore`
- **QR code share (v2.8.0)** — generate industry-standard share URIs for 6 protocols (ss / vmess / vless / trojan / hysteria2 / tuic); per-row QR code + batch "Share All"

### Menu bar extra

- Status icon, traffic speed, popover with mode / group / speed / shortcuts
- Network environment auto-switch — detect WiFi SSID changes, auto-switch proxy mode + profile

### Infrastructure

- **WebDAV sync** — cross-device config synchronization (DPAPI-encrypted password on Windows, Keychain on macOS)
- **External controller** — Clash-compatible REST API + WebSocket streaming (traffic & connections)
- **CLI** — `riptide validate`, `riptide run`, `riptide smoke`
- **Subscription auto-update** — background scheduler with configurable intervals
- **Rule set auto-update** — periodic refresh of remote rule sets integrated into profile lifecycle
- **Config backup/restore** — automatic backup on profile switch, manual backup, restore from history (max 20)
- **Kill Switch (On-Demand VPN)** — blocks all traffic when VPN is disconnected
- **Sleep/Wake + Network-change recovery** — restores the runtime after Mac sleep/wake and WiFi/Ethernet transitions
- **Graceful node degradation** — automatically fails over to next available proxy when a node is unreachable
- **Adaptive startup** — exponential backoff readiness check (100ms→2s)
- **Diagnostic reports** — `GET /diagnostics` REST + WebSocket endpoints with structured JSON reports (credentials excluded)
- **Connection timing metrics** — per-connection policy resolution and proxy connect latency
- **System proxy guard** — monitors and auto-restores system proxy settings if externally modified
- **TUN auto-recovery** — continuous interface health monitoring with automatic mihomo restart
- **XPC helper maturation** — automatic reconnection with exponential backoff, 30s heartbeat, version validation
- **Unified error handling** — `RiptideError` enum with `LocalizedError` conformance for 17 subsystems
- **First-run onboarding** — guided setup wizard with helper install and config import
- **MITM** 🟡 (experimental — CA generation/install, per-host certificates, CONNECT TLS termination/re-encryption, host whitelist UI, interception log)
- **Sparkle auto-update** — Cmd+Shift+U or settings panel, stable/beta channels
- **9 languages** — en / zh-Hans / ja / ru / es / ko / fa / pt-BR / vi + system auto-detect
- **Apple Shortcuts** — `SwitchProxyMode` + `SelectProfile` Intents (Shortcuts.app discoverable)
- **Touch Bar support** — node switching on Touch Bar MacBook Pros

### Persistent diagnostics (v2.8.0)

- **Logbook** — JSONL-per-UTC-day journal at `~/Library/Application Support/Riptide/logbook/YYYY-MM-DD.jsonl`
- 5 fire-and-forget writers (`ModeCoordinator`, `SubscriptionManager`, `HelperToolConnection`, `MihomoRuntimeManager`, `OverrideStore`) — diagnostic logging never blocks business paths
- Skip-malformed-line read, date-range + level + category + host filter, clear, export
- Diff-based closed-connection watcher (data model + algorithm in v2.8.0; runtime tick loop is the v2.4.x follow-up)

---

## 🏗 Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                    macOS — RiptideApp (SwiftUI)                       │
│  Dashboard · Config · Proxy · Traffic · Rules · Logs · 诊断 · Settings│
│                       │                                               │
│              ┌────────▼─────────┐                                     │
│              │   AppViewModel   │  ──── LogbookContainer ────► JSONL  │
│              └─┬──────┬──────┬──┘                                     │
│   ModeCoordinator  Subscription  OverrideStore  ...                   │
│       │            Manager          │                                │
│  ┌────▼─────────────────────────────▼────────────┐                   │
│  │         MihomoRuntimeManager  + Helper XPC    │                   │
│  │     Config Gen · REST :9090 · gVisor TUN      │                   │
│  └──────┬──────────────────────────┬─────────────┘                   │
└─────────┼──────────────────────────┼─────────────────────────────────┘
          │ XPC (root)                │ spawn
┌─────────▼─────────────┐    ┌────────▼────────────┐
│  RiptideHelper        │    │   mihomo sidecar    │
│  (SMJobBless)          │    │   native Go binary  │
└───────────────────────┘    └─────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                Riptide Library (pure Swift, 32 subdirs)               │
│  AppShell · Bridge · Config · Connection · Control · Core · DNS     │
│  Diagnostics · Groups · HealthCheck · LocalProxy · Logbook · Logging │
│  MITM · Mihomo · Models · NodeEditor · Override · Protocols          │
│  ProxyProvider · QRCode · Rules · Scripting · SingBox · Subscription  │
│  Sync · Traffic · Transport · Tunnel · Utils · VPN · XPC            │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                  Windows — riptide-windows/ (Tauri 2)                 │
│   React + TypeScript UI  ─►  Rust backend  ─►  mihomo REST API        │
│   riptide-tun-service.exe (SYSTEM) for unprivileged TUN              │
└──────────────────────────────────────────────────────────────────────┘
```

### Request flow (System Proxy / TUN)

```
Local Proxy / TUN packet
  → LiveTunnelRuntime.openConnection()
    → RuleEngine.resolve() → RoutingPolicy
    → ProxyConnector.connect(via: node, to: target)
      → Transport session (TCP / TLS / WS / QUIC / HTTP2)
      → Protocol handshake (SS / VMess / VLESS / Trojan / Hy2 / Snell / TUIC)
      → Bidirectional data relay
```

### Runtime modes

| Mode | Status | Description |
|------|--------|-------------|
| **System Proxy** | Stable | macOS: in-process **sing-box** core + `networksetup` (no root/helper/sudo). Windows: direct REST + system-proxy configuration with a 3s drift-guard |
| **TUN Mode** | Beta | Full packet-level interception. macOS: a standalone sing-box core run as **root** via a one-time launchd-daemon install (one admin prompt; prompt-free thereafter) — no Network Extension entitlement needed. Windows: `riptide-tun-service.exe` registered as a SYSTEM service |

#### macOS TUN mode

macOS can't create a `utun` device or change the routing table from an unentitled
GUI app, so Riptide runs the proxy core as **root** for TUN — the same approach
Hiddify uses on desktop — and does so **without** an Apple Developer account /
Network Extension entitlement:

1. **The first time you enable TUN**, Riptide shows one macOS administrator-password
   prompt and installs a launchd daemon (`com.riptide.tun`) that runs a bundled
   standalone `riptide-singbox` core. It is the *same* sing-box v1.9 (+`with_utls`)
   build the app links in-process for system-proxy mode, so the two cores accept
   identical configs.
2. The daemon's `KeepAlive.PathState` watches a flag file, so **enabling/disabling
   TUN afterwards just creates/removes that flag** — launchd starts the root core
   when the flag appears and sends it `SIGTERM` (clean route teardown) when it's
   removed. **No further password prompts.**
3. The generated config and flag live in `/Library/Application Support/Riptide/tun/`
   (mode `0700`, owned by you), so your node credentials aren't readable by other
   local users.

**Trade-offs (vs a signed Network Extension):** one admin prompt at install time;
a `LaunchDaemon` plist remains in `/Library/LaunchDaemons/`; switching nodes
mid-session isn't supported yet in TUN mode (the elevated daemon exposes no
clash-api). System-proxy mode has none of these caveats and needs no password.

**Remove the TUN daemon** entirely, if you ever want to:

```bash
sudo launchctl bootout system/com.riptide.tun 2>/dev/null
sudo rm -f /Library/LaunchDaemons/com.riptide.tun.plist
sudo rm -rf "/Library/Application Support/Riptide/tun" \
            "/Library/Application Support/Riptide/riptide-singbox"
```

---

## 🚀 Getting Started

### Prerequisites

- macOS 14.0 (Sonoma) or later for the macOS build
- Windows 10+ with WebView2 for the Windows build
- ~15 MB disk for the macOS app, plus ~50 MB for the bundled mihomo core on first launch
- Swift 6.2+ / Xcode 16+ (only for building macOS from source)
- Node 20+ and Rust 1.75+ (only for building Windows from source)

### Install (macOS)

Riptide v2.8.0 is distributed through three channels, **with no `xattr -cr` workaround required** when the build is signed and notarized (the recommended configuration). Pick whichever fits your setup:

#### Option 1 — Homebrew (recommended)

```bash
brew tap G3niusYukki/riptide
brew install riptide
```

Then launch Riptide from Launchpad, Spotlight, or `open -a Riptide`. To update later, `brew update && brew upgrade riptide`.

> **Tap note:** the `G3niusYukki/homebrew-tap` repository is created and published on the first tagged release by `.github/workflows/homebrew.yml`.

#### Option 2 — Direct download (DMG)

1. Open the [latest release page](https://github.com/G3niusYukki/Riptide/releases/latest)
2. Download `Riptide-X.Y.Z-universal.dmg`
3. Double-click to mount, drag **Riptide** into `/Applications`
4. Launch from Launchpad or `open -a Riptide`

Signed DMGs are verified by Gatekeeper automatically — no Terminal commands, no "unidentified developer" warnings. If you ever do see such a warning, the build is not signed (e.g. a local dev build) and you should fall back to Option 3.

#### Option 3 — Build from source (developers)

```bash
git clone https://github.com/G3niusYukki/Riptide.git
cd Riptide
./Scripts/download-mihomo.sh   # fetches the mihomo sidecar binary
swift build                    # build all targets
swift run RiptideApp           # launch the SwiftUI app
```

Local dev builds are **unsigned**; macOS will quarantine the binary on first run. For the cleanest experience use a signed release (Options 1 or 2) or sign the build yourself with your own Developer ID — see `docs/signing-setup.md`.

### Install (Windows)

1. Open the [latest release page](https://github.com/G3niusYukki/Riptide/releases/latest)
2. Download `Riptide_X.Y.Z_x64-setup.exe` (NSIS installer) or `Riptide_X.Y.Z_x64_en-US.msi` (MSI)
3. Run the installer; the app is registered in Add/Remove Programs
4. TUN mode requires admin (one-time). The first time you select TUN, Riptide prompts for elevation to install the `RiptideTUN` Windows service

### Auto-update

Once installed, Riptide checks for new releases in the background via [Sparkle](https://sparkle-project.org/) (macOS). You'll be notified in the menu bar when an update is available; the update is **edDSA-signed** against the public key bundled in `Riptide.entitlements` so the feed itself cannot be tampered with. You can also trigger a manual check from **Settings → Updates → Check Now**, or via the global hotkey **⌘⇧U**.

For a deeper walkthrough (including uninstall, TUN-mode helper install, and troubleshooting), see **[docs/INSTALL.md](docs/INSTALL.md)**.

---

## 🧪 Building & Testing

### macOS

```bash
swift build                              # library + CLI + app
swift test                               # 593 tests, 93 suites
swift test --filter "RuleEngine"         # single suite
swift test --filter "LogbookStore"       # v2.8.0 Logbook suite
swift run RiptideApp                     # launch UI
swift run riptide --help                 # CLI
./Scripts/download-mihomo.sh             # fetch mihomo for sidecar mode
./Scripts/build-release.sh               # build + sign a release bundle
./Scripts/bump-version.sh 2.8.0         # coordinated version bump
```

### Windows

```bash
cd riptide-windows
npm install
npm run tauri dev                        # dev mode (hot-reload UI)
npm run tauri build                      # release NSIS + MSI bundle
```

**Tauri version alignment is enforced:** the JS `@tauri-apps/api` and the Rust `tauri` crate must agree on minor versions or `tauri build` refuses to bundle. Keep `riptide-windows/package.json` pinned to whatever crates.io currently publishes (currently `~2.10`).

---

## 📁 Project Structure

```
.version                            # canonical version, read by every bundler
Package.swift                       # macOS SwiftPM manifest
Sources/
├── Riptide/                        # Pure-Swift core library (32 subdirs)
│   ├── AppShell/  Bridge/  Config/  Connection/  Control/  Core/
│   ├── DNS/  Diagnostics/  Groups/  HealthCheck/  LocalProxy/
│   ├── Logbook/  Logging/  MITM/  Mihomo/  Models/  NodeEditor/
│   ├── Override/  Protocols/  ProxyProvider/  QRCode/  Rules/
│   ├── Scripting/  SingBox/  Subscription/  Sync/  Traffic/
│   ├── Transport/  Tunnel/  Utils/  VPN/  XPC/  Riptide.swift
├── RiptideApp/                     # SwiftUI macOS app target
│   ├── App/  Assets.xcassets/  Intents/  Localization/
│   ├── RiptideApp.swift  AppViewModel.swift  SMJobBlessManager.swift
│   ├── MenuBarScene.swift  ViewModels/  Views/
│   └── Views/                      # tab views + subdirs:
│       ├── Dashboard/  Diagnostics/  MenuBar/  Rules/  Scenes/  Settings/
├── RiptideCLI/                     # `riptide` command-line tool
├── RiptideTunnel/                  # NetworkExtension (macOS only)
RiptideHelper/                      # privileged XPC service (SMJobBless)
Tests/RiptideTests/                 # 593 tests / 93 suites
RiptideAppUITests/                  # 38 UI tests / 11 suites
Scripts/                            # build-release.sh, bump-version.sh, signing
homebrew/                           # Homebrew Formula + auto-update workflow
riptide-windows/                    # Windows Tauri port (self-contained subtree)
rules/                              # bundled rule-sets (cn-domain, geoip-cn, …)
site/                               # VitePress documentation site
docs/                               # public design docs
docs/_archive/                      # archived iOS / Go stubs
```

For an authoritative description of every directory's responsibility, see **[AGENTS.md](AGENTS.md)**.

---

## 🔒 Security

> Status reflects the v2.8.0 configuration. Items marked *(when configured)* activate automatically once the corresponding credentials are provided to the release pipeline — see [`docs/signing-setup.md`](docs/signing-setup.md).

### Distribution integrity

- **Code signed** *(when Developer ID is configured)* — the release build is signed with a `Developer ID Application` certificate by `.github/workflows/release.yml`, applied with the hardened-runtime flag. Unsigned local builds remain supported for development.
- **Notarized by Apple** *(when notarization credentials are configured)* — signed DMGs are submitted to `notarytool` and stapled, so Gatekeeper verifies them on first launch with no warnings and no `xattr -cr` workaround needed.
- **Sparkle updates are edDSA-signed** — `Scripts/sign-sparkle-update.sh` signs every released DMG; the public key is bundled in `Riptide.entitlements` as `SUPublicEDKey`, so the appcast feed is authenticated end-to-end and cannot be tampered with in transit.
- **Windows installers are Authenticode-signed** *(when code-signing certificate is configured)* — MSI and NSIS bundles are signed via `signtool` with a timestamped SHA-256 signature.

### Runtime hardening

- **Hardened runtime** is enabled in `Riptide.entitlements` (`com.apple.security.cs.allow-jit`, `allow-unsigned-executable-memory`, `disable-library-validation` for the mihomo sidecar).
- **TLS verification** is enforced by `Network.framework` — there is no global `skip-cert-verify`; per-node `skip-cert-verify: true` is honoured but disabled by default.
- **Privileged helper** boundary: the XPC helper launches mihomo **only** from `/Library/Application Support/Riptide/mihomo/`, validates all config paths, and refuses to execute arbitrary commands.
- **Windows service** boundary: `riptide-tun-service.exe` runs as `SYSTEM` and writes only to `%PROGRAMDATA%\Riptide\`. All user-scope state is rooted at `%APPDATA%\Riptide\`.
- **Proxy credentials** are never written to logs. The diagnostic report (Diagnostics tab + `GET /diagnostics` REST) explicitly omits profile YAML contents, active connection list, and WebDAV credentials.
- **macOS TUN mode** runs a bundled standalone sing-box core as `root` via a launchd daemon (`com.riptide.tun`), gated by a `KeepAlive.PathState` flag file — it does **not** require a Network Extension entitlement. The daemon's working dir (`/Library/Application Support/Riptide/tun/`, mode `0700`) holds only the generated config + flag; system-proxy mode runs entirely in user space with no elevation.

### Sandbox status (honest)

- The shipped macOS app is **not** sandboxed. `Riptide.entitlements` sets `com.apple.security.app-sandbox = false`. This is intentional: Riptide is distributed outside the Mac App Store, and the helper tool / mihomo sidecar / system proxy guard require capabilities that the App Sandbox does not grant.
- For Mac App Store submission the sandbox would need to be re-enabled and the entitlement set trimmed accordingly — see [`docs/MAC-APP-STORE-CHECKLIST.md`](docs/MAC-APP-STORE-CHECKLIST.md). v2.8.0 does **not** ship to the App Store.
- **Reporting vulnerabilities:** please open a GitHub issue or contact the maintainers privately (do not include credentials or node URIs in reports).

---

## 🤝 Contributing

Contributions are welcome! A few guidelines:

1. **Library-first** — new protocol / transport logic belongs in `Sources/Riptide/`, not the app layer
2. **Swift 6 strict concurrency** — all code must pass `Sendable` and actor isolation checks
3. **Test coverage** — add tests for new behavior; `swift test` must pass (593 / 593)
4. **No force unwraps** in production — use proper error handling with typed error enums
5. **No silent fallbacks** — fail explicitly rather than silently degrading. The one allowed exception is fire-and-forget diagnostic logging (Logbook), and only because business paths must never block on diagnostic writes
6. **Dependency injection** over hard-coded global behavior. For v2.8.0+ cross-cutting concerns, the pattern is `Module.setFoo(dependency) async` on actors + a single injection site in `AppViewModel.init`

See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the full contribution workflow, PR conventions, and release process.

---

## 📄 License

[MIT](LICENSE) — free to use, modify, and distribute.

---

## Acknowledgments

- **[mihomo](https://github.com/MetaCubeX/mihomo)** — the proxy core powering Riptide's production runtime
- **[Clash](https://github.com/Dreamacro/clash)** — original configuration format Riptide is compatible with
- **[Yams](https://github.com/jpsim/Yams)** — YAML parsing
- **[swift-certificates](https://github.com/apple/swift-certificates)** — X.509 certificate handling
- **[Sparkle](https://sparkle-project.org/)** — macOS auto-update framework
- **[Tauri](https://tauri.app/)** — Windows + Linux app shell
