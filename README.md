# Riptide

Riptide is an open-source Swift proxy engine project targeting a Surge-like architecture: strict config parsing, deterministic rule routing, protocol framing, transport orchestration, tunnel lifecycle management, and executable CLI/App entrypoints.

**Current state: Beta** — System Proxy mode, TUN mode scaffolding, profile management, subscription workflow, runtime observability, and menu bar shell are implemented. Proxy groups and DNS policy routing are complete.

## Features

- **Strict Clash-compatible parser (subset)** with explicit validation errors
- **Rule engine**: `DOMAIN`, `DOMAIN-SUFFIX`, `DOMAIN-KEYWORD`, `IP-CIDR`, `IP-CIDR6`, `GEOIP`, `PROCESS-NAME`, `MATCH/FINAL`
- **Protocol framing**: HTTP CONNECT, SOCKS5, Shadowsocks AEAD
- **Transport layer**: connection contracts, pooling, and `Network.framework` TCP/TLS dialers
- **Runtime layers**:
  - `TunnelLifecycleManager` for lifecycle state transitions
  - `LiveTunnelRuntime` for real policy execution (`DIRECT` / `REJECT` / proxy path)
  - `InProcessTunnelControlChannel` for command/response/event control abstraction
  - `ModeCoordinator` for unified system proxy / TUN mode orchestration
- **Profile management**: `ProfileStore` actor for local and subscription-backed profiles
- **Observability**: `RuntimeEventStore` bounded buffer for lifecycle events, connection snapshots, and throughput counters
- **Local proxy ingress**:
  - `LocalHTTPConnectProxyServer` for real local HTTP CONNECT traffic and relay
  - `SystemProxyControlling` protocol for enable/disable with test doubles
- **Entrypoints**:
  - `riptide` CLI (`validate`, `run`, `smoke`, `serve`)
  - `RiptideApp` SwiftUI app with menu bar shell (`MenuBarExtra`) and tabbed dashboard

## Alpha-Ready Capabilities

| Feature | Status |
|---------|--------|
| System Proxy mode | Beta-ready |
| Profile import (YAML) | Beta-ready |
| Subscription workflow | Beta-ready |
| Runtime observability | Beta-ready |
| Menu bar controls | Beta-ready |
| Proxy groups | Beta-ready |
| DNS policy routing | Beta-ready |
| TUN / Packet Tunnel | Scaffolded (Beta) |

## Project Structure

```text
Sources/
  Riptide/
    AppShell/      # Import workflow + app-facing status mapping
    Config/        # Clash parser
    Connection/    # ProxyConnector orchestration
    Control/       # Control channel abstraction
    Models/        # Config/rule/proxy core models
    Protocols/     # HTTP/SOCKS5/SS framing
    Rules/         # RuleEngine + GeoIP resolver injection
    Transport/     # Session contracts, pooling, network dialers
    Tunnel/        # Runtime + lifecycle manager
  RiptideCLI/      # CLI entrypoint and command runner
  RiptideApp/      # SwiftUI demo app entrypoint
Tests/
  RiptideTests/    # End-to-end unit coverage across layers
```

## Requirements

- macOS 14+
- Swift 6.2+
- Xcode 16+/26.x toolchain with Swift Package Manager support

## Quick Start

### 1. Build

```bash
swift build
```

### 2. Run tests

```bash
swift test
```

### 3. CLI usage

Build and run with:

```bash
swift run riptide --help
```

Examples:

```bash
swift run riptide validate --config ./example.yaml
swift run riptide run --config ./example.yaml
swift run riptide smoke --config ./example.yaml --host example.com --port 443
swift run riptide serve --config ./Examples/direct-mode.yaml --port 6152
```

`serve` starts a local HTTP CONNECT proxy so macOS apps, browsers, or CLI tools can send real traffic through the live runtime.

### 4. Run the demo app

```bash
swift run RiptideApp
```

## Example Clash Config (supported subset)

```yaml
mode: rule
proxies:
  - name: "my-socks"
    type: socks5
    server: "127.0.0.1"
    port: 1080
  - name: "my-ss"
    type: ss
    server: "1.2.3.4"
    port: 443
    cipher: "aes-256-gcm"
    password: "secret"
rules:
  - DOMAIN-SUFFIX,google.com,my-socks
  - DOMAIN-KEYWORD,ads,REJECT
  - IP-CIDR,10.0.0.0/8,DIRECT
  - GEOIP,CN,my-ss
  - MATCH,my-socks
```

## GeoIP Rule Baseline

`GEOIP` matching is implemented through **dependency injection**:

- `RuleEngine(rules:geoIPResolver:)`
- `LiveTunnelRuntime(proxyDialer:directDialer:geoIPResolver:)`

Default resolver is `.none` (no country match). Production integration (e.g., MMDB) can be added without changing rule matching call sites.

## Roadmap

### Beta (current)

1. TUN / Packet Tunnel: wire `PacketTunnelProvider` and NetworkExtension target
2. Proxy groups: `ProxyGroupResolver` for Select, URL-Test, Fallback, Load-Balance
3. DNS policy routing: `DNSPolicy` with `respect-rules` and nameserver fallback

### Future

4. MITM / rewrite surfaces
5. External controller REST API expansion
6. VMess / VLESS / Trojan / Hysteria2 stream actors wired to `ProxyConnector`
7. Advanced dashboard and rule-set support

## Contributing

Contributions are welcome.

- Keep changes modular and test-backed
- Follow strict failure behavior (avoid silent fallbacks)
- Add/adjust tests for behavior changes

For substantial changes, open an issue first to discuss design and scope.

## License

This project is currently **unlicensed** (no OSS license file yet).  
If you plan public reuse, add a `LICENSE` file (e.g., MIT/Apache-2.0) in a follow-up.
