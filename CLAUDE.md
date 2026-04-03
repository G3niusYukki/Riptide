# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Riptide is a Swift proxy engine targeting a Surge/Clash-like architecture: config parsing, rule routing, protocol framing, transport orchestration, and tunnel lifecycle management. Library-first with CLI and SwiftUI app entrypoints.

## Build & Test Commands

```bash
swift build                          # Build all targets
swift test                           # Run all tests
swift test --filter "RuleEngine"     # Run tests matching a regex (e.g., single module)
swift run riptide --help             # CLI usage
swift run riptide validate --config ./example.yaml
swift run riptide serve --config ./Examples/direct-mode.yaml --port 6152
swift run RiptideApp                 # Run SwiftUI demo app
```

Requires macOS 14+ and Swift 6.2+ (Xcode 16+).

## Architecture

### Targets

- **`Riptide`** — core library (depends on Yams for YAML)
- **`RiptideCLI`** — CLI executable (ArgumentParser), subcommands: `validate`, `run`, `smoke`, `serve`
- **`RiptideApp`** — SwiftUI app shell

### Key Protocols (Extension Points)

| Protocol | Purpose |
|----------|---------|
| `TransportSession` | `send/receive/close` — raw I/O abstraction over any transport |
| `TransportDialer` | `openSession(to:)` — creates connections to proxy nodes |
| `TunnelRuntime` | `start/stop/update/status` — tunnel lifecycle contract |
| `OutboundProxyProtocol` | `makeConnectRequest/parseConnectResponse` — proxy handshake framing |

### Request Flow

`LocalHTTPConnectProxyServer` → `LiveTunnelRuntime.openConnection()` → `RuleEngine.resolve()` → routing policy → `ProxyConnector.connect()` → `TransportConnectionPool.acquire()` → protocol handshake → bidirectional `ConnectionRelay`

### Concurrency Model

- **Swift 6 strict concurrency** enforced throughout
- Stateful components are `actor`s: `LiveTunnelRuntime`, `TunnelLifecycleManager`, `TransportConnectionPool`, `DNSPipeline`, `HealthChecker`, `ProxyGroupResolver`, `ModeCoordinator`, `ProfileStore`, `RuntimeEventStore`, `AppGroupStateStore`, `TunnelProviderBridge`, all protocol stream actors
- Stateless components are `struct`/`enum` with `Sendable` conformance
- `@unchecked Sendable` used for `NWConnection` wrappers (already thread-safe) and `NSLock`-protected types
- All I/O is async/await; `NWConnection` callbacks bridged via `withCheckedThrowingContinuation`

### Dependency Injection

- Constructor injection of `any TransportDialer` into `LiveTunnelRuntime`
- `GeoIPResolver` is a closure-carrying struct (`@Sendable (String) -> String?`) — inject `.none` for no-op
- `TunnelRuntime` protocol enables mock substitution (`CLIMockTunnelRuntime`, `AppMockTunnelRuntime`)
- `TunnelLifecycleManager` wraps any `TunnelRuntime`

### Routing

`RuleEngine` uses first-match-wins over ordered rules. Supported rule types: `DOMAIN`, `DOMAIN-SUFFIX`, `DOMAIN-KEYWORD`, `IP-CIDR`, `IP-CIDR6`, `GEOIP`, `PROCESS-NAME`, `MATCH/FINAL`. Policies: `DIRECT`, `REJECT`, `proxyNode(name:)`. Proxy group references in rules are resolved by `ProxyGroupResolver`.

### Module Layout (Sources/Riptide/)

- **Config/** — Clash-compatible YAML parser (`ClashConfigParser`), parses proxies, rules, proxy groups, and DNS sections
- **Models/** — value-type configs/rules/proxies (`RiptideConfig`, `ProxyRule`, `RoutingPolicy`); `RiptideConfig` includes `proxyGroups` and `dnsPolicy`
- **Rules/** — `RuleEngine` + `GeoIPResolver`
- **Transport/** — `TransportSession`/`TransportDialer` protocols, `TransportConnectionPool`, TCP/TLS/WS implementations, `MultiplexTransport`
- **Protocols/** — `OutboundProxyProtocol` impls (HTTP CONNECT, SOCKS5, Shadowsocks), plus per-protocol `actor` streams (VMess, VLESS, Trojan, Hysteria2)
- **Connection/** — `ProxyConnector` orchestrates pool → handshake → `ConnectedProxyContext`
- **Tunnel/** — `LiveTunnelRuntime` (main runtime), `TunnelLifecycleManager` (state machine), models
- **Control/** — `InProcessTunnelControlChannel` (command/event), `ExternalController` (REST API via NWListener), `RuntimeControlSurface` (unified runtime contract)
- **Groups/** — `ProxyGroupResolver` (Select, URL-Test, Fallback, LoadBalance), `GroupSelector` (health-aware)
- **LocalProxy/** — `LocalHTTPConnectProxyServer`, `ConnectionRelay` (bidirectional pump)
- **DNS/** — Wire-format DNS codec, `DNSCache`, `DNSPipeline` (fake-IP/real-IP modes), UDP/TCP/DoH clients, `DNSPolicy` (nameserver routing, fake-IP config, per-domain policies)
- **VPN/** — Packet parsing, `UserSpaceTCP`, `TunnelProviderBridge`, `TunnelProviderMessages`, scaffolded `VPNTunnelManager`
- **AppShell/** — Import workflow, `ConfigImportService`, `ProfileStore`, `ModeCoordinator`, `RuntimeEventStore`, `AppGroupStateStore`, `SystemProxyControlling`, `TunnelControlViewModel` for UI layer

### Scaffolded (Not Fully Wired)

Protocol stream actors exist for VMess/VLESS/Trojan/Hysteria2 but `ProxyConnector` does not yet route to them. WebSocket transport, VPN NetworkExtension integration (`PacketTunnelProvider` wiring), MITM cert generation, and ScriptEngine are stubs.

## Conventions

- All model types are `struct`/`enum` with `Equatable, Sendable`
- Error types are exhaustive `enum` conforming to `Equatable, Sendable`
- `Riptide.swift` is the module entry — do not put logic there
- No force unwraps; strict failure behavior (avoid silent fallbacks)
- Config parser only supports `socks5`, `http`, and `ss` proxy types despite `ProxyKind` listing more
