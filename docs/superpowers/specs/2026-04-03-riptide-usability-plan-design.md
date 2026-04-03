# Riptide 可用性提升方案设计

**版本:** 1.0
**日期:** 2026-04-03
**状态:** 已批准

---

## 1. 背景与目标

Riptide 目前已实现核心代理引擎（HTTP CONNECT、SOCKS5、Shadowsocks）、传输层（TCP 连接池）、规则引擎和本地代理服务器，但存在以下问题导致无法真正投入使用：

- VMess / VLESS / Trojan / Hysteria2 协议代码存在但未接入运行时
- TLS 和 WebSocket 传输层不完整
- Config parser 不支持 proxy-groups 和 dns 配置
- ProxyGroupResolver 未接入
- DNS Pipeline 存在但从未被调用
- TUN/VPN 模式仅有存根
- SwiftUI App 是空壳，无真实功能

本设计的目标是让 Riptide 能够：**加载真实 Clash 配置文件，连接 VLESS/Trojan/Shadowsocks 代理服务器，实现规则路由 + DNS 解析 + TUN 全局代理，并提供完整的 macOS 应用界面。**

---

## 2. 架构总览

```
┌──────────────────────────────────────────────────────┐
│                    RiptideApp (SwiftUI)               │
│  ┌──────────┐  ┌─────────────────┐  ┌────────────┐ │
│  │StatusBar │  │   MainWindow    │  │ Dock Icon  │ │
│  │(NSStatus │  │  TabView:       │  │ (badge)     │ │
│  │ Item)    │  │  Config         │  │             │ │
│  │ Quick:   │  │  Proxies        │  │             │ │
│  │ -开关    │  │  Traffic        │  │             │ │
│  │ -节点    │  │  Rules          │  │             │ │
│  │ -速度    │  │  Logs           │  │             │ │
│  └────┬─────┘  └────────┬────────┘  └──────┬─────┘ │
└───────┼──────────────────┼───────────────────┼────────┘
        └──────────────────┴───────────────────┘
                          │
              ┌───────────┴────────────┐
              │    AppViewModel         │
              │  (ObservableObject)    │
              │  - tunnelState         │
              │  - activeConfig        │
              │  - trafficStats        │
              │  - proxyGroups         │
              │  - runtimeEvents/logs  │
              └───────────┬────────────┘
                          │
┌─────────────────────────┴──────────────────────────────────┐
│                    Riptide Core Library                     │
│                                                          │
│  LiveTunnelRuntime                                        │
│    ├─ DNSPipeline (Fake-IP, newly wired)                  │
│    ├─ ProxyGroupResolver (newly wired)                    │
│    ├─ RuleEngine                                          │
│    └─ ProxyConnector                                      │
│         ├─ Shadowsocks  ✅  (fully wired)                 │
│         ├─ VLESS       🟡  (fix + wire)                   │
│         ├─ Trojan      🟡  (fix + wire)                   │
│         ├─ HTTP CONNECT ✅  (fully wired)                 │
│         └─ SOCKS5      ✅  (fully wired)                   │
│                                                          │
│  Transport Layer                                          │
│    ├─ TCP       ✅  (fully wired)                         │
│    ├─ TLS       🟡  (fix: skipCertVerify + cancellation) │
│    └─ WebSocket 🔴  (implement via URLSessionWebSocketTask)│
│                                                          │
│  Config                                                   │
│    └─ ClashConfigParser (extended: proxy-groups, dns,     │
│                          vmess/vless/trojan types)        │
│                                                          │
│  TUN Mode                                                 │
│    ├─ PacketTunnelProvider (new: Network Extension)       │
│    ├─ PacketHandler (packet parse + inject)               │
│    ├─ UserSpaceTCP (TCP state machine)                    │
│    └─ UDP Relay (DNS → Fake-IP, others passthrough)      │
└──────────────────────────────────────────────────────────┘
```

