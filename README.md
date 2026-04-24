# Riptide

A native Swift proxy client for macOS and Windows. Riptide combines a **Swift-native proxy engine** with optional [mihomo](https://github.com/MetaCubeX/mihomo) sidecar integration, delivering a Clash-compatible configuration system, TUN mode, and a polished native user interface.

> **Architecture**: Library-first design. The `Riptide` library implements protocol framing, transport orchestration, DNS resolution, rule matching, and connection lifecycle management — all in pure Swift. The `RiptideApp` SwiftUI client (macOS) / WebView2 client (Windows) and the `mihomo` sidecar are interchangeable consumers of this library.

**Status**: v1.2.0 — Full mihomo sidecar integration, native SwiftUI app, System Proxy & TUN modes, subscription management, profile persistence, sudo-based privilege escalation (no developer certificate required).


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

### 跨平台支持

| 平台 | 状态 | 说明 |
|------|------|------|
| macOS 14+ | ✅ 完整支持 | SwiftUI 原生界面，完整 TUN 支持 |
| Windows 10/11 | ✅ v1.0+ 支持 | WebView2 界面，MSI 安装包 |
| Linux | ❌ 计划中 | - |

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

| Mode | Status | Notes |
|------|--------|-------|
| **System Proxy** | ✅ | macOS system proxy via `Network` framework |
| **TUN Mode** | ✅ | Full userspace TCP stack + DNS interception |
| **Direct** | ✅ | All traffic bypasses proxy |
| **Global** | ✅ | All traffic through single proxy node |

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
| Menu Bar Extra | ✅ | Status icon, traffic speed, profile switching, mode selector |
| Theme Manager | ✅ | System / Light / Dark appearance persistence |
| Global Hotkeys | ✅ | Configurable shortcuts (e.g., toggle proxy, switch mode) |
| MITM Settings | ✅ | Interception patterns, certificate management, logging |
| i18n (中文/English) | ✅ | 80+ localized string keys, auto-detect system language |
| Helper Setup | ✅ | Guided installation flow for privileged XPC helper |

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
  │ SMJobBless │  XPC     │  RiptideHelper (root, privileged)   │
  │ Manager    │◄────────►│  • Launch/terminate mihomo           │
  └────────────┘          │  • Validate config paths             │
                          │  • TUN device management             │
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

- **macOS 14+** (Sonoma or later) OR **Windows 10/11**
- **Swift 6.2+** / **Xcode 16+** (仅用于从源码构建 macOS 版本)
- Apple Developer certificate **可选** — 不需要证书也能使用 TUN 模式（通过 sudo 获取权限）


### 安装方式

#### macOS (DMG 下载)

1. 从 [GitHub Releases](https://github.com/G3niusYukki/Riptide/releases) 下载 `Riptide-x.x.x-arm64.dmg`
2. 打开 DMG，将 RiptideApp 拖入 Applications 文件夹
3. **首次打开会提示"已损坏"或"无法验证开发者"**，需要手动允许：
   - 打开 **系统设置 → 隐私与安全性**
   - 滚动到底部，找到 "RiptideApp 已被阻止使用，因为来自身份不明的开发者"
   - 点击 **"仍要打开"**
   - 或者在终端运行：`xattr -cr /Applications/RiptideApp.app`

> **为什么会有这个提示？** Riptide 没有 Apple Developer 证书 ($99/年)，所以 macOS Gatekeeper 会阻止运行。App 本身是安全的，代码完全开源。

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

#### Windows (MSI 安装包)

从 [GitHub Releases](https://github.com/G3niusYukki/Riptide/releases) 下载 `.msi` 安装包并运行。

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

### 5. (Optional) Install Privileged Helper for TUN Mode

By default, Riptide uses `sudo` to get root privileges for TUN mode. macOS will prompt for your password at each launch (cached 5-15 minutes).

If you have an Apple Developer certificate, you can install the privileged helper for a smoother experience (no password prompt after installation):

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

4. In the app, go to Helper Setup and click "安装 Helper"

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

1. Select "TUN 模式" mode
2. Click "启动"
3. macOS 会弹出密码框，输入管理员密码（首次需要，之后缓存 5-15 分钟）
4. All system traffic routes through the TUN interface

> **无需证书**: Riptide 通过 sudo 获取 root 权限来创建 TUN 接口，不需要 Apple Developer 证书。
> 如果安装了 Helper 工具（需要证书），启动时不会弹出密码框。

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
| 核心引擎 | ✅ Swift 自研 + mihomo | ❌ mihomo 封装 | ❌ sing-box 封装 |
| macOS 集成 | ✅ SwiftUI 原生 | ⚠️ Tauri | ⚠️ Flutter |
| Windows 支持 | 🔧 开发中 | ✅ Tauri | ✅ Flutter |
| Linux 支持 | ❌ 暂无 | ✅ 支持 | ✅ 支持 |
| TUN 模式 | ✅ sudo / Helper | ✅ mihomo | ✅ sing-box |
| 无需证书运行 | ✅ sudo 模式 | ✅ | ✅ |
| WebDAV 同步 | ✅ | ✅ | ❌ |
| Profile 持久化 | ✅ | ✅ | ✅ |
| 安装包大小 | ~15MB | ~40MB | ~50MB |


## 安装指南

- [完整安装指南](docs/INSTALL.md) - 包含 macOS 和 Windows 的详细安装步骤
- [从 Clash Verge Rev 迁移](docs/MIGRATION.md) - 平滑迁移指南

---

## Security

### Privileged Helper (TUN Mode)

RiptideHelper runs as root via `SMJobBless`. Its capabilities are strictly limited:

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
