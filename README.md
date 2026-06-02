<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?logo=apple" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/tests-505%20passed-brightgreen" alt="Tests" />
  <img src="https://img.shields.io/badge/version-2.3.0-blue" alt="Version" />
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="License" />
  <img src="https://img.shields.io/badge/status-stable-brightgreen" alt="Status" />
</p>

<h1 align="center">⚡ Riptide</h1>

<p align="center">
  <strong>A native macOS proxy client built with SwiftUI and a Swift-first core.</strong><br/>
  Library-first architecture · Clash-compatible · mihomo-powered runtime
</p>

> **Platform Support:** Riptide v3.0.0 targets **macOS only**. iOS support is not planned for the v3.0.0 release. Archived iOS stubs are available in `docs/_archive/riptide-ios-stub/` for reference.

<p align="center">
  <a href="#-features">Features</a> ·
  <a href="#-architecture">Architecture</a> ·
  <a href="#-getting-started">Getting Started</a> ·
  <a href="#-building--testing">Building</a> ·
  <a href="#-contributing">Contributing</a>
</p>

---

## Why Riptide?

Most macOS proxy clients wrap a Go core (mihomo / sing-box) in Electron or Tauri. Riptide takes a different path: a **Swift-first** library implements protocol framing, DNS, rule matching, and connection orchestration natively — while production traffic can delegate to the battle-tested [mihomo](https://github.com/MetaCubeX/mihomo) sidecar or the embedded GoCore/sing-box bridge where a protocol needs it.

This gives you:

- **Native look & feel** — SwiftUI interface, ~15 MB bundle, instant startup
- **Library-first** — the `Riptide` Swift package is usable standalone, independent of the GUI
- **Clash-compatible** — drop in your existing `.yaml` configs and subscriptions
- **Transparent boundaries** — Swift-native code and delegated sidecar/runtime paths are called out explicitly

> **Mode recommendation:** TUN mode is the most complete interception path — it captures all traffic at the packet level via mihomo's gVisor stack and works regardless of whether the build is signed. System Proxy mode is lighter-weight (HTTP/HTTPS/SOCKS5 only) and is a good fit for everyday browsing.

---

## ✨ Features

### Proxy Protocols

Status key: ✅ native Swift path · 🔵 delegated to a production core (mihomo or embedded GoCore/sing-box) · 🟡 partial / experimental · 🧱 scaffold only

Shadowsocks AEAD ✅ · VLESS / Reality ✅ · Trojan ✅ · Snell v2/v3 ✅ · SOCKS5 ✅ · HTTP CONNECT ✅ · VMess 🔵 (production via mihomo; native implementation incomplete) · Hysteria2 🔵/🟡 (production via mihomo; native QUIC path experimental and fails when QUIC is unavailable) · TUIC 🔵/🟡 (production via mihomo; native path experimental, single-stream) · WireGuard 🔵/🟡 (Clash fields parsed and embedded GoCore/sing-box JSON generated; pure Swift protocol handler not implemented)

### Transport

TCP (`NWConnection`) ✅ · TLS ✅ · WebSocket ✅ · HTTP/2 🟡 (URLSession stream / TLS wrapper; true H/2 CONNECT and multiplexing planned) · QUIC ✅ (macOS 14+) · Connection Pool ✅ · Multiplex 🟡 (client-initiated only)

### DNS (Fully Self-Developed)

UDP · TCP · DNS-over-HTTPS · DNS-over-TLS · DNS-over-QUIC (RFC 9250) · FakeIP · Cache · Domain Sniffing · Pipeline with Fallback · Hosts Override

### Rule Engine

DOMAIN / DOMAIN-SUFFIX / DOMAIN-KEYWORD · IP-CIDR / IP-CIDR6 · SRC-IP-CIDR · SRC-PORT / DST-PORT · PROCESS-NAME · GEOIP (native MMDB parser) · GEOSITE · IP-ASN · RULE-SET · SCRIPT (JavaScript) · NOT / REJECT / MATCH · Config Merger

### Proxy Groups

`select` · `url-test` · `fallback` · `load-balance` (consistent-hash / round-robin) · `relay` (chain)

### App GUI

- **Dashboard** — at-a-glance status cards (mode / node / speed), subscription quota bar with expiry countdown, recent connections, one-click diagnostics button
- Config import (file picker / drag-and-drop / subscription URL) with **import preview**
- **Node editor** with real-time validation, protocol-specific fields, add/edit/delete/duplicate
- **Rule editor** with drag-to-reorder, 10 rule types, policy picker
- **Config merge UI** — add merge sources (file/manual), preview diffs, one-click apply
- **Config backup/restore** — automatic backup on profile switch, manual backup, restore from history (20-backup rotation)
- **Rule set auto-update** — periodic refresh of remote rule sets with status display
- Proxy group cards with latency testing and one-click switching
- Real-time traffic chart (Swift Charts, 60s/10m/1h) and connection list with **expandable detail panel** (5-tuple, rule hit tracing, proxy chain, timing)
- Log viewer with level filter, search, and export
- Menu bar extra with status icon and traffic speed
- **Subscription quota** — parse `subscription-userinfo` header, display traffic bar + expiry countdown in dashboard
- **Nameserver-policy** — per-domain DNS routing (e.g. `geosite:cn` → domestic DNS, default → DoH)
- **HTTP Rewrite engine** — URL regex reject/redirect/header-modify rules (Surge-compatible format)
- **One-click diagnostics** — 6 checks: helper, core binary, connectivity, DNS, proxy ports, config integrity
- **Sparkle auto-update** — Cmd+Shift+U or settings panel, stable/beta channels
- **Network environment auto-switch** — detect WiFi SSID changes, auto-switch proxy mode + profile
- MITM 🟡 (experimental — CA generation/install, per-host certificates, CONNECT TLS termination/re-encryption, host whitelist UI, interception log)
- **Theme** — System / Light / Dark with segmented picker in Settings
- **10 languages** — en / zh-Hans / ja / ru / es / ko / fa / pt-BR / vi + system auto-detect
- Global hotkeys
- **Apple Shortcuts** — SwitchProxyMode + SelectProfile Intents (Shortcuts.app discoverable)
- **4 languages**: English · 简体中文 · 日本語 · Русский

### Infrastructure

- **WebDAV sync** — cross-device config synchronization
- **External controller** — Clash-compatible REST API + WebSocket streaming (traffic & connections)
- **CLI** — `riptide validate`, `riptide run`, `riptide smoke`
- **Subscription auto-update** — background scheduler with configurable intervals (5-minute check cycle)
- **Rule set auto-update** — periodic refresh of remote rule sets integrated into profile lifecycle
- **Config backup/restore** — automatic backup on profile switch, manual backup, restore from history (max 20 backups)
- **Kill Switch (On-Demand VPN)** — blocks all traffic when VPN is disconnected, preventing IP/DNS leaks
- **Sleep/Wake recovery** — automatically restores the runtime after Mac sleep/wake cycles
- **Network change recovery** — detects WiFi/Ethernet transitions and re-establishes connections
- **Graceful node degradation** — automatically fails over to next available proxy when a node is unreachable
- **Adaptive startup** — exponential backoff readiness check (100ms→2s) eliminates fixed-delay startup pauses
- **Diagnostic reports** — `GET /diagnostics` REST + WebSocket endpoints with structured JSON reports
- **Connection timing metrics** — per-connection policy resolution and proxy connect latency tracking
- **System proxy guard** — monitors and auto-restores system proxy settings if externally modified
- **TUN auto-recovery** — continuous interface health monitoring with automatic mihomo restart on failure
- **XPC helper maturation** — automatic reconnection with exponential backoff, 30s heartbeat, 3s timeout protection, version validation
- **Unified error handling** — `RiptideError` enum with `LocalizedError` conformance for 17 subsystems
- **First-run onboarding** — guided setup wizard with helper install and config import

---

## 🏗 Architecture

```
  ┌─────────────────────────────────────────────────────┐
  │               RiptideApp (SwiftUI)                    │
  │                                                       │
  │  Config · Proxy · Traffic · Rules · Logs              │
  │                    │                                  │
  │            ┌───────▼───────┐                          │
  │            │  AppViewModel │                          │
  │            └───────┬───────┘                          │
  │       ┌────────────┼────────────┐                     │
  │  ModeCoordinator  Subscription  Hotkey               │
  │       │            Manager      Manager               │
  │  ┌────▼─────────────────────────────┐                │
  │  │     MihomoRuntimeManager         │                │
  │  │  Config Gen · XPC · REST Client  │                │
  │  └────┬────────────────────────────┘                │
  └───────┼──────────────────────────────────────────────┘
          │
  ┌───────▼──────┐        ┌───────────────────────────┐
  │ mihomo core   │  XPC   │ RiptideHelper (gated)      │
  │ · Proxy Proto │◄──────►│ · TUN / helper scaffolding │
  │ · REST :9090  │        │ · Not product-ready yet     │
  │ · TUN Stack   │        └───────────────────────────┘
  └──────────────┘

  ┌─────────────────────────────────────────────────────┐
  │            Riptide Library (Swift-first)              │
  │                                                       │
  │  Protocols  ·  Transport  ·  DNS  ·  Rules           │
  │  Connection ·  Tunnel     ·  MITM ·  Control         │
  │  Groups     ·  Sync       ·  Subscription · Scripting│
  └─────────────────────────────────────────────────────┘
```

### Request Flow

```
Local Proxy / TUN packet
  → LiveTunnelRuntime.openConnection()
    → RuleEngine.resolve() → RoutingPolicy
    → Proxy_connector.connect(via: node, to: target)
      → Transport session (TCP / TLS / WS / QUIC / HTTP2)
      → Protocol handshake (SS / VMess / VLESS / Trojan / Hy2 / Snell)
      → Bidirectional data relay
```

### Runtime Modes

| Mode | Status | Description |
|------|--------|-------------|
| **System Proxy** | Beta | mihomo sidecar + macOS system proxy configuration with auto-guard (guard requires signed helper) |
| **TUN Mode** | Beta | Full traffic interception via mihomo gVisor TUN + auto-recovery. Requires sudo for first-time helper install; no Network Extension entitlement needed |

---

## 🚀 Getting Started

### Prerequisites

- macOS 14.0 (Sonoma) or later
- ~15 MB disk for the app, plus ~50 MB for the bundled mihomo core on first launch
- Swift 6.2+ / Xcode 16+ (only if building from source)

### Install

Riptide v3.0.0 is distributed through three channels, **with no `xattr -cr` workaround required** when the build is signed and notarized (the recommended configuration). Pick whichever fits your setup:

#### Option 1 — Homebrew (recommended)

```bash
brew tap G3niusYukki/riptide
brew install riptide
```

Then launch Riptide from Launchpad, Spotlight, or `open -a Riptide`. To update later, `brew update && brew upgrade riptide`.

> **Tap note:** the `G3niusYukki/homebrew-tap` repository is created and published on the first tagged release by `.github/workflows/homebrew.yml`. Until the first tagged release ships, install from the DMG below.

#### Option 2 — Direct download (DMG)

1. Open the [latest release page](https://github.com/G3niusYukki/Riptide/releases/latest)
2. Download `Riptide-X.Y.Z-universal.dmg`
3. Double-click to mount, drag **Riptide** into `/Applications`
4. Launch from Launchpad or `open -a Riptide`

Signed DMGs are verified by Gatekeeper automatically — no Terminal commands, no "unidentified developer" warnings. If you ever do see such a warning, it means the build is **not** signed (e.g. a local dev build) and you should fall back to Option 3.

#### Option 3 — Build from source (developers)

```bash
git clone https://github.com/G3niusYukki/Riptide.git
cd Riptide
./Scripts/download-mihomo.sh   # fetches the mihomo sidecar binary
swift build                    # build all targets
swift run RiptideApp           # launch the SwiftUI app
```

Local dev builds are **unsigned**; macOS will quarantine the binary on first run. For the cleanest experience use a signed release (Options 1 or 2) or sign the build yourself with your own Developer ID — see `docs/signing-setup.md`.

### Auto-update

Once installed, Riptide checks for new releases in the background via [Sparkle](https://sparkle-project.org/). You'll be notified in the menu bar when an update is available; the update is **edDSA-signed** against the public key bundled in `Riptide.entitlements` so the feed itself cannot be tampered with. You can also trigger a manual check from **Settings → Updates → Check Now**, or via the global hotkey **⌘⇧U**.

For a deeper walkthrough (including uninstall, TUN-mode helper install, and troubleshooting), see **[docs/INSTALL.md](docs/INSTALL.md)**.

---

## 🧪 Building & Testing

```bash
# Build everything
swift build

# Run full test suite (589 tests listed by `swift test list`)
swift test

# Run a specific suite
swift test --filter "RuleEngine"
swift test --filter "MihomoAPI"
swift test --filter "MITMConfig"

# CLI
swift run riptide --help
swift run riptide validate path/to/config.yaml

# Launch the app
swift run RiptideApp
```

---

## 📁 Project Structure

```
Sources/
├── Riptide/                 # Core library (Swift-first)
│   ├── AppShell/            # App coordinators: mode, profile, system proxy, import
│   ├── Config/              # Clash YAML parsing & deep merge
│   ├── Connection/          # Proxy connection orchestration
│   ├── Control/             # REST API + WebSocket external controller
│   ├── DNS/                 # Full DNS stack: UDP/TCP/DoH/DoT/DoQ + cache + FakeIP
│   ├── Groups/              # Proxy group resolution & load balancing
│   ├── HealthCheck/         # Latency-based health checking & group selection
│   ├── LocalProxy/          # HTTP CONNECT ingress with domain sniffing
│   ├── Logging/             # Structured log types
│   ├── Mihomo/              # Sidecar integration: API, config gen, runtime, logs
│   ├── MITM/                # HTTPS interception: config, CA, TLS termination
│   ├── Models/              # Core data models: ProxyNode, ProxyRule, RoutingPolicy
│   ├── NodeEditor/          # Proxy node editing with validation
│   ├── Protocols/           # Protocol framing: SS, VMess, VLESS, Trojan, Hy2, Snell, SOCKS5
│   ├── ProxyProvider/       # Proxy provider abstraction
│   ├── Rules/               # Rule engine, GeoIP MMDB, GeoSite, ASN, RuleSet, scripts
│   ├── Scripting/           # JavaScript rule evaluation engine
│   ├── SingBox/             # sing-box interop layer + GoCore JSON generation
│   ├── Subscription/        # Subscription manager, scheduler, URI parser
│   ├── Sync/                # WebDAV config sync
│   ├── Traffic/             # Traffic monitoring providers & view models
│   ├── Transport/           # Transport: TCP, TLS, WS, HTTP/2, QUIC, pool, multiplex
│   ├── Tunnel/              # Live runtime state machine & lifecycle
│   ├── Utils/               # Secure storage utilities
│   ├── VPN/                 # TUN providers & packet handling
│   └── XPC/                 # Privileged helper communication
│
├── RiptideApp/              # SwiftUI client
│   ├── App/                 # Theme, hotkeys, drop delegate, tab view, status bar
│   ├── Localization/        # i18n: en, zh-Hans, ja, ru
│   ├── ViewModels/          # AppViewModel, ProxyViewModel, LogViewModel, ...
│   ├── Views/               # All SwiftUI views + settings
│   └── RiptideApp.swift     # App entry point
│
└── RiptideCLI/              # Command-line interface

Tests/RiptideTests/          # 591 tests listed by `swift test list`
```

---

## 🔒 Security

> Status reflects the v3.0.0 GA configuration. Items marked *(when configured)* activate automatically once the corresponding credentials are provided to the release pipeline — see [`docs/signing-setup.md`](docs/signing-setup.md).

### Distribution integrity

- **Code signed** *(when Developer ID is configured)* — the release build is signed with a `Developer ID Application` certificate by `.github/workflows/release.yml`, applied with the hardened-runtime flag. Unsigned local builds remain supported for development.
- **Notarized by Apple** *(when notarization credentials are configured)* — signed DMGs are submitted to `notarytool` and stapled, so Gatekeeper verifies them on first launch with no warnings and no `xattr -cr` workaround needed.
- **Sparkle updates are edDSA-signed** — `Scripts/sign-sparkle-update.sh` signs every released DMG; the public key is bundled in `Riptide.entitlements` as `SUPublicEDKey`, so the appcast feed is authenticated end-to-end and cannot be tampered with in transit.

### Runtime hardening

- **Hardened runtime** is enabled in `Riptide.entitlements` (`com.apple.security.cs.allow-jit`, `allow-unsigned-executable-memory`, `disable-library-validation` for the mihomo sidecar).
- **TLS verification** is enforced by `Network.framework` — there is no global `skip-cert-verify`; per-node `skip-cert-verify: true` is honoured but disabled by default.
- **Privileged helper** boundary: the XPC helper launches mihomo **only** from `/Library/Application Support/Riptide/mihomo/`, validates all config paths, and refuses to execute arbitrary commands.
- **Proxy credentials** are never written to logs.
- **TUN mode** uses mihomo's gVisor stack via sudo — it does not require a Network Extension entitlement.

### Sandbox status (honest)

- The shipped app is **not** sandboxed. `Riptide.entitlements` sets `com.apple.security.app-sandbox = false`. This is intentional: Riptide is distributed outside the Mac App Store, and the helper tool / mihomo sidecar / system proxy guard require capabilities that the App Sandbox does not grant.
- For Mac App Store submission the sandbox would need to be re-enabled and the entitlement set trimmed accordingly — see [`docs/MAC-APP-STORE-CHECKLIST.md`](docs/MAC-APP-STORE-CHECKLIST.md). v3.0.0 GA does **not** ship to the App Store.
- **Reporting vulnerabilities:** please open a GitHub issue or contact the maintainers privately (do not include credentials or node URIs in reports).

---

## 🤝 Contributing

Contributions are welcome! A few guidelines:

1. **Library-first** — new protocol / transport logic belongs in `Sources/Riptide/`, not the app layer
2. **Swift 6 strict concurrency** — all code must pass `Sendable` and actor isolation checks
3. **Test coverage** — add tests for new behavior; `swift test` must pass
4. **No force unwraps** — use proper error handling with typed error enums
5. **No silent fallbacks** — fail explicitly rather than silently degrading
6. **Dependency injection** — prefer injection over hard-coded global behavior

---

## 📄 License

[MIT](LICENSE) — free to use, modify, and distribute.

---

## Acknowledgments

- **[mihomo](https://github.com/MetaCubeX/mihomo)** — the proxy core powering Riptide's production runtime
- **[Clash](https://github.com/Dreamacro/clash)** — original configuration format Riptide is compatible with
- **[Yams](https://github.com/jpsim/Yams)** — YAML parsing
- **[swift-certificates](https://github.com/apple/swift-certificates)** — X.509 certificate handling