**关键决策：**
- `AppViewModel` 是唯一的中介层，SwiftUI views 只依赖它
- Core library 保持 CLI 可独立使用，不依赖 SwiftUI
- 状态栏和主窗口共享同一个 `AppViewModel`
- VMess 和 Hysteria2 暂不实现（crypto 需要完全重写 / QUIC 依赖）
- VLESS 和 Trojan 接入但不包含 XTLS Vision / QUIC 等高级特性

---

## 3. Core Engine 改动

### 3.1 ProxyNode 模型扩展

新增字段支持 VLESS、VMess、Trojan、TLS 和 WebSocket：

```swift
struct ProxyNode {
    // 现有
    var name: String
    var kind: ProxyKind  // .http, .socks5, .shadowsocks, .vmess, .vless, .trojan, .hysteria2
    var server: String
    var port: Int
    var cipher: String?      // Shadowsocks
    var password: String?    // Shadowsocks, Trojan

    // 新增 — VLESS / VMess
    var uuid: String?
    var flow: String?         // VLESS XTLS flow, e.g. "xtls-rprx-vision"
    var alterId: Int?         // VMess legacy
    var security: String?     // "auto", "tls", "none"

    // 新增 — TLS
    var sni: String?
    var alpn: [String]?
    var skipCertVerify: Bool?

    // 新增 — Transport
    var network: String?     // "tcp", "ws", "grpc"
    var wsPath: String?
    var wsHost: String?
    var grpcServiceName: String?

    // Hysteria2 暂不支持
}
```

### 3.2 协议修复与接入

| 协议 | 当前状态 | 需要做的 | 优先级 |
|------|---------|---------|--------|
| **Shadowsocks** | ✅ 完全可用 | 无 | — |
| **HTTP CONNECT** | ✅ 完全可用 | 无 | — |
| **SOCKS5** | ✅ 完全可用 | 无 | — |
| **VLESS** | 🟡 ~50%，未接入 | 修复 IPv6 编码 bug（ATYP=3 时应编码 16 字节 raw bytes 而非 domain-style）；addons 从 raw string 改为 protobuf 格式；wire 进 ProxyConnector | P1 |
| **Trojan** | 🟡 ~25%，未接入 | SHA-256 → SHA-224（协议规定）；添加 outbound hex-length CRLF framing；添加 inbound length-prefixed frame 解析；强制要求 TLS（throw `tlsRequired`）；wire 进 ProxyConnector | P1 |
| **VMess** | 🔴 ~30%，未接入 | 跳过 — AES-GCM 应为 AES-CFB、auth ID 应为 MD5(UUID) 而非随机字节、header length byte 错误，需要完全重写 crypto 层 | 暂不支持 |
| **Hysteria2** | 🔴 stub | 跳过 — 需要 QUIC 实现 | 暂不支持 |

**ProxyConnector 接入逻辑：**

```swift
ProxyConnector.connect(via: node, to: target) {
    // 1. 选择 transport chain
    let transport: any TransportDialer = selectTransport(node)
    // 2. 获取连接
    let session = await pool.acquire(for: node, using: transport)
    // 3. 协议握手
    switch node.kind {
    case .vless:    return performVLESSConnect(session, node, target)
    case .trojan:   return performTrojanConnect(session, node, target)
    case .shadowsocks: return performShadowsocksConnect(session, node, target)
    case .http:     return performHTTPConnect(session, node, target)
    case .socks5:   return performSOCKS5Connect(session, node, target)
    case .vmess, .hysteria2: throw .unsupportedProxyKind
    }
}

func selectTransport(node: ProxyNode) -> any TransportDialer {
    let useTLS = node.port == 443 || node.sni != nil || node.skipCertVerify != nil
    if node.network == "ws" || node.network == "grpc" {
        return TLSDialer(WSDialer(TCPDialer()))  // WS over TLS over TCP
    } else if useTLS {
        return TLSDialer(TCPDialer())  // TLS over TCP
    } else {
        return TCPDialer()  // Plain TCP
    }
}
```

### 3.3 Transport 层

