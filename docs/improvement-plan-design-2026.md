# Riptide 改进方案设计规范

> 版本: 1.0
> 日期: 2026-04-06
> 状态: 已批准，待实施

## 1. 背景与目标

Riptide 当前使用 mihomo 作为单一代理内核，在协议支持、流量管理和安全伪装能力上与主流代理客户端（Surge、Clash Verge Rev、Hiddify、sing-box）存在差距。本规范制定三阶段改进方案，消除核心能力差距并建立长期技术优势。

## 2. 架构决策

### 2.1 双内核架构

引入 sing-box 作为第二代理内核，mihomo 保留用于已有协议支持。

**路由规则：**

| 协议 | 内核 | 原因 |
|------|------|------|
| Shadowsocks / VMess / VLESS (非 Reality) / Trojan / Hysteria2 / TUIC | mihomo | 已有稳定实现 |
| **VLESS + Reality** | sing-box | mihomo 稳定版不支持 |
| **WireGuard** | sing-box | mihomo 不支持 |
| **ShadowTLS** | sing-box | sing-box 独有 |
| **NaiveProxy** | sing-box | sing-box 独有 |
| **Tor** | sing-box | sing-box 独有 |
| **ECH** | sing-box | sing-box 独有 |

### 2.2 统一抽象层

引入 `ProxyEngine` 协议抽象两种内核的差异：

```swift
public protocol ProxyEngine: Sendable {
    var name: String { get }
    var supportedKinds: Set<ProxyKind> { get }
    func generateConfig(from proxy: ProxyNode) throws -> Data
    func measureDelay(for proxy: ProxyNode) async throws -> Int?
}
```

两种引擎实现：
- `MihomoEngine: ProxyEngine` — 封装现有 MihomoConfigGenerator，输出 Clash YAML
- `SingboxEngine: ProxyEngine` — 生成 sing-box JSON 配置

**引擎选择逻辑：** 根据 `ProxyKind` 自动路由，用户无感知。

### 2.3 进程管理

两种内核均作为外部进程运行，通过 XPC/SMJobBless 管理（与现有 mihomo 架构一致）。Go 库路线因复杂度过高被否决。

```
┌──────────────────────────────────────────┐
│          Riptide (SwiftUI App)              │
│  ┌────────────────────────────────────┐   │
│  │   ProxyEngine (Protocol)            │   │
│  │  ┌─────────────┐ ┌──────────────┐  │   │
│  │  │MihomoEngine │ │SingboxEngine │  │   │
│  │  └──────┬──────┘ └──────┬───────┘  │   │
│  └─────────┼───────────────┼──────────┘   │
└────────────┼───────────────┼───────────────┘
             │               │
      XPC / REST API   XPC / REST API
             │               │
    ┌────────▼───┐   ┌──────▼────────┐
    │  mihomo    │   │   sing-box    │
    │  (root)    │   │   (root)      │
    └────────────┘   └───────────────┘
```

## 3. Phase 1 — 核心补全

### 3.1 目标

消除 P0（核心）和 P1（高优先）功能差距。

### 3.2 ProxyNode 模型扩展

新增字段：

```swift
public struct ProxyNode: Equatable, Sendable {
    // 新增: TLS 指纹
    public let tlsFingerprint: String?  // "chrome", "firefox", "safari", "ios", "android", "randomized"

    // 新增: UDP over TCP
    public let udpOverTcp: Bool?

    // 新增: 协议嗅探
    public let sniff: Bool?
    public let sniOverride: String?

    // 新增: Reality 专用
    public let publicKey: String?       // X25519 公钥
    public let shortId: String?         // 短 ID
    public let realityFingerprint: String?  // 目标 TLS 指纹
    public let realityServerName: String?   // 伪装目标域名
}
```

新增 `ProxyKind` 枚举值：`reality`。

### 3.3 Reality 协议

- **URL 导入为主**：扩展 URI 解析器支持 `vless+reality://` 格式
- **手动编辑为辅**：节点编辑器提供 Reality 专用表单
- Reality 不与其他协议共用表单，需独立设计

### 3.4 TLS 指纹

- 值域：`chrome`, `firefox`, `safari`, `ios`, `android`, `randomized`
- mihomo 输出：`fingerprint: chrome`
- sing-box 输出：`tls.fingerprint: chrome`
- UI：节点编辑器 TLS 设置区块中的下拉选择器

### 3.5 UDP over TCP

- `ProxyNode.udpOverTcp` 布尔字段
- mihomo 输出：`udp-over-tcp: true`
- sing-box 输出：`udp-over-tcp: true`

### 3.6 Multiplex

新增全局配置结构：

```swift
public struct MultiplexConfig: Sendable {
    public let enabled: Bool
    public let maxConnections: Int?    // default: 8
    public let minInterval: String?   // "5s"
}
```

- UI：设置面板新增"连接复用"区块
- mihomo 和 sing-box 均输出对应配置块

### 3.7 协议嗅探

- `ProxyNode.sniff: Bool`
- `ProxyNode.sniOverride: String?`
- UI：节点高级设置中的"协议嗅探"开关

### 3.8 sing-box 基础集成

新增 `Sources/Riptide/SingBox/` 模块：

