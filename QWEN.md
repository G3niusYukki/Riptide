# QWEN.md — Riptide Project Context

## Project Overview

**Riptide** is a native macOS proxy client built entirely in **Swift 6**. It features a **library-first architecture** with three main components:

1. **`Riptide`** — Core library (pure Swift) implementing protocol framing, DNS resolution, rule matching, and connection orchestration
2. **`RiptideApp`** — SwiftUI macOS client application
3. **`RiptideCLI`** — Command-line interface tool

The app integrates with the [mihomo](https://github.com/MetaCubeX/mihomo) sidecar for production-grade runtime modes (System Proxy / TUN), while the library independently implements all proxy logic in pure Swift.

**Status**: Beta — 366 tests in 57 suites, all passing.

### Key Features

- **Proxy Protocols**: Shadowsocks (AEAD), VMess, VLESS, Trojan, Hysteria2, Snell, SOCKS5, HTTP CONNECT
- **Transport Layer**: TCP, TLS, WebSocket, HTTP/2, QUIC, Multiplex, Connection Pool
- **DNS Stack**: UDP/TCP/DoH/DoT/DoQ clients, FakeIP pool, DNS cache, pipeline orchestrator
- **Rule Engine**: Domain/IP/PORT/PROCESS matching, GEOIP (MMDB), GEOSITE, ASN, RULE-SET, SCRIPT
- **Proxy Groups**: select, url-test, fallback, load-balance (consistent-hash/round-robin), relay
- **Runtime Modes**: System Proxy, TUN Mode, Direct, Global
- **MITM Framework**: HTTPS interception with wildcard host matching and certificate authority
- **SwiftUI App**: Config import, subscription management, proxy selection, traffic monitoring, connection list, log viewer, menu bar extra, hotkeys, i18n (zh-Hans/en)

### Tech Stack

- **Language**: Swift 6.2+
- **UI Framework**: SwiftUI
- **Package Manager**: Swift Package Manager
- **Dependencies**: 
  - `Yams` (YAML parsing)
  - `swift-argument-parser` (CLI)
  - `swift-certificates` (X.509 certificates for MITM)
- **Target Platform**: macOS 14+ (Sonoma or later)
- **Sidecar**: mihomo (optional integration via XPC)

---

## Building and Running

### Prerequisites

- macOS 14+
- Swift 6.2+ / Xcode 16+
- Apple Developer account (for signing privileged helper — required for TUN mode)

### Build Commands

```bash
# Build all targets
swift build

# Run all tests (366/366 must pass)
swift test

# Run specific test suite
swift test --filter "RuleEngine"
swift test --filter "MihomoAPI"
swift test --filter "MITMConfig"

# Run CLI
swift run riptide --help

# Run app
swift run RiptideApp
```

### Setup mihomo Binary

```bash
./Scripts/download-mihomo.sh
```

### Privileged Helper (TUN Mode)

1. Open `RiptideHelper/Resources/Info.plist`
2. Replace `YOUR_TEAM_ID` with your Apple Developer Team ID
3. Build and sign:

```bash
cd RiptideHelper
swift build
codesign --sign "Developer ID Application: Your Name" \
  --entitlements Entitlements.plist \
  .build/debug/RiptideHelper
```

---

## Project Structure

```
Riptide/
├── Package.swift                      # SPM manifest (3 targets + 3 deps)
├── README.md                          # Comprehensive documentation
├── AGENTS.md                          # Development conventions
├── ROADMAP.md                         # Future development plans
│
├── Sources/
│   ├── Riptide/                       # Core library (pure Swift)
│   │   ├── AppShell/                  # Mode coordinator, profile store, system proxy
│   │   ├── Config/                    # Clash YAML parsing & merging
│   │   ├── Connection/                # Proxy connection orchestration
│   │   ├── Control/                   # REST API + WebSocket external controller
│   │   ├── DNS/                       # Full DNS stack (10 files)
│   │   ├── Groups/                    # Proxy group management
│   │   ├── HealthCheck/               # Health checking & group selection
│   │   ├── LocalProxy/                # Local HTTP CONNECT server
│   │   ├── Logging/                   # Log types
│   │   ├── Mihomo/                    # mihomo sidecar integration
│   │   ├── MITM/                      # HTTPS interception framework
│   │   ├── Models/                    # Core data models
│   │   ├── NodeEditor/                # Proxy node editing & validation
│   │   ├── Protocols/                 # Protocol framing (8 protocols)
│   │   ├── ProxyProvider/             # Proxy provider abstraction
│   │   ├── Rules/                     # Rule engine + GeoIP/GeoSite
│   │   ├── Scripting/                 # JavaScript script engine
│   │   ├── Subscription/              # Subscription management
│   │   ├── Traffic/                   # Traffic monitoring
│   │   ├── Transport/                 # Transport layer (7 implementations)
│   │   ├── Tunnel/                    # Runtime & lifecycle
│   │   ├── VPN/                       # TUN providers & packet handling
│   │   └── XPC/                       # Helper tool communication
│   │
│   ├── RiptideApp/                    # SwiftUI client
│   │   ├── App/                       # Theme, hotkeys, tab view, status bar
│   │   ├── Localization/              # i18n (zh-Hans, en)
│   │   ├── ViewModels/                # App view models
│   │   ├── Views/                     # All SwiftUI views
│   │   ├── AppViewModel.swift         # Central state management
│   │   └── RiptideApp.swift           # App entry point
│   │
│   └── RiptideCLI/                    # Command-line interface
│
├── Tests/RiptideTests/                # 366 tests in 57 suites
│
├── Resources/
│   ├── zh-Hans.json                   # Chinese translations
│   └── en.json                        # English translations
│
├── RiptideHelper/                     # Privileged XPC helper tool
│
├── AppExtensions/                     # App extensions
│
├── Scripts/
│   └── download-mihomo.sh             # Download mihomo binary
│
├── Examples/                          # Example configurations
│
└── docs/                              # Additional documentation
```

---

## Architecture

### Request Flow (System Proxy / TUN)

```
LocalHTTPConnectProxyServer / TUN packet
  → LiveTunnelRuntime.openConnection()
    → RuleEngine.resolve() → RoutingPolicy
    → Proxy_connector.connect(via: node, to: target)
      → Transport session (TCP/TLS/WS/QUIC/HTTP2)
      → Protocol handshake (SS/VMess/VLESS/Trojan/Hy2/Snell)
      → Bidirectional data relay
```

### Key Design Principles

- **Library-first**: Shared logic belongs in `Sources/Riptide/`, not CLI or app targets
- **Strict concurrency**: Follow Swift 6 `Sendable` and actor isolation throughout
- **No silent fallbacks**: Fail explicitly rather than silently degrading
- **No force unwraps**: Use proper error handling with typed error enums
- **Separable units**: Protocol streams and transport layers have clear interfaces
- **Dependency injection**: Prefer injection over hard-coded global behavior

---

## Development Conventions

### Coding Style

- Follow Swift 6 strict concurrency (`@MainActor`, `Sendable`, `actor`)
- Prefer `struct`/`enum` models with `Equatable` and `Sendable`
- Keep stateful runtime components isolated and concurrency-safe
- Do not add logic to `Sources/Riptide/Riptide.swift` (module entry surface)
- Avoid force unwraps (`!`) and silent fallbacks
- Keep changes modular and consistent with surrounding folder patterns

### Testing

- Add tests for new functionality (parsers, routing, transport, runtime)
- Run `swift test` before claiming work is complete (366/366 must pass)
- Run targeted tests first when changing a focused area

### Validation

- If changing CLI behavior, verify with `swift run riptide ...`
- If changing app-facing state or workflow code, sanity-check `RiptideApp` buildability
- Fix root causes rather than patching symptoms

### Documentation

- Update `README.md` when user-visible behavior changes
- Keep documentation precise about what is implemented versus scaffolded
- Update feature status tables in README when adding new capabilities

---

## Security

### Privileged Helper (TUN Mode)

- Runs as root via `SMJobBless`
- Launches mihomo **only** from `/Library/Application Support/Riptide/mihomo/`
- Validates all config paths are within allowed directory
- No arbitrary command execution

### Code Signing

- Both main app and helper must be signed with same Apple Developer Team ID
- Helper's `Info.plist` embeds allowed client Team ID for XPC authentication

### Network Security

- TLS connections use Network.framework's built-in TLS verification
- Certificate validation is enforced (no skip-cert-verify by default)
- Proxy credentials are never logged

---

## Useful Commands

```bash
# Build
swift build

# Test all
swift test

# Test specific module
swift test --filter "RuleEngine"

# Run CLI
swift run riptide --help

# Run app
swift run RiptideApp

# Clean build artifacts
rm -rf .build
```