| Transport | 当前状态 | 需要做的 | 优先级 |
|-----------|---------|---------|--------|
| **TCP** | ✅ 完全可用 | 无 | — |
| **TLS** | 🟡 ~70% | 修复 `skipCertVerify` 实际生效（`sec_protocol_options_set_tls_verify_peer`）；添加 connection timeout（15s）；添加 task cancellation 支持 | P1 |
| **WebSocket** | 🔴 0% | 用 `URLSessionWebSocketTask` 实现完整 WebSocket：handshake（RFC 6455）、frame encode/decode（text + binary）、ping/pong、close；`openSession` 需解析 `ws://host:port/path` URL | P1 |

### 3.4 Config Parser 扩展

新增解析内容：

```
Clash YAML Config
  ├─ proxies[]:
  │    ├─ ss { cipher, password, name, server, port }
  │    ├─ vmess { uuid, alterId, security, ... }     ← 新增
  │    ├─ vless { uuid, flow, network, ws-opts, ... } ← 新增
  │    ├─ trojan { password, sni, skip-cert-verify, } ← 新增
  │    ├─ socks5 { name, server, port }
  │    └─ http { name, server, port }
  │
  ├─ proxy-groups[]:                                   ← 新增
  │    ├─ { name, type: select|url-test|fallback|load-balance, proxies[] }
  │    └─ { name, type: select, proxies[], "initial": nodeName }
  │
  ├─ dns:                                              ← 新增
  │    ├─ enable: true
  │    ├─ listen: 0.0.0.0:53
  │    ├─ fake-ip-range: 198.18.0.0/15
  │    ├─ nameserver: [8.8.8.8, 1.1.1.1]
  │    ├─ fallback: [8.8.4.4, 1.0.0.1]
  │    └─ nameserver-policy: { "+.example.com": [...] }
  │
  ├─ rules[]:
  │    ├─ DOMAIN-SUFFIX,google.com,代理
  │    ├─ GEOIP,CN,DIRECT
  │    ├─ MATCH,DIRECT
  │    └─ ...
  │
  └─ mode: rule|global|direct
```

### 3.5 Proxy Group 接入

`LiveTunnelRuntime.openConnection` 增加分组解析步骤：

```
RuleEngine.resolve(target:) → .proxyNode(name: "auto-select")
  → 查找 name 是否匹配 ProxyGroup
    → 是 → ProxyGroupResolver.resolve(groupID:)
             ├─ Select: 返回持久化的用户选择节点（默认第一个）
             ├─ URL-Test: 返回延迟最低的节点（HealthChecker）
             ├─ Fallback: 返回第一个存活的节点
             └─ LoadBalance: 随机返回
    → 否 → 直接查找 leaf ProxyNode
  → connector.connect(via: node, to: target)
```

**Phase 1 只实现 Select 类型**，URL-Test / Fallback / LoadBalance 后续迭代。

`GroupSelector` 存在但未使用 — 从 `HealthChecker` 中整合到 `ProxyGroupResolver`。

### 3.6 DNS Pipeline 接入

```
LiveTunnelRuntime.openConnection(target:)
  → target.host 是域名？
    → 是 → DNSPipeline.resolve(host)
             ├─ 检查内存缓存（DNSCache）
             ├─ 检查 Fake-IP 池（isFakeIP）
             └─ 向上游 DNS 服务器查询（UDP 或 DoH）
    → 替换 target.host 为解析后 IP，保留原始域名用于 SNI/Host
  → 后续走正常 proxy connect
```

**Fake-IP 模式：** TUN 开启后，由 `DNSPipeline.resolveFakeIP()` 分配 198.18.x.x 地址，规则引擎基于原始域名匹配，结果缓存。

### 3.7 TUN/VPN 模式

**架构：**

```
系统所有流量 → utun 虚拟网卡 (PacketTunnelProvider)
  → PacketHandler 解析 IP 包
    ├─ TCP: UserSpaceTCP 状态机 → ConnectionRelay → proxy
    └─ UDP:
         ├─ DNS (port 53): Fake-IP 分配 → DNSPipeline → proxy
         └─ 其他: 直传或 proxy（按规则）
  → DNS 拦截: Fake-IP 模式 → 规则引擎按域名匹配
```

**需要实现的组件：**

