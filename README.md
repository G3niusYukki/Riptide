<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue?logo=apple" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/tests-562%20passing-brightgreen" alt="Tests" />
  <img src="https://img.shields.io/badge/version-1.7.0-blue" alt="Version" />
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="License" />
  <img src="https://img.shields.io/badge/status-stable-brightgreen" alt="Status" />
</p>

<h1 align="center">⚡ Riptide</h1>

<p align="center">
  <strong>A native macOS proxy client built entirely in Swift 6.</strong><br/>
  Library-first architecture · Clash-compatible · mihomo-powered runtime
</p>

<p align="center">
  <a href="#-features">Features</a> ·
  <a href="#-architecture">Architecture</a> ·
  <a href="#-getting-started">Getting Started</a> ·
  <a href="#-building--testing">Building</a> ·
  <a href="#-contributing">Contributing</a>
</p>

---

## Why Riptide?

Most macOS proxy clients wrap a Go core (mihomo / sing-box) in Electron or Tauri. Riptide takes a different path: a **pure Swift** library implements protocol framing, DNS, rule matching, and connection orchestration natively — while the production runtime delegates to the battle-tested [mihomo](https://github.com/MetaCubeX/mihomo) sidecar for real traffic.

This gives you:

- **Native look & feel** — SwiftUI interface, ~15 MB bundle, instant startup
- **Library-first** — the `Riptide` Swift package is usable standalone, independent of the GUI
- **Clash-compatible** — drop in your existing `.yaml` configs and subscriptions
- **Transparent** — every line is Swift, no opaque binary blobs beyond mihomo itself

> **Unsigned builds:** TUN mode is the recommended path — it intercepts all traffic at the packet level via mihomo's gVisor stack and does not require the privileged helper.

---

## ✨ Features

### Proxy Protocols

Shadowsocks AEAD · VMess · VLESS (XTLS/Vision) · VLESS Reality · Trojan · Hysteria2 · TUIC · WireGuard · Snell v2/v3 · SOCKS5 · HTTP CONNECT

### Transport

TCP (`NWConnection`) · TLS · WebSocket · HTTP/2 · QUIC (macOS 14+) · Connection Pool · Multiplex

### DNS (Fully Self-Developed)

UDP · TCP · DNS-over-HTTPS · DNS-over-TLS · DNS-over-QUIC (RFC 9250) · FakeIP · Cache · Domain Sniffing · Pipeline with Fallback · Hosts Override

### Rule Engine

DOMAIN / DOMAIN-SUFFIX / DOMAIN-KEYWORD · IP-CIDR / IP-CIDR6 · SRC-IP-CIDR · SRC-PORT / DST-PORT · PROCESS-NAME · GEOIP (native MMDB parser) · GEOSITE · IP-ASN · RULE-SET · SCRIPT (JavaScript) · NOT / REJECT / MATCH · Config Merger

### Proxy Groups

`select` · `url-test` · `fallback` · `load-balance` (consistent-hash / round-robin) · `relay` (chain)

### App GUI

- Config import (file picker / drag-and-drop / subscription URL) with **import preview**
- **Node editor** with real-time validation, protocol-specific fields, add/edit/delete/duplicate
- **Rule editor** with drag-to-reorder, 10 rule types, policy picker
- **Config merge UI** — add merge sources (file/manual), preview diffs, one-click apply
- **Config backup/restore** — automatic backup on profile switch, manual backup, restore from history
- **Rule set auto-update** — periodic refresh of remote rule sets with status display
- Proxy group cards with latency testing and one-click switching
- Real-time traffic monitor and connection list
- Log viewer with level filter, search, and export
- Menu bar extra with status icon and traffic speed
- MITM settings with host pattern matching
- Theme: System / Light / Dark
- Global hotkeys
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
  │            Riptide Library (pure Swift)               │
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
| **System Proxy** | Stable | mihomo sidecar + macOS system proxy configuration with auto-guard (guard requires signed helper) |
| **TUN Mode** | Stable | Full traffic interception via mihomo gVisor TUN + auto-recovery — recommended for unsigned builds. Requires sudo, no Apple Developer account needed |

---

## 🚀 Getting Started

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Swift 6.2+ / Xcode 16+ (building from source)

### Install (DMG)

1. Download `Riptide-x.x.x-arm64.dmg` from [Releases](https://github.com/G3niusYukki/Riptide/releases)
2. Open the DMG, drag **RiptideApp** to `/Applications`
3. If macOS blocks the app (unsigned), run:
   ```bash
   xattr -cr /Applications/RiptideApp.app
   ```
   Then open normally.

> Riptide is fully open source but not Apple-signed (no $99/year developer certificate). `xattr -cr` simply removes the "downloaded from internet" quarantine flag. After launching, select **TUN mode** during onboarding for full traffic interception without Apple signing.

### Install (Homebrew)

```bash
brew tap G3niusYukki/riptide
brew install riptide
```

### Build from Source

```bash
git clone https://github.com/G3niusYukki/Riptide.git
cd Riptide
swift build
```

### Download mihomo Core

```bash
./Scripts/download-mihomo.sh
```

This fetches the mihomo binary (universal — Intel + Apple Silicon) needed for the System Proxy runtime.

---

## 🧪 Building & Testing

```bash
# Build everything
swift build

# Run full test suite (491 tests, 76 suites)
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
├── Riptide/                 # Core library (pure Swift)
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
│   ├── MITM/                # HTTPS interception: config, manager, CA scaffolding
│   ├── Models/              # Core data models: ProxyNode, ProxyRule, RoutingPolicy
│   ├── NodeEditor/          # Proxy node editing with validation
│   ├── Protocols/           # Protocol framing: SS, VMess, VLESS, Trojan, Hy2, Snell, SOCKS5
│   ├── ProxyProvider/       # Proxy provider abstraction
│   ├── Rules/               # Rule engine, GeoIP MMDB, GeoSite, ASN, RuleSet, scripts
│   ├── Scripting/           # JavaScript rule evaluation engine
│   ├── SingBox/             # sing-box interop layer
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

Tests/RiptideTests/          # 467 tests in 71 suites
```

---

## 🔒 Security

- **TLS verification** enforced by Network.framework — no `skip-cert-verify` by default
- **Proxy credentials** are never logged
- **Privileged helper** boundary: launches mihomo only from `/Library/Application Support/Riptide/mihomo/`, validates all config paths, no arbitrary command execution
- TUN mode uses mihomo's built-in gvisor stack via sudo — no Network Extension or Apple Developer account required

---

## 🤝 Contributing

Contributions are welcome! A few guidelines:

1. **Library-first** — new protocol / transport logic belongs in `Sources/Riptide/`, not the app layer
2. **Swift 6 strict concurrency** — all code must pass `Sendable` and actor isolation checks
3. **Test coverage** — add tests for new behavior; `swift test` must pass (491 / 491)
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