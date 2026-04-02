# Riptide - Sub-project 1: Core Proxy Engine

## Overview

Riptide is a macOS network proxy and debugging tool, inspired by Surge. Sub-project 1 establishes the foundational proxy engine with basic protocol support, rule-based routing, and a minimal native UI.

**Scope**: NetworkExtension packet tunnel, HTTP/SOCKS5/Shadowsocks protocols, domain/IP/GeoIP rule routing, clash.yaml config parsing, minimal SwiftUI app.

**Out of scope** (future sub-projects): VMess/VLESS, proxy groups, request capture/debugging, request rewriting, node speed testing, advanced UI.

---

## Architecture

### XPC-Separated Architecture

The system is split into two processes communicating via XPC:

1. **Main App** (SwiftUI) — UI, config management, user interaction
2. **Packet Tunnel Provider** (NetworkExtension) — runs as a system extension, intercepts and routes all network traffic

```
 System Traffic
      │
      ▼
 NEPacketTunnelProvider
      │
      ├─► DNS Resolver
      │
      ├─► Rule Engine (match domain/IP/GeoIP)
      │       │
      │       ▼
      │   Select Policy (DIRECT / REJECT / Proxy Node)
      │       │
      │       ▼
      ├─► Protocol Handler (HTTP / SOCKS5 / Shadowsocks)
      │
      └─► Remote Proxy Server ──► Internet

 Main App (SwiftUI)
      │
      ├─► Config Manager (parse clash.yaml)
      ├─► Tunnel Manager (XPC IPC)
      └─► UI (menu bar + main window + settings)
```

### XPC Communication

- **App → Tunnel**: start tunnel, stop tunnel, update configuration, query status
- **Tunnel → App**: connection statistics (bytes up/down), active connection count, error reports

---

## Protocol Layer

### Supported Protocols

| Protocol | Role | Details |
|----------|------|---------|
| HTTP/HTTPS | Outbound proxy client | Forward HTTP requests and HTTP CONNECT for HTTPS |
| SOCKS5 | Outbound proxy client | CONNECT command only; no UDP ASSOCIATE in this phase |
| Shadowsocks | Outbound proxy client | AEAD ciphers: aes-128-gcm, aes-256-gcm, chacha20-ietf-poly1305 |

### Protocol Interface

```swift
protocol OutboundProxy {
    func connect(to target: ConnectionTarget) async throws -> ProxyConnection
}

protocol ProxyConnection {
    func sendData(_ data: Data) async throws
    func receiveData() async throws -> Data
    func close() async
}
```

Each protocol implements `OutboundProxy`. The rule engine uses only this interface, keeping protocol details encapsulated.

### Shadowsocks Implementation

- AEAD encryption via Apple CryptoKit or CommonCrypto
- Per-connection key derivation
- TCP only in this phase; UDP deferred to a later sub-project

---

## Rule Engine

### Rule Types

| Type | Match Logic | Example |
|------|-------------|---------|
| DOMAIN | Exact domain match | `DOMAIN,example.com,Proxy` |
| DOMAIN-SUFFIX | Domain suffix match | `DOMAIN-SUFFIX,google.com,Proxy` |
| DOMAIN-KEYWORD | Domain keyword match | `DOMAIN-KEYWORD,ads,REJECT` |
| IP-CIDR | IP range match | `IP-CIDR,192.168.0.0/16,DIRECT` |
| GEOIP | Country/region by IP | `GEOIP,CN,DIRECT` |
| FINAL | Fallback (always matches) | `FINAL,Proxy` |

### Policy Types

| Policy | Behavior |
|--------|----------|
| DIRECT | Connect directly, no proxy |
| REJECT | Drop the connection |
| Proxy Node | Route through a specific configured proxy node |

Proxy Groups (auto-select, fallback, load-balance) are deferred to sub-project 2.

### Matching Flow

1. Receive connection request, extract target domain and/or IP
2. Iterate rule list in order
3. First matching rule determines the policy
4. If no rule matches, apply FINAL policy

### GeoIP

- MaxMind GeoLite2 database (free tier)
- Bundled with the app, with periodic update checks
- Lookup uses libmaxminddb or a Swift wrapper

---

## Configuration Parsing

### Format