| 组件 | 当前状态 | 需要做的 |
|------|---------|---------|
| **PacketTunnelProvider** | 不存在 | 新建 `RiptideTunnel` Network Extension target；子类化 `PacketTunnelProvider`；`startTunnel` 创建 utun、启动核心引擎；`stopTunnel` 清理 |
| **Network Extension target** | 不存在 | Xcode 新增 `RiptideTunnel` target；`com.apple.developer.networking.networkextension` entitlement |
| **PacketHandler** | 仅解析 | 补充包注入（`writePackets` 回写到 utun） |
| **UserSpaceTCP** | 部分 TCP 状态机 | 完善 SYN/ACK/FIN/RST 处理；连接 lifecycle 与 proxy relay 对齐 |
| **UDP relay** | 不存在 | 新建：DNS 走 Fake-IP，其他按规则决定直连或 proxy |
| **VPNTunnelManager** | stub | 接入 `NETunnelProviderManager`；VPN 配置安装/连接/断开/状态查询 |
| **TunnelProviderBridge** | scaffolded | App ↔ Extension App Group 双向通信：命令（启动/停止/切换模式）、事件（状态/统计/日志） |

**运行模式切换：**

```
用户选择模式:
  ├─ 系统代理模式 → LocalHTTPConnectProxyServer（HTTP CONNECT）
  └─ TUN 模式    → PacketTunnelProvider（全流量代理）
```

两种模式共享同一个 `LiveTunnelRuntime` 核心。

---

## 4. UI 设计

### 4.1 状态栏 (NSStatusItem)

```
┌─────────────────────────────────────┐
│  🟢 Riptide   ▼                     │
├─────────────────────────────────────┤
│  ● 已连接 · 节点: Tokyo-01          │
│  ↑ 2.3 MB/s  ↓ 5.1 MB/s           │
├─────────────────────────────────────┤
│  模式: 规则                          │
│    ├─ 规则                           │
│    ├─ 全局                           │
│    └─ 直连                           │
├─────────────────────────────────────┤
│  代理组: 自动选择                    │
│    ├─ Tokyo-01          42ms  ✓    │
│    ├─ Singapore-01      68ms       │
│    ├─ US-West-01        120ms      │
│    └─ ──── 延迟测试 ────           │
├─────────────────────────────────────┤
│  打开主窗口                         │
│  退出                               │
└─────────────────────────────────────┘
```

- 灰色 = 未连接，绿色 = 已连接，黄色 = 连接中
- 速度显示实时更新（1 秒刷新）
- 代理组列表可直接切换，无需打开主窗口
- 延迟测试按钮在菜单内触发

### 4.2 主窗口

```
┌─ Riptide ────────────────────────────────────────────────┐
│  ┌─ 配置 ─┬─ 代理 ─┬─ 流量 ─┬─ 规则 ─┬─ 日志 ─┐         │
│  │        │        │        │        │        │           │
│  └────────┴────────┴────────┴────────┴────────┘           │
│  (当前 Tab 内容区)                                         │
└──────────────────────────────────────────────────────────┘
```

**深色主题设计：**
- 背景: `#1a1a2e` → `#16213e` 渐变
- 卡片: 毛玻璃效果 (`.ultraThinMaterial`)
- 圆角: 12px 卡片, 8px 按钮
- 强调色: `#0fbcf9` (蓝) / `#0be881` (绿-连接) / `#fd7272` (红-断开)
- 字体: SF Pro，标题 13pt semibold，正文 12pt regular

### 4.3 各 Tab 详情

#### Tab 1: 配置管理

