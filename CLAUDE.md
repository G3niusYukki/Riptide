# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Riptide is a dual-engine proxy client: a **pure Swift proxy engine** (the `Riptide` library) plus an optional [mihomo](https://github.com/MetaCubeX/mihomo) sidecar. It ships as a SwiftUI macOS app (`RiptideApp`), a CLI tool (`RiptideCLI`), and a Windows port (`riptide-windows`, Tauri + React + TypeScript + Rust).

**Two interchangeable runtimes consume the same `Riptide` library:**
- **Swift Proxy Engine** — native Swift implementation of all proxy protocols, transports, DNS, and rule matching
- **mihomo Sidecar** — mihomo process managed via XPC + REST API; handles TUN mode and production-grade protocol support

## Build & Test Commands

```bash
swift build                                    # Build all targets (Riptide, RiptideCLI, RiptideApp)
swift test                                     # Run all tests (366+ tests in 57 suites)
swift test --filter "RuleEngine"              # Run a specific test suite
swift run RiptideApp                           # Launch SwiftUI app
swift run riptide --help                       # CLI help
./Scripts/download-mihomo.sh                   # Download mihomo binary for sidecar mode
```

**Requirements:** macOS 14+, Swift 6.2+ (Xcode 16+).

**Windows port:** `cd riptide-windows && npm install && npm run tauri dev`

## Architecture

### Dual-Engine Design

```
┌──────────────────────────────────────────────────────────┐
│                    RiptideApp (SwiftUI)                   │
│  ┌──────────────────┐  ┌──────────────────────────────┐ │
│  │ Config/Proxy UI   │  │ ModeCoordinator              │ │
│  └────────┬─────────┘  │  - Swift Engine / mihomo    │ │
│           │            │  - System Proxy / TUN        │ │
│           └────────────┼──────────────────────────────┘ │
│                        │                                │
│         ┌──────────────▼────────────────┐               │
│         │    MihomoRuntimeManager     │               │
│         │    (actor — orchestrator)    │               │
│         └──────────────┬────────────────┘               │
└─────────────────────────┼────────────────────────────────┘
                          │
          ┌───────────────┴───────────────┐
          │                               │
  ┌───────▼────────┐            ┌────────▼────────┐
  │ Swift Proxy    │            │  mihomo sidecar │
  │ Engine         │            │  (optional)    │
  │ (built-in)     │            │  REST :9090    │
  └────────┬───────┘            └────────┬────────┘
           │                             │
           │         ┌───────────────────┘
           │         │ XPC (root)
           │  ┌──────▼──────────┐
           │  │ RiptideHelper   │
           └──►  (privileged)   │
              └─────────────────┘
```

### Native Swift Proxy Engine (no external binary)

The `Riptide` library implements the full proxy stack in pure Swift:

```
User / App traffic
  → LocalHTTPConnectProxyServer (ingress)
  → LiveTunnelRuntime (connection lifecycle)
    → RuleEngine (routing policy)
    → ProxyConnector (node → transport binding)
      → Transport layer (TCP/TLS/WS/HTTP2/QUIC)
        → Protocol framing (SS/VMess/VLESS/Trojan/Hy2/Snell/SOCKS5)
          → Remote server
```

Key subsystems: `Sources/Riptide/Transport/`, `Sources/Riptide/Protocols/`, `Sources/Riptide/Rules/`, `Sources/Riptide/DNS/`, `Sources/Riptide/Groups/`, `Sources/Riptide/Tunnel/`, `Sources/Riptide/LocalProxy/`

### mihomo Sidecar (optional runtime)

For production use, mihomo provides TUN mode and broader protocol compatibility. Managed by:
- `Sources/Riptide/Mihomo/MihomoRuntimeManager` — actor orchestrating config generation, XPC to helper, REST API client
- `Sources/Riptide/Mihomo/MihomoConfigGenerator` — generates Clash-compatible YAML with secure escaping
- `Sources/Riptide/XPC/HelperToolConnection` — XPC client for privileged helper
- `Sources/Riptide/AppShell/ModeCoordinator` — switches between Swift Engine, System Proxy, and TUN modes

### Targets

| Target | Type | Purpose |
|--------|------|---------|
| `Riptide` | Library | Core proxy library: protocols, transport, DNS, rules, tunnel |
| `RiptideCLI` | Executable | Command-line tunnel management |
| `RiptideApp` | Executable | SwiftUI macOS client |
| `RiptideHelper` | Helper tool | Privileged XPC service (SMJobBless, runs as root) |
| `RiptideTunnel` | Network Extension | TUN network extension (macOS only) |
| `riptide-windows` | Tauri app | Windows port: React + TypeScript + Rust |

### Concurrency Model

- **Swift 6 strict concurrency** enforced everywhere
- **Actors** for all stateful components: `MihomoRuntimeManager`, `HelperToolConnection`, `MihomoAPIClient`, `ModeCoordinator`, `ProfileStore`, `LiveTunnelRuntime`
- All value types: `struct`/`enum` with `Equatable, Sendable, Codable`
- Error types: `enum` with `Error, Equatable, Sendable`
- `@unchecked Sendable` only for `NSXPCConnection` / `NSXPCListener` (Foundation types)

