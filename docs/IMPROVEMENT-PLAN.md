# Riptide 改进计划 — 对标 Clash Verge Rev

> 最后更新：2026-04-04
> 目标：将 Riptide 从当前原型状态推进为 **功能完整、可真实日常使用** 的 macOS 原生代理客户端，核心能力对齐 Clash Verge Rev。

---

## 目录

1. [现状总览](#1-现状总览)
2. [差距分级](#2-差距分级)
3. [改进路线图](#3-改进路线图)
4. [详细任务分解](#4-详细任务分解)
   - [P0 — 核心可用](#p0--核心可用)
   - [P1 — 功能补齐](#p1--功能补齐)
   - [P2 — 体验提升](#p2--体验提升)
   - [P3 — 高级能力](#p3--高级能力)
5. [验收标准](#5-验收标准)
6. [风险与约束](#6-风险与约束)

---

## 1. 现状总览

### 1.1 已实现（可直接使用）

| 领域 | 已实现内容 |
|------|-----------|
| **代理协议** | HTTP CONNECT、SOCKS5、Shadowsocks (AEAD)、VMess (AEAD)、VLESS、Trojan、Hysteria2 (基础 TCP)、Relay Chain |
| **传输层** | TCP、TLS、WebSocket、HTTP/2 (ALPN)、Multiplex、连接池 |
| **规则引擎** | DOMAIN / DOMAIN-SUFFIX / DOMAIN-KEYWORD / IP-CIDR / IP-CIDR6 / SRC-IP-CIDR / SRC-PORT / DST-PORT / PROCESS-NAME / GEOIP(接口) / RULE-SET(远程自动更新) / SCRIPT(表达式) / MATCH / FINAL |
| **DNS** | UDP / TCP / DoH / DoT 完整编解码、Fake-IP 池、Hosts 映射、TTL 缓存、DNS 分流策略 |
| **连接编排** | `LiveTunnelRuntime` 完整生命周期、`ProxyConnector` 协议握手、`TransportConnectionPool` 池化复用 |
| **本地代理** | `LocalHTTPConnectProxyServer` (127.0.0.1:6152) HTTP CONNECT 监听、域名嗅探、双向流量中继 |
| **外部控制器** | REST API (9090) + WebSocket 控制器、版本/代理/规则/连接/流量/日志端点 |
| **节点编辑** | `EditableProxyNode` + `ProxyNodeValidator` + SwiftUI `NodeEditorView` 全 CRUD |
| **订阅管理** | `SubscriptionManager` CRUD、`ProxyURIParser` (ss/vmess/vless/trojan URI)、`SubscriptionUpdateScheduler` 定时更新 |
| **代理组** | Select / URL-Test / Fallback / Load-Balance (rr + consistent-hashing) + `ProxyGroupManager` + `GroupSelector` 健康感知 |
| **健康检查** | `HealthChecker` HTTP 延迟测量、周期检查 |
| **代理提供者** | `ProxyProvider` 远程/本地 provider 下载解析、自动刷新 |
| **Mihomo 集成** | `MihomoRuntimeManager` XPC 生命周期、`MihomoAPIClient` API 调用、`MihomoConfigGenerator` 配置生成 |
| **日志** | `LogTypes` 编解码、`LogViewModel` + `LogStreamView` 实时日志流 |
| **流量** | `TrafficViewModel` 60 点历史、速率计算、`TrafficChartView` 可视化 |
| **TUN 骨架** | `TUNRoutingEngine` IP 包解析、TCP 状态机、UDP 会话管理、DNS 拦截响应、`PacketHandler` 包头编校 |
| **CLI** | `validate` / `run` / `smoke` / `serve` 四命令 |

### 1.2 空壳/未完成（代码存在但无实质功能）

| 组件 | 当前状态 | 问题 |
|------|---------|------|
| `TUNRoutingEngine.forwardTCPData` | **空函数** | TCP 数据无法通过代理转发，TUN 模式无法实际工作 |
| `SystemProxyController` | **仅协议定义** | 无 `scutil` / NetworkExtension 平台实现，系统代理无法开启 |
| `GeoIPResolver` | **注入点存在，无实现** | `.none` 默认返回 nil，GEOIP 规则永远不匹配 |
| `IP-ASN` 规则 | **空返回 policy** | 无 ASN 数据库，规则退化为直通 |
| `GEO-SITE` 规则 | **空返回 policy** | 无 GeoSite 数据库，规则退化为直通 |
| `DOQResolver` | **直接抛异常** | DNS-over-QUIC 不可用 |
| `ScriptEngine` execute 方法 | **返回原输入** | 请求/响应修改脚本不生效 |
| `NodeEditorViewModel` YAML 操作 | **返回未修改 YAML** | 节点删除/更新无法写回文件 |
| `AppViewModel.addSubscription` | **设错误信息** | 提示 "Subscriptions not yet implemented" |
| `TUNRoutingEngine.getStats` | **返回硬编码 0** | 统计数据不准确 |
| `HealthChecker.check()` | **直连 HEAD 请求** | 不经过代理，测活对需要代理的节点无效 |
| Hysteria2 | **仅 TCP 握手** | 无 QUIC/UDP 转发，实际不可用 |

---

## 2. 差距分级

### 🔴 P0 — 核心可用（没有则产品不可用）

| # | 差距 | 影响 |
|---|------|------|
| P0-1 | **系统代理实际实现** | 无法开启系统代理，用户必须手动配置浏览器代理 |
| P0-2 | **TUN 模式 TCP 数据转发** | TUN 模式下所有 TCP 流量被丢弃，完全不可用 |
| P0-3 | **UDP 隧道/通用 UDP 转发** | QUIC 游戏、HTTP/3、DNS-over-UDP 全部失败 |
| P0-4 | **GeoIP 数据库** | GEOIP 规则失效，国内/国外分流无法工作 |

### 🟡 P1 — 功能补齐（没有则体验明显落后）

| # | 差距 | 影响 |
|---|------|------|
| P1-1 | **缺失代理协议**：TUIC、WireGuard、Snell、SSR、SSH | 使用这些协议的用户无法迁移 |
| P1-2 | **Hysteria2 QUIC 完整实现** | Hysteria2 节点实际不可用 |
| P1-3 | **GEO-SITE / IP-ASN 实际实现** | 高级规则集失效 |
| P1-4 | **配置 Merge / 增强脚本** | 无法覆盖复杂订阅场景 |
| P1-5 | **NOT / REJECT 规则** | 无法显式拒绝特定流量 |
| P1-6 | **DNS-over-QUIC** | 部分 DoQ -only 服务器无法使用 |
| P1-7 | **订阅使用量显示 / WebDav 备份** | 订阅管理不完整 |

### 🟢 P2 — 体验提升（锦上添花）

| # | 差距 | 影响 |
|---|------|------|
| P2-1 | 热键/快捷键 | 效率型用户需要 |
| P2-2 | IP 查看器 | 快速验证出口 IP |
| P2-3 | 拖拽导入配置 | 体验优化 |
| P2-4 | 主题/CSS 自定义 | 个性化需求 |
| P2-5 | 多语言国际化 | 非中文用户 |
| P2-6 | 配置语法高亮 | 编辑器体验 |

### 🔵 P3 — 高级能力（长期演进）

| # | 差距 | 影响 |
|---|------|------|
| P3-1 | MITM 中间人 | HTTPS 内容修改场景 |
| P3-2 | 脚本引擎完整化 | 动态路由/修改请求 |
| P3-3 | Mixed Port 统一监听 | 多协议合一端口 |
| P3-4 | gRPC 传输独立实现 | 当前回退到 TLS |

---

## 3. 改进路线图

```
┌─────────────────────────────────────────────────────────────────┐
│  Phase 1: 核心可用 (P0)                                         │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐            │
│  │ 系统代理实现  │ │ TUN TCP转发  │ │ UDP 隧道     │            │
│  │ scutil/NWPath │ │ 连接目标注册  │ │ QUIC/UDP     │            │
│  │ 守护进程      │ │ 代理链打通    │ │ 转发         │            │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘            │
│         └────────────────┼────────────────┘                     │
│                          ▼                                      │
│              ┌───────────────────────┐                          │
│              │  GeoIP 数据库集成      │                          │
│              │  MMDB 加载 + 查询      │                          │
│              └───────────┬───────────┘                          │
├──────────────────────────┼──────────────────────────────────────┤
│  Phase 2: 功能补齐 (P1)  │                                      │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐            │
│  │ 新协议: TUIC │ │ Hysteria2    │ │ GEO-SITE/    │            │
│  │ WireGuard/   │ │ QUIC 完整    │ │ IP-ASN       │            │
│  │ Snell/SSR    │ │ 实现         │ │ 数据库       │            │
│  └──────────────┘ └──────────────┘ └──────────────┘            │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐            │
│  │ 配置 Merge   │ │ NOT/REJECT   │ │ DoQ 实现     │            │
│  │ 增强脚本     │ │ 规则         │ │ (或标记降级)  │            │
│  └──────────────┘ └──────────────┘ └──────────────┘            │
├──────────────────────────┼──────────────────────────────────────┤
│  Phase 3: 体验提升 (P2)  │                                      │
│  热键 · IP 查看器 · 拖拽导入 · 主题 · i18n · 语法高亮            │
├──────────────────────────┼──────────────────────────────────────┤
│  Phase 4: 高级能力 (P3)  │                                      │
│  MITM · 完整 ScriptEngine · Mixed Port · gRPC 独立传输           │
└──────────────────────────┼──────────────────────────────────────┘
```

---

## 4. 详细任务分解

### P0 — 核心可用

---

#### P0-1: 系统代理实际实现

**当前状态**: `SystemProxyControlling` 协议存在，仅有 `MockSystemProxyController` 和 `FailingSystemProxyController` 测试替身。

**技术方案**:
```
方案 A: scutil (推荐，macOS 原生)
  - 使用 scutil 读写 System 配置
  - 设置 HTTPProxy / HTTPSEnable / SOCKSEnable / SOCKSProxy 等
  - 监听 SCDynamicStore 事件实现状态监控
  - 优点: 简单直接
  - 缺点: 需要权限，仅影响 System Configuration，不覆盖 PAC

方案 B: Network Extension (长期)
  - 使用 NEProxyManager 管理代理设置
  - 更现代的 API，支持更多场景
  - 需要 entitlement 配置

方案 C: 特权 Helper Tool (当前已有 XPC 骨架)
  - 通过 SMJobBless 安装的 helper 执行 scutil 操作
  - 当前 `MihomoRuntimeManager` 已使用此模式
  - 推荐沿用
```

**建议**: 方案 C — 复用现有 XPC helper 通道，在 helper 中执行 `scutil` 命令。

**需要修改/新增的文件**:
```
Sources/Riptide/AppShell/SystemProxyController.swift  (新增 macOS 实现)
Sources/Riptide/XPC/HelperToolProtocol.swift           (扩展协议)
Sources/Riptide/XPC/HelperToolConnection.swift         (扩展方法)
```

**实现要点**:
```swift
// SystemProxyController (macOS 实现)
final class macOSSystemProxyController: SystemProxyControlling, @unchecked Sendable {
    private let helperConnection: HelperToolConnection
    
    func enable(httpPort: Int, socksPort: Int?) throws {
        // 通过 XPC 调用 helper 执行:
        // scutil --keys > /dev/null 2>&1
        // 设置 HTTPProxy, HTTPPort, HTTPSEnable, HTTPSPort
        // 可选设置 SOCKSProxy, SOCKSPort
    }
    
    func disable() throws {
        // 清除所有代理设置
    }
    
    func currentState() throws -> SystemProxyState {
        // 读取 scutil 配置返回当前状态
    }
}
```

**scutil 命令参考**:
```bash
# 读取当前代理配置
scutil --proxy

# 设置 HTTP 代理 (需在 helper 中以 root 执行)
networksetup -setwebproxy Wi-Fi 127.0.0.1 6152 off
networksetup -setsecurewebproxy Wi-Fi 127.0.0.1 6152 off
networksetup -setsocksfirewallproxy Wi-Fi 127.0.0.1 6153 off

# 关闭代理
networksetup -setwebproxystate Wi-Fi off
networksetup -setsecurewebproxystate Wi-Fi off
networksetup -setsocksfirewallproxystate Wi-Fi off
```

**验收标准**:
- [ ] `AppViewModel.startTunnel()` 调用后，`scutil --proxy` 显示代理已启用
- [ ] Safari/Chrome 等浏览器流量走代理
- [ ] `AppViewModel.stopTunnel()` 后代理自动清除
- [ ] 系统代理 Guard 每 5 秒检测，被外部修改时自动恢复

---

#### P0-2: TUN 模式 TCP 数据转发

**当前状态**: `TUNRoutingEngine.forwardTCPData(connectionID:data:)` 是空函数。TCP 三次握手能完成，但应用层数据不转发。

**技术方案**:
```
需要解决的问题:
1. 连接目标注册: 每个 TCP 连接需要知道目标地址和期望的代理节点
2. 数据流对接: 将 TUN 中的 TCP payload 通过 ProxyConnector 发送
3. 响应回传: 代理返回的数据通过 TCP 状态机打包回 TUN

架构设计:
┌─────────────┐     IP Packets      ┌──────────────────┐
│   TUN iface  │ ◄─────────────────► │  TUNRoutingEngine│
└─────────────┘                     └────────┬─────────┘
                                             │
                        ┌────────────────────┼────────────────────┐
                        ▼                    ▼                    ▼
                 ┌────────────┐     ┌─────────────┐     ┌──────────────┐
                 │ TCP State  │     │  UDP Session│     │ DNS Pipeline │
                 │  Machine   │     │  Manager    │     │              │
                 └─────┬──────┘     └─────────────┘     └──────────────┘
                       │
                       ▼
              ┌────────────────┐
              │ Connection     │  ← 新增: 连接目标注册表
              │ Target Registry│
              └───────┬────────┘
                      │ lookup(connectionID) → ConnectionTarget
                      ▼
              ┌────────────────┐
              │ ProxyConnector │
              │ .connect(via:) │
              └───────┬────────┘
                      │
                      ▼
              代理服务器 (SS/VMess/Trojan...)
```

**需要修改/新增的文件**:
```
Sources/Riptide/VPN/TUNRoutingEngine.swift           (实现 forwardTCPData)
Sources/Riptide/VPN/TCPConnectionRegistry.swift      (新增: 连接目标注册表)
Sources/Riptide/VPN/TCPTunnelForwarder.swift         (新增: TCP 隧道转发器)
```

**实现要点**:
```swift
// TCPConnectionRegistry — 注册每个连接的目标
actor TCPConnectionRegistry {
    private var targets: [TCPConnectionID: ConnectionTarget] = [:]
    
    func register(id: TCPConnectionID, target: ConnectionTarget) {
        targets[id] = target
    }
    
    func lookup(id: TCPConnectionID) -> ConnectionTarget? {
        targets[id]
    }
    
    func remove(id: TCPConnectionID) {
        targets.removeValue(forKey: id)
    }
}

// TCPTunnelForwarder — 单个 TCP 连接的代理转发
actor TCPTunnelForwarder {
    private let connectionID: TCPConnectionID
    private let target: ConnectionTarget
    private let proxyConnector: ProxyConnector
    private let tcpStateMachine: TCPStateMachine
    private let responseQueue: AsyncStream<Data>.Continuation?
    
    func start() async {
        // 1. 通过 ProxyConnector 连接到目标
        // 2. 启动双向数据流中继:
        //    TUN → TCP State Machine → Proxy Session → Remote
        //    Remote → Proxy Session → TCP State Machine → TUN
        // 3. 连接关闭时清理
    }
    
    func sendData(_ data: Data) async throws {
        // 通过已建立的代理连接发送数据
    }
    
    func close() async {
        // 关闭代理连接，清理注册表
    }
}

// TUNRoutingEngine.forwardTCPData 实现
private func forwardTCPData(connectionID: TCPConnectionID, data: Data) async throws {
    // 1. 查找连接目标
    guard let target = await connectionRegistry.lookup(id: connectionID) else {
        // 首次数据: 需要建立代理连接
        // 从 TCP 状态机获取目标 IP:Port
        // 通过 LiveTunnelRuntime.openConnection 建立代理连接
        // 注册到 registry
        // 启动 forwarder
        return
    }
    
    // 2. 通过已建立的 forwarder 发送数据
    if let forwarder = forwarders[connectionID] {
        try await forwarder.sendData(data)
    }
}
```

**验收标准**:
- [ ] TUN 模式下浏览器可以正常访问网页
- [ ] `curl` 等 CLI 工具流量走代理
- [ ] 连接关闭时资源正确释放
- [ ] TCP 状态机在异常情况下正确回退

---

#### P0-3: UDP 隧道/通用 UDP 转发

**当前状态**: `UDPSessionManager` 存在但 `routePacket` 仅做基础会话管理，无实际代理转发。DNS (port 53) 通过 `DNSPipeline` 处理，但其他 UDP 流量无转发。

**技术方案**:
```
UDP vs TCP 差异:
- UDP 无连接，每个 datagram 独立
- 需要 session 级别的多路复用
- 部分协议 (QUIC/H2/HTTP3) 对 UDP 有强依赖

实现策略:
1. 通用 UDP-over-proxy 框架
2. 优先支持 SOCKS5 UDP Associate
3. 逐步支持各协议的 UDP 变体
```

**需要修改/新增的文件**:
```
Sources/Riptide/VPN/UDPSessionManager.swift          (增强: 代理转发)
Sources/Riptide/Protocols/UDPRelayProtocol.swift     (新增: UDP 代理协议抽象)
Sources/Riptide/Transport/UDPTransportSession.swift  (新增: UDP 传输会话)
Sources/Riptide/Protocols/SOCKS5Protocol.swift       (扩展: UDP Associate)
```

**实现要点**:
```swift
// UDPSessionManager 增强
actor UDPSessionManager {
    private var sessions: [UDPSessionID: UDPTunnelSession] = [:]
    
    func routePacket(
        sessionID: UDPSessionID,
        data: Data,
        proxyConnector: ProxyConnector
    ) async throws -> [Data] {
        // 获取或创建 UDP 隧道会话
        let session: UDPTunnelSession
        if let existing = sessions[sessionID] {
            session = existing
        } else {
            // 建立 UDP 代理隧道
            session = try await UDPTunnelSession(
                sessionID: sessionID,
                target: ConnectionTarget(host: sessionID.dstIP, port: sessionID.dstPort),
                proxyConnector: proxyConnector
            )
            sessions[sessionID] = session
        }
        
        // 转发数据
        let response = try await session.forward(data)
        return [response]
    }
}

// UDPTunnelSession — 单个 UDP 会话
actor UDPTunnelSession {
    private let sessionID: UDPSessionID
    private var proxyConnection: (any TransportSession)?
    
    func forward(_ data: Data) async throws -> Data {
        // 1. 如果没有连接，建立 SOCKS5 UDP Associate
        // 2. 封装数据为 SOCKS5 UDP 格式
        // 3. 通过代理连接发送
        // 4. 接收响应，解封装
        // 5. 返回原始 UDP payload
    }
}
```

**验收标准**:
- [ ] `nslookup` 通过 UDP 53 正常解析 (已有 DNS 拦截)
- [ ] QUIC 协议节点可以建立连接
- [ ] UDP 游戏流量可以正常转发
- [ ] 长时间无活动的 UDP 会话自动超时清理

---

#### P0-4: GeoIP 数据库集成

**当前状态**: `GeoIPResolver` 是注入点，默认 `.none` 返回 nil。

**技术方案**:
```
方案 A: MaxMind GeoLite2 Country MMDB (推荐)
  - 开源免费，需注册账号下载
  - 纯二进制查询，性能优秀
  - 需要 MMDB 解析库

方案 B: 内置精简版 country-coder
  - 将 IP 段 → 国家码映射内置为 Swift 代码
  - 体积较大，更新不便
  - 优点: 无外部依赖

方案 C: 在线 API (不推荐)
  - 每次查询延迟高
  - 依赖网络，不适合本地代理场景
```

**建议**: 方案 A — 集成 `MMDB` 解析。

**需要修改/新增的文件**:
```
Sources/Riptide/Rules/GeoIPResolver.swift            (扩展: MMDB 加载)
Sources/Riptide/Rules/GeoIPDatabase.swift            (新增: MMDB 解析器)
Resources/geoip.mmdb                                 (数据文件, 不入库)
```

**实现要点**:
```swift
// GeoIPDatabase — MMDB 解析 (简化实现，无外部依赖)
final class GeoIPDatabase: Sendable {
    private let data: Data
    private let metadata: MMDBMetadata
    
    static func load(from path: String) throws -> GeoIPDatabase {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try GeoIPDatabase(data: data)
    }
    
    func lookupCountryCode(forIP ip: String) -> String? {
        // 解析 MMDB 二叉搜索树
        // 返回 2 字母国家码 (CN, US, JP...)
    }
}

// 更新 GeoIPResolver
public struct GeoIPResolver: Sendable {
    public let resolveCountryCode: @Sendable (String) -> String?
    
    public init(database: GeoIPDatabase) {
        self.resolveCountryCode = { ip in
            database.lookupCountryCode(forIP: ip)
        }
    }
    
    public static let none = GeoIPResolver { _ in nil }
}
```

**验收标准**:
- [ ] 加载 GeoLite2-Country.mmdb 成功
- [ ] `GeoIPResolver.resolveCountryCode("8.8.8.8")` 返回 "US"
- [ ] GEOIP 规则在 `RuleEngine` 中正确匹配
- [ ] 数据库更新时自动重新加载

---

### P1 — 功能补齐

---

#### P1-1: 缺失代理协议实现

| 协议 | 优先级 | 复杂度 | 说明 |
|------|:------:|:------:|------|
| **TUIC v5** | 高 | 中 | 基于 QUIC 的协议，需 Network.framework QUIC 支持 |
| **WireGuard** | 高 | 高 | 本身就是 VPN 协议，与 TUN 有交互 |
| **Snell** | 中 | 低 | 简单的加密协议，适合快速实现 |
| **SSR (ShadowsocksR)** | 中 | 中 | 需要混淆和协议插件支持 |
| **SSH** | 低 | 中 | 使用 SSH tunnel 转发流量 |

**Snell 实现** (最快上手):
```
Sources/Riptide/Protocols/Snell/SnellProtocol.swift
Sources/Riptide/Protocols/Snell/SnellStream.swift
```

**TUIC 实现**:
```
Sources/Riptide/Protocols/TUIC/TUICProtocol.swift
Sources/Riptide/Protocols/TUIC/TUICStream.swift
// 依赖: Network.framework NWProtocolQUIC
```

**WireGuard 实现**:
```
Sources/Riptide/VPN/WireGuardTunnel.swift
// WireGuard 比较特殊，它本身就是一个 TUN 隧道
// 需要与现有 TUNRoutingEngine 协调
```

**验收标准**:
- [ ] 每种协议可以成功连接到测试服务器
- [ ] 可以解析 Clash YAML 中对应类型的代理配置
- [ ] `ProxyConnector` 正确路由到对应协议处理

---

#### P1-2: Hysteria2 QUIC 完整实现

**当前状态**: `Hysteria2Stream` 仅实现了 TCP 握手框架。

**需要补充**:
```
Sources/Riptide/Protocols/Hysteria2/Hysteria2Stream.swift  (重构: QUIC 传输)
Sources/Riptide/Transport/QUICTransport.swift              (新增: QUIC 传输层)
```

**实现要点**:
- Hysteria2 基于 QUIC，需要使用 `NWProtocolQUIC`
- 实现 HMAC-SHA256 认证令牌交换
- 支持 UDP 流量转发 (Hysteria2 的核心能力)
- 实现拥塞控制 (BBR)

**验收标准**:
- [ ] Hysteria2 节点可以连接并传输数据
- [ ] UDP 流量通过 QUIC 正确转发

---

#### P1-3: GEO-SITE / IP-ASN 实际实现

**技术方案**:
```
GEO-SITE:
  - 需要 GeoSite 数据库 (dat 格式或 mmdb 格式)
  - 域名 → 站点分类 → 策略
  - 格式: category:code (如 "geosite:cn")

IP-ASN:
  - 需要 ASN 数据库 (IP 段 → ASN 号)
  - 可使用 MaxMind 或自建 IP2ASN 数据
  - 格式: "ip-asn:13335" (Cloudflare)
```

**需要修改的文件**:
```
Sources/Riptide/Rules/GeoSiteResolver.swift    (新增)
Sources/Riptide/Rules/ASNResolver.swift        (新增)
Sources/Riptide/Rules/RuleEngine.swift         (修改: 使用真实解析器)
```

**验收标准**:
- [ ] GEO-SITE 规则可以匹配域名分类
- [ ] IP-ASN 规则可以匹配 IP 所属 ASN
- [ ] 不再空返回 policy

---

#### P1-4: 配置 Merge / 增强脚本

**Merge 功能**:
```
配置合并允许用户在一个独立的 YAML 文件中覆盖/追加主配置:
- 覆盖 DNS 设置
- 追加自定义规则
- 修改代理组策略

实现:
Sources/Riptide/Config/ConfigMerger.swift     (新增)
```

**增强脚本**:
```
JavaScript 脚本，在配置加载时执行:
- 动态修改代理节点
- 添加自定义规则
- 修改 DNS 策略

实现:
Sources/Riptide/Scripting/ScriptEngine.swift  (完善 execute 方法)
```

**验收标准**:
- [ ] Merge 文件可以正确合并到主配置
- [ ] 增强脚本可以修改配置内容
- [ ] 合并/脚本错误有明确提示

---

#### P1-5: NOT / REJECT 规则

**需要修改**:
```
Sources/Riptide/Models/ProxyModels.swift
  - ProxyRule 添加:
    case not(rule: ProxyRule)          // 取反
    case reject                         // 拒绝连接

Sources/Riptide/Rules/RuleEngine.swift
  - matchedPolicy 处理 .not → 取反结果
  - .reject 抛 LiveTunnelRuntimeError.rejectPolicy
```

**验收标准**:
- [ ] `NOT,DOMAIN,google.com,DIRECT` 正确对非 google.com 的域名应用 DIRECT
- [ ] `REJECT` 规则正确拒绝连接并返回错误

---

#### P1-6: DNS-over-QUIC

**当前状态**: `DOQResolver.query()` 直接抛异常。

**方案**:
- `NWProtocolQUIC` 在 macOS 14+ 可用
- 需要配置 QUIC 参数 (ALPN = "dq")
- RFC 9250 规定 DoQ 使用 QUIC STREAM 传输 DNS 消息

**验收标准**:
- [ ] DoQ 服务器可以正常解析 DNS
- [ ] QUIC 不可用时优雅降级到 DoT/DoH

---

#### P1-7: 订阅使用量 / WebDav 备份

**订阅使用量**:
```
部分订阅服务商在订阅响应头中返回使用量信息:
- Subscription-Userinfo: upload=0; download=1073741824; total=1073741824; expire=1714694400

实现:
Sources/Riptide/Subscription/SubscriptionManager.swift
  - 解析响应头，存储到 Subscription 模型
  - UI 显示使用量百分比和到期时间
```

**WebDav 备份**:
```
实现:
Sources/Riptide/Backup/WebDavBackup.swift    (新增)
  - 上传 profiles.yaml 到 WebDav
  - 下载并恢复配置
  - 定时同步
```

**验收标准**:
- [ ] 订阅列表显示使用量和到期时间
- [ ] 可以通过 WebDav 备份和恢复配置

---

### P2 — 体验提升

| 任务 | 预计工作量 | 说明 |
|------|:---------:|------|
| P2-1 热键/快捷键 | 低 | `Carbon`/`KeyboardShortcuts` 注册全局快捷键 |
| P2-2 IP 查看器 | 低 | 调用外部 API 或 mihomo API 获取出口 IP |
| P2-3 拖拽导入 | 低 | SwiftUI `onDrop` 处理 YAML 文件 |
| P2-4 主题系统 | 中 | `Theme` 已存在骨架，补充颜色/字体配置 |
| P2-5 国际化 | 中 | `Localizable.xcstrings` + `NSLocalizedString` |
| P2-6 语法高亮 | 中 | 集成 `TextKit` 或 `Highlighter` 库 |

---

### P3 — 高级能力

| 任务 | 说明 |
|------|------|
| P3-1 MITM | `MITMManager` 和 `CertificateAuthority` 骨架已存在，需实现 TLS 拦截和证书生成 |
| P3-2 ScriptEngine | `ScriptEngine` 加载 JS 成功，但 execute 方法是空壳，需实现 JSContext 注入和调用 |
| P3-3 Mixed Port | 统一监听端口，自动检测协议 (类似 mihomo mixed-port) |
| P3-4 gRPC 传输 | 当前 `DialerSelector` 将 gRPC 回退到 TLS，需独立实现 |

---

## 5. 验收标准

### Phase 1 (P0) 完成标准

| 项目 | 验收方法 |
|------|---------|
| 系统代理 | `scutil --proxy` 显示已启用，Safari 走代理 |
| TUN TCP | `curl http://httpbin.org/ip` 返回代理出口 IP |
| UDP 隧道 | `nslookup` 通过 UDP 53 正常解析 |
| GeoIP | `GEOIP,CN,DIRECT` 对中国 IP 生效 |

### Phase 2 (P1) 完成标准

| 项目 | 验收方法 |
|------|---------|
| 新协议 | TUIC/WireGuard/Snell 各能连接一个测试节点 |
| Hysteria2 | 实际可用，不只是骨架 |
| GEO-SITE | `GEOSITE,cn,DIRECT` 对中国域名生效 |
| 配置 Merge | Merge 文件导入后配置正确覆盖 |
| NOT/REJECT | `NOT,DOMAIN,google.com,DIRECT` 和 `REJECT` 正常工作 |

### Phase 3 (P2) 完成标准

| 项目 | 验收方法 |
|------|---------|
| 热键 | 全局快捷键可以切换代理模式 |
| IP 查看器 | 一键查看当前出口 IP |
| 国际化 | 至少支持中英双语 |

---

## 6. 风险与约束

| 风险 | 说明 | 缓解措施 |
|------|------|---------|
| **NWProtocolQUIC 可用性** | macOS 14+ 才支持 QUIC API | 降级到 TCP 传输，明确标注最低系统版本 |
| **GeoIP 数据库授权** | GeoLite2 需注册 MaxMind 账号 | 提供开源替代方案 (如 ip2location lite) |
| **WireGuard 复杂度** | WireGuard 是完整 VPN 协议 | 考虑使用用户态实现 (如 wireguard-go Swift 移植) |
| **XPC Helper 权限** | SMJobBless 需要代码签名和 entitlement | 开发阶段先用 `AuthorizationExecuteWithPrivileges` 替代 |
| **Swift 6 严格并发** | 大量 `Sendable` 约束需要遵守 | 每步编译验证，避免积累编译错误 |
| **测试覆盖** | 网络相关代码难写单元测试 | 使用 Mock/Stub + 集成测试补充 |

---

## 附录 A: 文件变更清单 (P0 阶段)

| 文件 | 操作 | 说明 |
|------|------|------|
| `SystemProxyController.swift` | 修改 | 添加 macOS 实现类 |
| `HelperToolProtocol.swift` | 修改 | 扩展代理控制方法 |
| `TUNRoutingEngine.swift` | 修改 | 实现 forwardTCPData |
| `TCPConnectionRegistry.swift` | 新增 | 连接目标注册表 |
| `TCPTunnelForwarder.swift` | 新增 | TCP 隧道转发器 |
| `UDPSessionManager.swift` | 修改 | 增强 UDP 代理转发 |
| `UDPTunnelSession.swift` | 新增 | UDP 隧道会话 |
| `SOCKS5Protocol.swift` | 修改 | 添加 UDP Associate |
| `GeoIPDatabase.swift` | 新增 | MMDB 解析器 |
| `GeoIPResolver.swift` | 修改 | 支持数据库加载 |

## 附录 B: 与现有 ROADMAP.md 的关系

本计划是对现有 `ROADMAP.md` 的 **补充和细化**。区别在于：

1. **ROADMAP.md** 侧重 Phase 1-3 的功能闭环（延迟测试、订阅、TUN 稳定化）
2. **本计划** 从对标 Clash Verge Rev 的角度，给出了 **完整差距分析和分阶段追赶路径**
3. 本计划中的 P0 任务 **覆盖并扩展** 了 ROADMAP.md 中 Phase 1 的内容
4. ROADMAP.md 中未提及的 GeoIP、UDP 隧道、协议补齐等 **在本计划中补充**

建议将本计划合并到 `ROADMAP.md` 或作为 `docs/GAP-ANALYSIS.md` 独立存在。