```
┌─────────────────────────────────────────┐
│  配置文件                    [+ 导入]    │
├─────────────────────────────────────────┤
│  ┌─ 我的服务器.yaml ──── 激活 ──────┐   │
│  │  节点: 12  规则: 86  更新: 今天   │   │
│  │  [编辑] [更新] [删除]              │   │
│  └────────────────────────────────────┘   │
│  ┌─ 订阅列表 ────────────────────────┐   │
│  │  名称          URL        更新    │   │
│  │  航空节点      https://..  2h前   │   │
│  │              [+ 添加订阅]          │   │
│  └────────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

- 支持导入本地 `.yaml` 文件 + 订阅 URL（支持 base64 / gzip 订阅）
- 订阅支持自动更新间隔设置（1h / 6h / 12h / 24h）
- 激活配置高亮显示，一键切换

#### Tab 2: 代理节点

```
┌─────────────────────────────────────────┐
│  代理节点              [全部延迟测试]     │
├─────────────────────────────────────────┤
│  ▾ 自动选择 (Select)                    │
│    ├─ 🟢 Tokyo-01           42ms   ●   │
│    ├─ 🟢 Singapore-01      68ms       │
│    ├─ 🟡 US-West-01        120ms       │
│    └─ 🔴 HK-03            timeout      │
│                                         │
│  ▾ 流媒体 (Select)                      │
│    ├─ 🟢 US-Netflix-01      85ms   ●   │
│    └─ 🟢 SG-Netflix-01      92ms       │
│                                         │
│  ▸ 自动测试 (URL-Test)                  │
│  ▸ 故障转移 (Fallback)                  │
│  ▸ 负载均衡 (LoadBalance)               │
│                                         │
│  直连                                    │
│  拒绝                                    │
└─────────────────────────────────────────┘
```

- 分组折叠展示，选中节点高亮
- 延迟颜色：绿 <100ms，黄 <300ms，红 >300ms/超时
- 点击节点立即切换，触发 `ProxyGroupResolver`
- URL-Test/Fallback/LoadBalance 显示当前自动选择结果

#### Tab 3: 流量统计

```
┌─────────────────────────────────────────┐
│  流量统计                    [重置]      │
├─────────────────────────────────────────┤
│     ↑ 1.2 GB          ↓ 4.8 GB         │
│     上传               下载             │
│                                         │
│  ── 实时速率 ─────────────────────       │
│  ↑ 2.3 MB/s     ↓ 5.1 MB/s            │
│                                         │
│  ── 活跃连接 ────────── 总: 47 ──      │
│  ┌──────────────────────────────────┐   │
│  │ google.com       TCP  Tokyo-01  43 │   │
│  │ github.com       TCP  SG-01    12 │   │
│  │ api.openai.com   TCP  US-01    8  │   │
│  │ ...                              │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

- 速率用 sparkline 图表（最近 60 秒）
- 活跃连接列表实时更新（目标 host、协议、代理节点、连接数）

#### Tab 4: 规则/路由