| 文件 | 职责 |
|------|------|
| `SingBoxConfigGenerator.swift` | sing-box JSON 配置生成 |
| `SingBoxRuntimeManager.swift` | sing-box 进程生命周期管理 |
| `SingBoxAPIClient.swift` | sing-box REST API 客户端 |
| `SingBoxPaths.swift` | 文件系统布局 |

**下载脚本：** `Scripts/download-singbox.sh`

sing-box 二进制通过 XPC Helper 安装到 `/Library/Application Support/Riptide/singbox/Binaries/sing-box`。

### 3.9 节点编辑器 UI 改动

| 视图 | 改动 |
|------|------|
| `NodeEditorView.swift` | 新增 TLS 指纹下拉、UDP over TCP 开关、协议嗅探开关 |
| `RealityNodeSheet.swift` | **新增** — Reality 节点专用编辑表单 |
| `AdvancedNodeSettings.swift` | **新增** — Multiplex、协议嗅探等高级设置 |

### 3.10 实施文件清单（Phase 1）

**新增文件：**

```
Sources/Riptide/SingBox/
  SingBoxConfigGenerator.swift
  SingBoxRuntimeManager.swift
  SingBoxAPIClient.swift
  SingBoxPaths.swift
Sources/Riptide/Engines/
  ProxyEngine.swift              (protocol)
  MihomoEngine.swift             (wraps existing)
  SingBoxEngineImpl.swift        (wraps SingboxConfigGenerator)
  EngineRouter.swift             (routes by ProxyKind)
Sources/RiptideApp/Views/
  RealityNodeSheet.swift
  AdvancedNodeSettings.swift
Scripts/
  download-singbox.sh
Tests/
  SingboxConfigGeneratorTests.swift
  SingboxAPIClientTests.swift
  RealityURIParserTests.swift
  EngineRouterTests.swift
```

**修改文件：**

```
Sources/Riptide/Models/ProxyModels.swift     (新增字段)
Sources/Riptide/Mihomo/MihomoConfigGenerator.swift  (新字段输出)
Sources/RiptideApp/Views/NodeEditorView.swift
Sources/Riptide/Config/ValidationRules.swift
Sources/Riptide/Subscription/URIProtocols.swift
Tests/MihomoConfigGeneratorTests.swift
Tests/ProxyModelsTests.swift
```

## 4. Phase 2 — 能力扩展

### 4.1 WireGuard

- sing-box 支持完整 WireGuard 协议
- 新增 `ProxyKind.wireGuard` 和对应 `WireGuardConfig` 模型
- UI：WireGuard 节点编辑表单

### 4.2 ShadowTLS

- sing-box 独有协议
- 新增 `ProxyKind.shadowTLS` 和对应配置

### 4.3 NaiveProxy

- 基于 Chrome 网络栈的强伪装代理
- 新增 `ProxyKind.naive`

### 4.4 Tor 集成

- 内置 Tor SOCKS 出站支持
- 新增 `ProxyKind.tor`

### 4.5 订阅过滤与节点重写

- 正则表达式过滤节点
- 节点名重写规则

### 4.6 MITM JavaScript 脚本

- 基于现有 MITM 框架，扩展 JavaScript 修改请求/响应

### 4.7 Tailscale 集成

- 利用 sing-box 的 Tailscale 出站支持

## 5. Phase 3（可选）

| 功能 | 说明 |
|------|------|
| 启动项管理 | Surge 风格开机启动控制 |
| URL Scheme 唤起 | `riptide://` 协议支持 |
| CSS 注入 | MITM 高级功能 |
| ACM 证书申请 | sing-box ACME 自动证书 |

## 6. 风险与缓解

| 风险 | 缓解方案 |
|------|---------|
| sing-box 配置格式复杂 | Phase 1 仅实现核心协议所需最小配置子集 |
| 两种引擎状态同步 | ProxyEngine 抽象隔离，运行时只激活一个引擎 |
| mihomo vs sing-box 协议混淆 | EngineRouter 根据 ProxyKind 自动路由，用户无感知 |
| Reality URL 解析 | 扩展现有 URI 解析框架，支持 `vless+reality://` |
| sing-box 二进制下载/安装 | 复用 `download-mihomo.sh` 架构，通过 XPC Helper 安装 |

## 7. 成功标准

### Phase 1

- [ ] Reality 节点可通过 URL 导入并正常连接
- [ ] Reality 节点可手动创建并编辑
- [ ] TLS 指纹选项在所有支持 TLS 的协议中可用
- [ ] UDP over TCP 配置正确输出到 mihomo/sing-box
- [ ] Multiplex 设置正确输出
- [ ] sing-box 进程可通过 XPC 启动/停止
- [ ] sing-box Reality 节点延迟测试正常工作
- [ ] 所有新功能有对应单元测试

### Phase 2

- [ ] WireGuard / ShadowTLS / NaiveProxy 节点可用
- [ ] Tor SOCKS 出站支持
- [ ] 订阅过滤/节点重写功能
- [ ] Tailscale 集成

### Phase 3

- [ ] 开机启动管理
- [ ] URL Scheme 支持
- [ ] MITM 高级功能
