# AGENTS.md

## Project Summary

Riptide is a native macOS proxy client built entirely in Swift 6. It has a **library-first architecture** with a pure Swift proxy engine (`Riptide` library), a SwiftUI client (`RiptideApp`), and a CLI tool (`RiptideCLI`). The app integrates with the [mihomo](https://github.com/MetaCubeX/mihomo) sidecar for production-grade runtime mode (System Proxy / TUN), while the library independently implements protocol framing, DNS resolution, rule matching, and connection orchestration.

**Current state**: Beta — 366 tests in 57 suites, all passing.

## Environment

- Target platform: macOS 14+
- Toolchain: Swift 6.2+ / Xcode 16+
- Package manager: Swift Package Manager
- Dependencies: `Yams` (YAML parsing), `swift-argument-parser` (CLI)

## Repo Layout

### Core Library — `Sources/Riptide/`

| Directory | Responsibility |
|-----------|---------------|
| `Config/` | Clash YAML parsing (`ClashConfigParser`) and deep config merging (`ConfigMerger`) |
| `Models/` | Core data models: `ProxyNode`, `ProxyRule`, `RoutingPolicy`, `ProxyGroup` |
| `Rules/` | Rule engine (`RuleEngine`), GeoIP MMDB parser, GeoSite/ASN resolvers, RuleSet, script rules |
| `Transport/` | Transport contracts + 7 implementations: TCP, TLS, WS, HTTP/2, QUIC, Multiplex, Connection Pool |
| `Protocols/` | Outbound protocol framing: Shadowsocks (AEAD), VMess, VLESS, Trojan, Hysteria2, Snell, SOCKS5, HTTP CONNECT |
| `Connection/` | `Proxy_connector` — connects proxy nodes to transports with protocol handshake |
| `DNS/` | Full DNS stack: UDP/TCP/DoH/DoT/DoQ clients, cache, FakeIP pool, pipeline orchestrator |
| `Groups/` | Proxy group resolution (select/url-test/fallback/load-balance), LoadBalancer with consistent-hash/round-robin |
| `HealthCheck/` | `HealthChecker` + `GroupSelector` for latency-based proxy selection |
| `Tunnel/` | `LiveTunnelRuntime` — runtime state machine, connection lifecycle, traffic recording |
| `LocalProxy/` | `LocalHTTPConnectProxyServer` — local HTTP CONNECT ingress with domain sniffing |
| `Control/` | External controller surfaces: REST API, WebSocket streaming (traffic + connections) |
| `MITM/` | MITM framework: config, manager, HTTPS interceptor, CA scaffolding |
| `Subscription/` | `SubscriptionManager` + `SubscriptionUpdateScheduler` + URI parser |
| `AppShell/` | App-facing coordinators: mode, profile store, system proxy, import service, stats pipeline |
| `Mihomo/` | mihomo sidecar integration: API client, config generator, paths, runtime manager, log client |
| `VPN/` | TUN providers: `TUNRoutingEngine`, `UserSpaceTCP`, `PacketTunnelProvider`, TCP/UDP sessions |
| `XPC/` | Privileged helper tool communication via XPC |
| `NodeEditor/` | Proxy node editing with real-time validation |
| `Scripting/` | JavaScript-based script engine for rule evaluation |
| `Logging/` | Log types and entry parsing |
| `Traffic/` | Traffic monitoring providers and view models |
| `ProxyProvider/` | Proxy provider abstraction |

### App — `Sources/RiptideApp/`

| Directory | Responsibility |
|-----------|---------------|
| `App/` | Theme manager, hotkey manager, config drop delegate, main tab view, status bar controller |
| `Localization/` | i18n system: `Localized` enum (80+ keys), `LocalizationManager`, zh-Hans/en JSON files |
| `ViewModels/` | App view models: `AppViewModel`, `ProxyViewModel`, `LogViewModel`, `MITMSettingsViewModel`, etc. |
| `Views/` | All SwiftUI views: Config, Proxy, Traffic, Rules, Logs tabs + connection list + subscription sheet + node editor |
| `AppViewModel.swift` | Central application state management |
| `RiptideApp.swift` | App entry point |
| `MenuBarScene.swift` | Menu bar extra with status, traffic, profile switching |
| `SMJobBlessManager.swift` | Privileged helper installation management |

### CLI — `Sources/RiptideCLI/`

Command-line interface for tunnel management and configuration testing.

### Tests — `Tests/RiptideTests/`

366 tests in 57 suites covering: config parsing, rule engine, DNS, protocols, transports, tunnel runtime, mihomo API, subscriptions, MITM config, localization, and more.

## Build And Test

```bash
# Build all targets
swift build

# Run all tests
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

## Architecture Notes

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

## Coding Conventions

- Follow Swift 6 strict concurrency (`@MainActor`, `Sendable`, `actor`)
- Prefer `struct`/`enum` models with `Equatable` and `Sendable`
- Keep stateful runtime components isolated and concurrency-safe
- Do not add logic to `Sources/Riptide/Riptide.swift` (module entry surface)
- Avoid force unwraps (`!`) and silent fallbacks
- Keep changes modular and consistent with surrounding folder patterns

## Change Guidance

- Fix the root cause rather than patching symptoms when practical
- Add or update tests for behavior changes (parsers, routing, transport, runtime)
- Keep scaffolding and partially wired subsystems clearly separated from production-ready paths
- Do not broaden support claims in docs or code unless the behavior is wired end-to-end
- For new features, prefer dependency injection over hard-coded global behavior

## Validation Expectations

- Run targeted tests first when changing a focused area
- Run `swift test` before claiming the work is complete (366/366 must pass)
- If changing CLI behavior, verify with `swift run riptide ...`
- If changing app-facing state or workflow code, sanity-check `RiptideApp` buildability

## Documentation

- Update `README.md` when user-visible behavior, commands, or supported capabilities change
- Keep documentation precise about what is implemented versus scaffolded
- Update feature status tables in README when adding new capabilities