```
┌─────────────────────────────────────────┐
│  路由规则                   模式: 规则   │
├─────────────────────────────────────────┤
│  当前模式:                              │
│  ● 规则  ○ 全局  ○ 直连                │
│                                         │
│  ── 规则列表 ────────────────── 共 86 ──│
│  ┌──────────────────────────────────┐   │
│  │ DOMAIN-SUFFIX  google.com    代理 │   │
│  │ DOMAIN-SUFFIX  github.com    代理 │   │
│  │ GEOIP          CN           直连 │   │
│  │ MATCH          *            代理 │   │
│  └──────────────────────────────────┘   │
│                                         │
│  ── 实时匹配日志 ──────────────────      │
│  ┌──────────────────────────────────┐   │
│  │ google.com    → DOMAIN-SUFFIX     │   │
│  │              → 自动选择(Tokyo)    │   │
│  │ 142.250.x.x   → GEOIP CN         │   │
│  │              → 直连               │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

#### Tab 5: 日志

```
┌─────────────────────────────────────────┐
│  日志                      [清空] [导出]  │
├─────────────────────────────────────────┤
│  [INFO ] 隧道已启动 · 规则模式           │
│  [INFO ] 已加载 12 个节点                │
│  [INFO ] DNS: fake-ip 池已初始化         │
│  [CONN ] google.com:443 → Tokyo-01      │
│  [WARN ] US-West-01 延迟测试超时         │
│  [CONN ] github.com:443 → Singapore-01  │
│  [DNS  ] api.openai.com → 198.18.1.42  │
│  [RULE ] api.openai.com → DOMAIN-SUFFIX │
│  [INFO ] 隧道已停止                     │
└─────────────────────────────────────────┘
```

- 日志级别过滤：ALL / INFO / WARN / ERROR
- 关键词搜索
- 实时滚动，新日志自动到底部

### 4.4 Dock 图标

```
  ┌──────────┐
  │          │
  │   🔷     │  ← 主图标: 圆角方形，内含 "R" 字
  │   R      │     蓝色渐变 (#0fbcf9 → #6c5ce7)
  │          │
  └──────────┘
```

- 未连接：灰色图标 + 无徽章
- 已连接：蓝色图标
- Dock badge 可选显示当前速度 `"5.1M↓"`

### 4.5 AppViewModel 数据模型

```swift
@Observable class AppViewModel {
    // 隧道状态
    var tunnelState: TunnelState  // .stopped / .starting / .running / .stopping
    var proxyMode: ProxyMode      // .rule / .global / .direct
    var connectionMode: ConnectionMode  // .systemProxy / .tun

    // 配置
    var profiles: [Profile]       // 配置文件列表
    var activeProfile: Profile?
    var subscriptions: [Subscription]

    // 代理
    var proxyGroups: [ProxyGroupDisplay]   // 含当前选中节点、延迟
    var allProxies: [ProxyNodeDisplay]

    // 流量
    var currentSpeed: (up: Int64, down: Int64)
    var totalTraffic: (up: Int64, down: Int64)
    var activeConnections: [ConnectionInfo]

    // 规则
    var rules: [ProxyRule]
    var ruleMatches: [RuleMatchLog]

    // 日志
    var logEntries: [LogEntry]
    var logLevel: LogLevel

    // Actions
    func toggleTunnel()
    func switchMode(_ mode: ProxyMode)
    func switchConnectionMode(_ mode: ConnectionMode)
    func selectProxy(groupID: String, nodeName: String)
    func testDelay(groupID: String?)
    func importConfig(url: URL)
    func addSubscription(url: String, name: String)
    func updateSubscription(_ sub: Subscription)
}
```

---

## 5. 实施阶段

### Phase 1：模型与解析基础

| 任务 | 说明 |
|------|------|
| 扩展 `ProxyNode` 模型 | 添加 uuid, flow, sni, alpn, skipCertVerify, network, wsPath, wsHost, grpcServiceName 字段 |
| 扩展 `ClashConfigParser` | 解析 vless / trojan 类型及协议参数；解析 proxy-groups → ProxyGroup；解析 dns section → DNSPolicy |

**验证目标：** `swift run riptide validate --config real-clash-config.yaml` 能正确解析真实 Clash 配置

### Phase 2：传输层

| 任务 | 说明 |
|------|------|
| 修复 `TLSTransport` | skipCertVerify 生效（sec_protocol_options_set_tls_verify_peer）；connection timeout 15s；task cancellation |
| 实现 `WSTransport` | URLSessionWebSocketTask 实现完整 WebSocket（handshake、frame encode/decode、ping/pong、close） |
| ProxyConnector transport 选择 | 根据 node.network 和 TLS 配置选择 transport chain |

**验证目标：** TLS 连接测试通过；WebSocket 握手成功并收发数据

### Phase 3：协议接入

| 任务 | 说明 |
|------|------|
| 修复 VLESSStream | IPv6 编码 bug（ATYP=3 时 16 字节 raw bytes）；addons 改 protobuf；去除 flow 实现（简化为 basic VLESS over TLS） |
| 修复 TrojanStream | SHA-224；outbound payload framing：每帧格式为 `{hex_length}\r\n{data}\r\n`；inbound 解析：读取 hex-length + CRLF，读取对应长度 data，再读尾部 `\r\n`；TLS 强制检查（无 TLS 时 throw `tlsRequired`） |
| ProxyConnector 接入 VLESS + Trojan | performVLESSConnect / performTrojanConnect |
| 集成测试 | `swift run riptide serve` + curl 通过 VLESS/Trojan 代理访问外网 |

**验证目标：** 端到端连接真实 VLESS 和 Trojan 代理服务器

### Phase 4：运行时集成

| 任务 | 说明 |
|------|------|
| ProxyGroupResolver 接入 LiveTunnelRuntime | Select 类型（用户选择持久化）；整合 GroupSelector |
| DNSPipeline 接入 openConnection | 域名解析替换 target.host；保留原始域名用于 SNI |
| Fake-IP 池初始化 | FakeIPPool 启动时分配 198.18.0.0/15；isFakeIP 查询 |
| ProxyConnector transport 链路 | TCP / TLS / WS / WSS 完整链路 |
| 模式切换 | 规则 / 全局 / 直连 |

**验证目标：** 完整 Clash 配置 → 规则匹配 → 分组选择 → DNS 解析 → 代理连接 → 数据传输

### Phase 5：TUN 模式

| 任务 | 说明 |
|------|------|
| 新建 RiptideTunnel Network Extension target | Xcode target + entitlement |
| 实现 PacketTunnelProvider | startTunnel / stopTunnel / handleAppMessage |
| PacketHandler 完善 | 包解析 + writePackets 回写 utun |
| UserSpaceTCP 完善 | SYN/ACK/FIN/RST 状态机；proxy relay 集成 |
| UDP relay | DNS → Fake-IP；其他按规则直连或 proxy |
| VPNTunnelManager | NETunnelProviderManager 配置安装/连接/断开 |
| TunnelProviderBridge | App ↔ Extension App Group 双向通信 |

**验证目标：** 开启 TUN → 系统流量走代理 → Fake-IP DNS → 规则路由 → 端到端

### Phase 6：UI

| 任务 | 说明 |
|------|------|
| AppViewModel | 完整数据层 + Actions |
| 状态栏 NSStatusItem | 连接状态 + 速度 + 快速节点切换 |
| 主窗口 TabView 骨架 | 深色主题 |
| Tab: 配置管理 | 导入/切换配置；订阅管理 |
| Tab: 代理节点 | 分组列表 + 节点选择 + 延迟测试 |
| Tab: 流量统计 | 速率图 + 连接列表 |
| Tab: 规则/路由 | 规则列表 + 实时匹配日志 + 模式切换 |
| Tab: 日志 | 日志查看 + 过滤 + 搜索 |
| Dock 图标 | AppIcon + badge |
| TUN / 系统代理模式切换 | 状态栏 + 主窗口内切换 |

**验证目标：** 用户可通过 UI 完成全部操作：导入配置 → 选择节点 → 开启代理 → 查看流量/日志

### 依赖关系

```
Phase 1 (模型+解析)
  ├→ Phase 2 (传输层)
  │    └→ Phase 3 (协议接入)
  │         └→ Phase 4 (运行时集成) ──┬→ Phase 5 (TUN)
  ├→ Phase 4 (代理组/DNS) ────────────┘        │
  └────────────────────────────────────────────│
                                             Phase 6 (UI)
```

Phase 1 和 Phase 2 可并行开发。Phase 6 UI 骨架可提前开始，数据绑定在 Phase 4 完成后接入。

---

## 6. 不包含范围

以下功能暂不实现，作为后续迭代：

- **VMess 协议**：crypto 层需要完全重写（AES-CFB、正确的 auth ID、header format），工作量独立
- **Hysteria2**：需要 QUIC 实现
- **VLESS XTLS Vision / RPRX Direct**：需要 TLS ClientHello 拦截和 UTLS 指纹模拟
- **gRPC 传输**：需要 gRPC 特定 wire format
- **规则集（RuleSet）**：Clash Meta 的远程规则集扩展
- **MITM / Script 引擎**：动态规则脚本
- **多语言国际化**：先只做英文/中文

---

## 7. 风险与缓解

| 风险 | 缓解 |
|------|------|
| Network Extension entitlement 申请可能被拒 | 明确告知用户需要手动到系统设置授权；提供详细引导 |
| WebSocket 实现遇到 Apple 平台限制 | URLSessionWebSocketTask 跨平台兼容性好，优先使用 |
| VLESS protobuf 编码不兼容特定服务端 | 先支持 basic VLESS（无 flow），后续按需扩展 |
| 订阅更新需要处理各种编码格式 | 先支持 plain + base64，gzip 后续迭代 |