## Core Component Map

### Request Pipeline (Swift Engine)
| Component | File | Role |
|-----------|------|------|
| `LocalHTTPConnectProxyServer` | `LocalProxy/` | HTTP CONNECT ingress, domain sniffing |
| `LiveTunnelRuntime` | `Tunnel/` | Connection lifecycle, traffic recording |
| `RuleEngine` | `Rules/RuleEngine.swift` | DOMAIN/GEOSITE/GEOIP/RULE-SET/SCRIPT routing |
| `ProxyConnector` | `Connection/` | Binds proxy node to transport |
| `HealthChecker` | `HealthCheck/` | Latency probing for url-test/fallback groups |
| `FakeIPPool` | `DNS/` | CIDR-based IP allocation for HTTPS interception |

### mihomo Sidecar
| Component | File | Role |
|-----------|------|------|
| `MihomoConfigGenerator` | `Mihomo/` | YAML config generation with `yamlEscape()` injection prevention |
| `MihomoRuntimeManager` | `Mihomo/` | Process lifecycle, XPC, REST API health checks |
| `MihomoAPIClient` | `Control/` | `PUT /proxies/{name}` for proxy switching |
| `HelperToolProtocol` | `XPC/` + `RiptideHelper/` | `@objc` XPC protocol for launch/terminate/install |

### App Layer
| Component | File | Role |
|-----------|------|------|
| `ModeCoordinator` | `AppShell/` | Mode switching (Swift Engine ↔ mihomo ↔ TUN) |
| `ProfileStore` | `AppShell/` | Profile persistence to `~/Library/Application Support/Riptide/profiles/` |
| `SMJobBlessManager` | `RiptideApp/` | Helper tool installation via admin password |
| `SubscriptionManager` | `Subscription/` | Remote config subscription with auto-update |

## Key Workflows

### HTTP CONNECT Proxy (System Proxy — Swift Engine)
1. App sets macOS system proxy to `127.0.0.1:6152`
2. `LocalHTTPConnectProxyServer` receives HTTP CONNECT
3. `RuleEngine` resolves routing policy
4. `ProxyConnector` → transport → protocol → remote server
5. Response relayed back through proxy server

### TUN Mode (mihomo sidecar)
1. User selects TUN mode → `ModeCoordinator` checks `RiptideHelper` installation
2. If not installed, `SMJobBlessManager` prompts for admin password
3. `MihomoRuntimeManager.start(mode: .tun)`:
   - `MihomoConfigGenerator` writes YAML with `tun.enable: true`
   - XPC call to `launchMihomo(configPath:)`
   - REST API health check (10 retries, 500ms delay)
4. mihomo creates gVisor TUN device, traffic intercepted

### Proxy Switching
1. User selects node in UI
2. `MihomoAPIClient.switchProxy(to: name, inGroup: "GLOBAL")`
3. PUT `http://127.0.0.1:9090/proxies/GLOBAL`
4. mihomo immediately switches active proxy

## Security Practices

### YAML Injection Prevention
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

### Path Validation
The privileged helper validates config paths are within `~/Library/Application Support/Riptide/mihomo/` before operating — prevents access to arbitrary files as root.

## File System Layout

```
~/Library/Application Support/Riptide/
├── mihomo/              # mihomo sidecar
│   ├── config.yaml
│   ├── config.yaml.bak
│   ├── cache/GeoIP.dat, GeoSite.dat
│   └── logs/mihomo.log
├── profiles/            # Saved profiles
└── ...

/Library/PrivilegedHelperTools/   # RiptideHelper (installed by SMJobBless)
/Library/Application Support/Riptide/mihomo   # Installed mihomo binary
```

## Windows Port

The `riptide-windows/` directory is a separate Tauri + React + TypeScript + Rust project. It communicates with mihomo via its REST API (same as macOS sidecar), and uses Rust crates (`sysproxy` for system proxy, `tokio` for async). See `riptide-windows/README.md` for details.

## Conventions

- **No force unwraps** — use `guard`/`if let`/`throw` throughout
- **Dependency injection** via constructors (no singletons except where intentional)
- **TDD** — tests live alongside source in `Tests/RiptideTests/`
- Model types: `struct`/`enum` with `Equatable, Sendable, Codable`
- Error types: `enum` with `Error, Equatable, Sendable`

## Known Limitations

1. **Helper Tool Signing**: `RiptideHelper/Resources/Info.plist` requires valid Apple Developer Team ID for production SMJobBless
2. **macOS TUN**: Uses NetworkExtension and SMJobBless APIs — not portable
3. **QUIC transport**: Requires macOS 14+ (`NWProtocolQUIC`)
4. **Windows port**: In progress (Phase 2), `feat/windows-port-phase2` branch

## References

- [mihomo documentation](https://wiki.metacubex.one/)
- [Clash configuration format](https://github.com/Dreamacro/clash/wiki/configuration)
- [SMJobBless sample](https://developer.apple.com/library/archive/samplecode/SMJobBless/)