Clash YAML format for broad ecosystem compatibility. Example:

```yaml
port: 7890
socks-port: 7891
mode: rule

proxies:
  - name: "my-ss"
    type: ss
    server: server.com
    port: 443
    cipher: aes-256-gcm
    password: "password"

  - name: "my-socks5"
    type: socks5
    server: server.com
    port: 1080

rules:
  - DOMAIN-SUFFIX,google.com,my-ss
  - GEOIP,CN,DIRECT
  - MATCH,my-ss
```

### Parsing Strategy

- Swift `Codable` + `Yams` library for YAML parsing
- Strict mode: fail to start on parse errors rather than silently skipping
- Validate proxy node completeness (server, port, password are required)

---

## UI (Minimal for Sub-project 1)

### Menu Bar

- Icon showing connection status (connected/disconnected/error)
- Click to show dropdown: connect/disconnect, current mode, open main window, quit

### Main Window

- Proxy toggle (start/stop)
- Current mode selector (rule-based / global proxy / direct)
- Proxy node list (loaded from config)
- Selected node indicator
- Traffic statistics (upload/download bytes)

### Config Import

- Drag-and-drop or file picker for clash.yaml files
- Validate on import, show errors inline

### Not in Scope

Request list, MitM, Map Local, scripting, rule editor UI — these belong to later sub-projects.

---

## Project Structure

```
Riptide/
├── RiptideApp/                    # Main App target (SwiftUI)
│   ├── App/
│   │   ├── RiptideApp.swift       # App entry point
│   │   └── AppDelegate.swift
│   ├── Views/
│   │   ├── StatusBarView.swift    # Menu bar
│   │   ├── MainView.swift         # Main window
│   │   └── SettingsView.swift     # Settings
│   ├── ViewModels/
│   │   ├── ProxyViewModel.swift
│   │   └── ConfigViewModel.swift
│   └── Services/
│       └── TunnelManager.swift    # XPC communication
│
├── RiptideTunnel/                 # NetworkExtension target
│   ├── PacketTunnelProvider.swift # NE entry point
│   ├── DNS/
│   │   └── DNSResolver.swift
│   ├── Rules/
│   │   ├── RuleEngine.swift
│   │   ├── DomainRule.swift
│   │   ├── IPCIDRRule.swift
│   │   └── GeoIPRule.swift
│   ├── Protocols/
│   │   ├── OutboundProxy.swift    # Protocol interface
│   │   ├── HTTPProxy.swift
│   │   ├── SOCKS5Proxy.swift
│   │   └── ShadowsocksProxy.swift
│   ├── Config/
│   │   └── ClashConfigParser.swift
│   └── Connection/
│       └── ConnectionPool.swift
│
├── RiptideKit/                    # Shared framework (App & Tunnel)
│   ├── Models/
│   │   ├── ProxyNode.swift
│   │   ├── Rule.swift
│   │   └── Config.swift
│   └── XPC/
│       └── XPCProtocol.swift
│
└── RiptideTests/                  # Unit tests
```

---

## Dependencies

| Dependency | Purpose |
|------------|---------|
| Yams | YAML parsing (clash.yaml) |
| MaxMind GeoLite2 | GeoIP database |
| CryptoKit / CommonCrypto | Shadowsocks AEAD encryption |

---

## Key Technical Decisions

1. **NEPacketTunnelProvider** over NEAppProxyProvider — enables full traffic interception (like Surge's enhanced mode) rather than per-app proxying
2. **clash.yaml** as primary config format — widest ecosystem compatibility for easy migration
3. **CryptoKit** for crypto — Apple-native, no external dependencies for Shadowsocks
4. **Strict config parsing** — fail loudly on malformed config rather than silent misconfiguration
5. **Protocol abstraction via `OutboundProxy`** — adding VMess/VLESS in sub-project 2 requires only a new implementation, no engine changes

---

## Future Sub-Projects (not in this scope)

- **Sub-project 2**: VMess/VLESS protocols, proxy groups (auto-select/fallback/load-balance), advanced rule features
- **Sub-project 3**: Request capture, HTTP traffic inspector, request/response modification, breakpoints, Map Local
- **Sub-project 4**: Node speed testing, config editor UI, Surge .conf compatibility, polish
