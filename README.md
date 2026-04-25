# Riptide

A native Swift proxy-client project for macOS. Riptide currently focuses on a SwiftUI app shell, Clash-compatible configuration parsing, and [mihomo](https://github.com/MetaCubeX/mihomo) sidecar integration for product runtime.

> **Architecture**: Library-first design. The `Riptide` library contains protocol, DNS, rule, runtime, and mihomo integration components. Product readiness is intentionally scoped to the verified mihomo-backed System Proxy path first; native protocol and TUN work remain under active development.

**Status**: Beta / product-readiness hardening. System Proxy via mihomo is the only product-exposed runtime path in this phase. TUN mode is gated until real mihomo TUN integration, signing/entitlements, and recovery behavior are verified end-to-end.

## Product capability matrix

| Capability | Product status | Notes |
|------------|----------------|-------|
| macOS app shell | Beta | SwiftUI app and menu bar are present; packaging/signing still need product validation. |
| Clash YAML import | Beta | Parser and profile import are covered by tests; broad provider compatibility still needs real subscription coverage. |
| mihomo System Proxy runtime | Beta | Intended primary path. Requires a usable mihomo binary and verified local permissions. |
| TUN / VPN runtime | Gated | Hidden/disabled in product UI until mihomo TUN, NetworkExtension entitlement, signing, and cleanup are verified. |
| Native Swift proxy stack | Experimental | Useful for library tests and self-contained smoke checks; not the recommended product runtime. |
| CLI `validate` | Supported helper | Validates config parsing/import. |
| CLI `run` | Simulation only | Exercises the in-process lifecycle; it does not launch the product mihomo runtime. |
| CLI `smoke` | Self-contained self-test | Opens through the native runtime test path; not a guarantee that real proxy nodes or mihomo are production-ready. |


---

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Project Structure](#project-structure)
- [Build & Test](#build--test)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

---

## Features

### Platform support

| Platform | Status | Notes |
|----------|--------|-------|
| macOS 14+ | Beta | SwiftUI app shell and mihomo-backed System Proxy path are the current product focus. |
| Windows | Not supported | No product Windows client is shipped by this Swift package. |
| Linux | Not supported | No product Linux client is shipped by this Swift package. |

### 配置同步

| 功能 | 状态 | 说明 |
|------|------|------|
| WebDAV 同步 | ✅ v1.1+ | 跨设备配置同步 |

### Proxy Protocols

| Protocol | Implementation | Notes |
|----------|---------------|-------|
| Shadowsocks (AEAD) | ✅ Native Swift | Full AEAD cipher support, crypto provider |
| VMess | ✅ Native Swift | UUID-based auth, stream framing |
| VLESS | ✅ Native Swift | XTLS/Vision flow support |
| Trojan | ✅ Native Swift | SHA224 password auth |
| Hysteria2 | ✅ Native Swift | QUIC transport (macOS 14+) with TCP fallback |
| Snell | ✅ Native Swift | v2/v3 dual-version, AEAD encryption |
| SOCKS5 | ✅ Native Swift | UDP Associate support |
| HTTP CONNECT | ✅ Native Swift | Local proxy server with relay |

### Transport Layer

| Transport | Implementation | Notes |
|-----------|---------------|-------|
| TCP | ✅ `NWConnection` | Network framework |
| TLS | ✅ `NWProtocolTLS` | SNI support |
| WebSocket | ✅ `URLSessionWebSocketTask` | WS framing |
| HTTP/2 | ✅ `URLSessionStreamTask` | Stream multiplexing |
| QUIC | ✅ `NWProtocolQUIC` | Requires macOS 14+ |
| Connection Pool | ✅ | Reusable transport sessions per proxy node |
| Multiplex | ✅ | Multiple logical streams over single transport |

### DNS Subsystem (Fully Self-Developed)

| Component | Status | Notes |
|-----------|--------|-------|
| UDP DNS | ✅ `UDPDNSClient` | Standard port 53 resolution |
| TCP DNS | ✅ `TCPDNSClient` | Length-prefixed framing |
| DNS-over-HTTPS | ✅ `DoHClient` | HTTP POST `application/dns-message` |
| DNS-over-TLS | ✅ `DOTResolver` | Port 853 with SNI |
| DNS-over-QUIC | ✅ `DOQResolver` | RFC 9250, macOS 14+ |
| FakeIP Pool | ✅ | CIDR-based allocation, TTL eviction |
| DNS Cache | ✅ | TTL-aware, domain:type keying |
| Domain Sniffing | ✅ | HTTP CONNECT Host header extraction |
| DNS Pipeline | ✅ | Cascading resolver with fallback |
| Hosts Override | ✅ | Exact match + wildcard patterns |

### Rule Engine

| Rule Type | Status | Notes |
|-----------|--------|-------|
| `DOMAIN` | ✅ | Exact domain match |
| `DOMAIN-SUFFIX` | ✅ | Suffix match |
| `DOMAIN-KEYWORD` | ✅ | Substring match |
| `IP-CIDR` / `IP-CIDR6` | ✅ | IPv4/IPv6 CIDR match |
| `SRC-IP-CIDR` | ✅ | Source IP match |
| `SRC-PORT` / `DST-PORT` | ✅ | Port-based routing |
| `PROCESS-NAME` | ✅ | Application-based routing |
| `GEOIP` | ✅ | Native MMDB binary parser (no external library) |
| `GEOSITE` | ✅ | JSON-based geo-site matching |
| `IP-ASN` | ✅ | ASN-based routing via `GeoSiteAndASNResolver` |
| `RULE-SET` | ✅ | Remote download + auto-refresh |
| `SCRIPT` | ✅ | JavaScript expression engine |
| `NOT` / `REJECT` | ✅ | Negation + silent rejection |
| `MATCH` / `FINAL` | ✅ | Default catch-all rule |

### Proxy Groups

| Group Type | Status | Notes |
|------------|--------|-------|
| `select` | ✅ | Manual selection, persisted choice |
| `url-test` | ✅ | Auto-select lowest latency |
| `fallback` | ✅ | First-available health check |
| `load-balance` | ✅ | Consistent-hash + round-robin strategies |
| `relay` (chain) | ✅ | Config-level multi-hop support |

### Runtime Modes

| Mode | Product status | Notes |
|------|----------------|-------|
| **System Proxy** | Beta | Primary product path via mihomo sidecar and macOS system proxy configuration. |
| **TUN Mode** | Gated | Runtime entry points now reject TUN until real mihomo TUN integration is verified end-to-end. |
| **Direct / Global routing** | Config-level | Available as routing concepts in Clash/mihomo config, not standalone product runtime modes. |

### MITM Framework

| Component | Status | Notes |
|-----------|--------|-------|
| MITM Config | ✅ | Wildcard host matching (`*.example.com`) + exclusion list |
| MITM Manager | ✅ | Config-driven interception decisions with logging hooks |
| HTTPS Interceptor | ✅ | TLS pass-through relay with interception hooks |
| Certificate Authority | ✅ | RSA 2048 keypair scaffolding (ready for ASN.1 library) |
| MITM Settings UI | ✅ | Enable/disable, host patterns, cert install guide, log view |

### App GUI (SwiftUI)

| Feature | Status | Notes |
|---------|--------|-------|
| Config Import | ✅ | File picker for `.yaml` / `.yml` Clash configs |
| Subscription Management | ✅ | Full CRUD: add/edit/delete/update with URL fetch + profile creation |
| Drag & Drop Import | ✅ | Drop `.yaml` files onto app window |
| Proxy Group View | ✅ | Expandable cards, node list, latency display |
| Proxy Selection | ✅ | Wired to mihomo API for real-time switching |
| Delay Testing | ✅ | Group-level or all-proxy batch testing |
| Connection List | ✅ | Real-time table with search filter + close individual/all |
| Traffic Monitor | ✅ | Upload/download speed + cumulative totals |
| Rule Viewer | ✅ | Full rule list with type indicators |
| Log Viewer | ✅ | Level filter, search, auto-scroll, export |
| Menu Bar Extra | Beta | Status icon, traffic speed, profile switching; TUN is shown as unavailable/disabled |
| Theme Manager | ✅ | System / Light / Dark appearance persistence |
| Global Hotkeys | Beta | Configurable shortcuts for verified product actions |
| MITM Settings | Experimental | Interception patterns, certificate management, logging |
| i18n (中文/English) | ✅ | 80+ localized string keys, auto-detect system language |
| Helper Setup | Gated | Historical privileged-helper flow; not product-ready until TUN/signing is verified |

### External Control

| Interface | Status | Notes |
|-----------|--------|-------|
| REST API | ✅ | Clash-compatible endpoints |
| WebSocket Controller | ✅ | Real-time traffic + connection streaming |
| Traffic Stream | ✅ | `GET /traffic` WebSocket endpoint |
| Connection Stream | ✅ | `GET /connections` WebSocket endpoint |
| Proxy Switching | ✅ | `PUT /proxies/{name}` |

### Configuration

| Feature | Status | Notes |
|---------|--------|-------|
| Clash YAML Parser | ✅ | Strict validation, full proxy/ group/ rule parsing |
| Config Merger | ✅ | Deep merge: proxies, proxy-groups, rules, DNS, hosts |
| Node Editor | ✅ | Form-based editor with real-time validation |
| Profile Management | ✅ | Multi-profile support with activation tracking |
| Subscription Auto-Update | ✅ | Background scheduler with configurable intervals |

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                         RiptideApp (SwiftUI)                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ Config   │  │ Proxy    │  │ Traffic  │  │ Rules    │  Tabs    │
│  │ Tab      │  │ Tab      │  │ Tab      │  │ Tab      │          │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘          │
│       └──────────────┴─────────────┴──────────────┘               │
│                              │                                     │
│                    ┌─────────▼─────────┐                           │
│                    │   AppViewModel    │                           │
│                    │   (State Hub)     │                           │
│                    └─────────┬─────────┘                           │
│                              │                                     │
│       ┌──────────────────────┼──────────────────────┐             │
│       │                      │                      │             │
│  ┌────▼────┐  ┌──────────────▼──────────────┐  ┌───▼────┐       │
│  │ Mode    │  │ SubscriptionManager         │  │Hotkey  │       │
│  │Coordi-  │  │ + UpdateScheduler           │  │Manager │       │
│  │nator    │  └─────────────────────────────┘  └────────┘       │
│  └────┬────┘                                                    │
│       │                                                         │
│  ┌────▼──────────────────────────────────────────┐              │
│  │           MihomoRuntimeManager                 │              │
│  │  Config Gen  •  XPC  •  REST API Client       │              │
│  └────┬──────────────────────────────────────────┘              │
└───────┼─────────────────────────────────────────────────────────┘
        │
  ┌─────▼──────┐          ┌─────────────────────────────────────┐
  │ SMJobBless │  XPC     │  RiptideHelper (gated)               │
  │ Manager    │◄────────►│  • Helper/TUN scaffolding             │
  └────────────┘          │  • Not product-ready yet              │
                          │  • Requires signing validation        │
                          └─────────┬───────────────────────────┘
                                    │
                          ┌─────────▼─────────┐
                          │   mihomo sidecar   │
                          │  ┌─────────────┐  │
                          │  │ TUN Stack   │  │  gVisor / lwIP
                          │  │ Proxy Proto │  │  VLESS/VMess/SS/…
                          │  │ REST :9090  │◄─┼── MihomoAPIClient
                          │  │ External WS │  │  WebSocket controller
                          │  └─────────────┘  │
                          └───────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│              Riptide Library (pure Swift)                        │
│  ┌──────────┐ ┌─────────┐ ┌─────────┐ ┌──────────┐            │
│  │Protocols │ │Transport│ │   DNS   │ │  Rules   │             │
│  │ SS/VMess │ │TCP/TLS/ │ │UDP/TCP/ │ │GEOIP/    │             │
│  │ VLESS/…  │ │WS/QUIC/ │ │DoH/DoT/ │ │GEOSITE/  │             │
│  │          │ │HTTP2    │ │DoQ      │ │RULE-SET  │             │
│  └──────────┘ └─────────┘ └─────────┘ └──────────┘             │
│  ┌──────────┐ ┌─────────┐ ┌─────────┐ ┌──────────┐            │
│  │Connection│ │ Tunnel  │ │  MITM   │ │ External │             │
│  │ProxyConn │ │Runtime/ │ │Config/  │ │Controller│             │
│  │          │ │Lifecycle│ │Intercept│ │REST/WS   │             │
│  └──────────┘ └─────────┘ └─────────┘ └──────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### Requirements

- **macOS 14+** (Sonoma or later)
- **Swift 6.2+** / **Xcode 16+** (when building from source)
- A local **mihomo** binary for the product System Proxy runtime
- TUN mode is currently gated; do not rely on sudo/helper/NetworkExtension flows for product use yet.


### 安装方式

#### macOS (DMG 下载)

1. 从 [GitHub Releases](https://github.com/G3niusYukki/Riptide/releases) 下载 `Riptide-x.x.x-arm64.dmg`
2. 打开 DMG，将 RiptideApp 拖入 Applications 文件夹
3. **直接双击会提示"已损坏"，请按以下步骤操作：**

   **方法一（推荐）：终端运行**
   ```bash
   xattr -cr /Applications/RiptideApp.app
   ```
   然后正常打开即可。

   **方法二：系统设置**
   - 双击 App（会弹出"已损坏"提示，点"取消"）
   - 打开 **系统设置 → 隐私与安全性**
   - 滚动到底部，找到 "RiptideApp 已被阻止..."
   - 点击 **"仍要打开"**，输入密码确认

> **为什么会有这个提示？** Riptide 没有 Apple 开发者证书（$99/年），macOS Gatekeeper 会阻止未签名应用运行。App 本身完全开源且安全，只是没有付费签名。运行 `xattr -cr` 只是移除"从互联网下载"的标记。

#### macOS (Homebrew)

```bash
brew tap G3niusYukki/riptide
brew install riptide
```

#### macOS (从源码构建)

```bash
git clone https://github.com/G3niusYukki/Riptide.git
cd Riptide
swift build
```

#### Windows

Windows is not a shipped product target for this Swift package in the current product-readiness phase.

### 2. 下载 mihomo Binary

```bash
./Scripts/download-mihomo.sh
```

Downloads the mihomo core binary (universal binary for Intel + Apple Silicon).

### 3. Run Tests

```bash
swift test
```

All **366 tests in 57 suites** should pass.

### 4. Run the App

**Via Xcode** (recommended):
```
Open project → Select "RiptideApp" scheme → Run
```

**Via command line**:
```bash
swift run RiptideApp
```

### 5. TUN / Helper status

TUN mode and privileged helper flows are intentionally not product-exposed in this phase. Keep them disabled until mihomo TUN integration, signing/entitlements, privilege installation, and system-proxy cleanup are verified end-to-end.

---

## Usage

### Import Configuration

1. **File Import**: Click "导入配置文件" → select `.yaml` / `.yml` Clash config
2. **Drag & Drop**: Drop config files directly onto the app window
3. **Subscription**: Click "+" in Subscriptions section → paste URL → auto-fetch nodes

### System Proxy Mode

1. Import or create a configuration profile
2. Select "系统代理" mode
3. Click "启动" — macOS system proxy is configured automatically

### TUN Mode

TUN mode is currently gated. Product UI should hide or disable it, and runtime entry points reject `.tun` until the mihomo-backed TUN path is verified end-to-end.

### Proxy Switching

In the **代理** tab:
- Expand any proxy group card
- Click a node to switch the active proxy
- Click "延迟测试" to batch-test latency

### Connection Monitoring

In the **流量** tab:
- View real-time upload/download speeds
- See active connections with domain, protocol, and proxy node
- Search/filter connections
- Close individual or all connections

### Log Viewing

In the **日志** tab:
- Filter by level (debug / info / warning / error)
- Search log messages
- Export logs to a text file

### Keyboard Shortcuts

Configure in HotkeyManager:
- **Option+Control+P**: Toggle proxy on/off
- **Option+Control+M**: Switch mode

### MITM Interception

1. Open MITM Settings view
2. Enable MITM
3. Add host patterns (`*.example.com`, `example.com`)
4. Add exclusion patterns for hosts to skip
5. Install the CA certificate via Keychain Access

---

## Project Structure

```
Riptide/
├── Package.swift                 # SPM manifest (3 targets + 2 deps)
├── README.md                     # This file
├── AGENTS.md                     # Development conventions
│
├── Sources/
│   ├── Riptide/                  # Core library (pure Swift)
│   │   ├── AppShell/             # App-facing coordinators
│   │   │   ├── ModeCoordinator.swift
│   │   │   ├── ConfigImportService.swift
│   │   │   ├── ProfileStore.swift
│   │   │   ├── SystemProxyController.swift
│   │   │   ├── SystemProxyGuard.swift
│   │   │   └── …
│   │   ├── Config/               # Clash YAML parsing & merging
│   │   │   ├── ClashConfigParser.swift
│   │   │   └── ConfigMerger.swift
│   │   ├── Connection/           # Proxy connection orchestration
│   │   │   └── Proxy_connector.swift
│   │   ├── Control/              # REST API + WebSocket external controller
│   │   │   ├── ExternalController.swift
│   │   │   └── WebSocketExternalController.swift
│   │   ├── DNS/                  # Full DNS stack (10 files)
│   │   │   ├── UDPDNSClient.swift
│   │   │   ├── TCPDNSClient.swift
│   │   │   ├── DoHClient.swift
│   │   │   ├── DOTResolver.swift
│   │   │   ├── DOQResolver.swift
│   │   │   ├── DNSCache.swift
│   │   │   ├── DNSPipeline.swift
│   │   │   ├── DNSPolicy.swift
│   │   │   ├── DNSMessage.swift
│   │   │   └── FakeIPPool.swift
│   │   ├── Groups/               # Proxy group management
│   │   │   ├── ProxyGroup.swift
│   │   │   ├── ProxyGroupManager.swift
│   │   │   ├── ProxyGroupResolver.swift
│   │   │   └── LoadBalancer.swift
│   │   ├── HealthCheck/          # Health checking
│   │   │   └── HealthChecker.swift
│   │   ├── LocalProxy/           # Local HTTP CONNECT server
│   │   │   └── LocalHTTPConnectProxyServer.swift
│   │   ├── Logging/              # Log types
│   │   │   └── LogTypes.swift
│   │   ├── Mihomo/               # mihomo sidecar integration
│   │   │   ├── MihomoAPIClient.swift
│   │   │   ├── MihomoConfigGenerator.swift
│   │   │   ├── MihomoLogClient.swift
│   │   │   ├── MihomoPaths.swift
│   │   │   └── MihomoRuntimeManager.swift
│   │   ├── MITM/                 # HTTPS interception framework
│   │   │   ├── MITMConfig.swift
│   │   │   ├── MITMManager.swift
│   │   │   ├── MITMHTTPSInterceptor.swift
│   │   │   └── CertificateAuthority.swift
│   │   ├── Models/               # Core data models
│   │   │   └── ProxyModels.swift
│   │   ├── NodeEditor/           # Proxy node editing & validation
│   │   │   ├── EditableProxyNode.swift
│   │   │   └── ProxyNodeValidator.swift
│   │   ├── Protocols/            # Protocol framing (6 protocol dirs)
│   │   │   ├── HTTPConnectProtocol.swift
│   │   │   ├── OutboundProtocol.swift
│   │   │   ├── SOCKS5Protocol.swift
│   │   │   ├── Shadowsocks/      # AEAD cipher + stream
│   │   │   ├── VMess/
│   │   │   ├── VLESS/
│   │   │   ├── Trojan/
│   │   │   ├── Hysteria2/
│   │   │   └── Snell/
│   │   ├── ProxyProvider/        # Proxy provider abstraction
│   │   ├── Rules/                # Rule engine + GeoIP
│   │   │   ├── RuleEngine.swift
│   │   │   ├── GeoIPDatabase.swift
│   │   │   ├── GeoIPResolver.swift
│   │   │   ├── GeoSiteAndASNResolver.swift
│   │   │   ├── RuleScriptEngine.swift
│   │   │   ├── RuleSet.swift
│   │   │   └── RuleSetProvider.swift
│   │   ├── Scripting/            # Script engine
│   │   │   └── ScriptEngine.swift
│   │   ├── Subscription/         # Subscription management
│   │   │   ├── SubscriptionManager.swift
│   │   │   ├── SubscriptionUpdateScheduler.swift
│   │   │   └── ProxyURIParser.swift
│   │   ├── Traffic/              # Traffic monitoring
│   │   │   ├── MihomoTrafficProvider.swift
│   │   │   └── TrafficViewModel.swift
│   │   ├── Transport/            # Transport layer (7 implementations)
│   │   │   ├── NetworkTransport.swift
│   │   │   ├── TLSTransport.swift
│   │   │   ├── WSTransport.swift
│   │   │   ├── HTTP2Transport.swift
│   │   │   ├── QUICTransport.swift
│   │   │   ├── MultiplexTransport.swift
│   │   │   └── TransportConnectionPool.swift
│   │   ├── Tunnel/               # Runtime & lifecycle
│   │   │   ├── LiveTunnelRuntime.swift
│   │   │   ├── TunnelLifecycleManager.swift
│   │   │   └── TunnelModels.swift
│   │   ├── VPN/                  # TUN providers & packet handling
│   │   │   ├── TUNRoutingEngine.swift
│   │   │   ├── UserSpaceTCP.swift
│   │   │   ├── PacketTunnelProvider.swift
│   │   │   ├── TCPTunnelForwarder.swift
│   │   │   ├── UDPSessionManager.swift
│   │   │   ├── UDPTunnelSession.swift
│   │   │   ├── VPNTunnelManager.swift
│   │   │   └── …
│   │   └── XPC/                  # Helper tool communication
│   │       ├── HelperToolProtocol.swift
│   │       └── HelperToolConnection.swift
│   │
│   ├── RiptideApp/               # SwiftUI client
│   │   ├── App/                  # Theme, hotkeys, drop delegate, tab view
│   │   ├── Localization/         # i18n system (zh-Hans, en)
│   │   ├── ViewModels/           # App view models
│   │   ├── Views/                # All SwiftUI views
│   │   ├── AppViewModel.swift    # Central state management
│   │   └── RiptideApp.swift      # App entry point
│   │
│   └── RiptideCLI/               # Command-line interface
│       └── …
│
├── Tests/RiptideTests/           # 366 tests in 57 suites
│   ├── DNS/
│   ├── MITM/
│   └── … (35 root-level test files)
│
├── Resources/
│   ├── zh-Hans.json              # Chinese translations
│   └── en.json                   # English translations
│
└── Scripts/
    └── download-mihomo.sh        # Download mihomo binary
```

---

## Build & Test

```bash
# Build all targets
swift build

# Run tests
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

---

## 对比其他客户端

| 功能 | Riptide | Clash Verge Rev | Hiddify Next |
|------|---------|-----------------|-------------|
| 核心引擎 | ⚠️ mihomo product path + Swift experimental stack | ❌ mihomo 封装 | ❌ sing-box 封装 |
| macOS 集成 | ⚠️ SwiftUI beta | ⚠️ Tauri | ⚠️ Flutter |
| Windows 支持 | ❌ 暂无产品目标 | ✅ Tauri | ✅ Flutter |
| Linux 支持 | ❌ 暂无 | ✅ 支持 | ✅ 支持 |
| TUN 模式 | ❌ Gated until verified | ✅ mihomo | ✅ sing-box |
| 无需证书运行 | ⚠️ System Proxy path only | ✅ | ✅ |
| WebDAV 同步 | ✅ | ✅ | ❌ |
| Profile 持久化 | ✅ | ✅ | ✅ |
| 安装包大小 | ~15MB | ~40MB | ~50MB |


## 安装指南

- [完整安装指南](docs/INSTALL.md) - 可能包含历史安装说明；请以本 README 的当前能力矩阵为准
- [从 Clash Verge Rev 迁移](docs/MIGRATION.md) - 迁移说明仍需按当前 Beta 能力重新验证

---

## Security

### Privileged Helper / TUN status

Privileged helper and TUN flows are not product-ready in this phase. Historical helper scaffolding exists, but it must not be treated as verified product behavior until signing, installation, privilege boundaries, NetworkExtension/TUN behavior, and recovery cleanup are tested end-to-end.

The intended helper capability boundary is:

- Launches mihomo **only** from `/Library/Application Support/Riptide/mihomo/`
- Validates all config paths are within the allowed directory
- Terminates mihomo process on request
- No arbitrary command execution

### Code Signing

Both the main app and helper must be signed with the **same Apple Developer Team ID**. The helper's `Info.plist` embeds the allowed client Team ID for XPC authentication.

### Network Security

- TLS connections use Network.framework's built-in TLS verification
- Certificate validation is enforced (no skip-cert-verify by default)
- Proxy credentials are never logged

---

## Contributing

Contributions are welcome. Please follow these guidelines:

1. **Library-first**: New protocol/transport logic belongs in `Sources/Riptide/`, not the app layer
2. **Swift 6 concurrency**: All code must pass Swift 6 strict concurrency checks
3. **Test coverage**: Add tests for new functionality
4. **No force unwraps**: Use proper error handling throughout
5. **No silent fallbacks**: Fail explicitly rather than silently degrading
6. **Documentation**: Update this README for user-facing changes
7. **Modular**: Keep changes scoped and dependency-injected

---

## License

MIT License — See [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- **[mihomo](https://github.com/MetaCubeX/mihomo)** — The proxy core that powers Riptide's runtime mode
- **[Clash](https://github.com/Dreamacro/clash)** — Original configuration format that Riptide is compatible with
- **[Yams](https://github.com/jpsim/Yams)** — YAML parsing library
