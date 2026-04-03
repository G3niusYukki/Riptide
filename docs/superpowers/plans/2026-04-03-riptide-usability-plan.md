# Riptide 可用性提升实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Riptide 能够加载真实 Clash 配置，连接 VLESS/Trojan/Shadowsocks 代理，实现规则路由、DNS 解析、TUN 全局代理，并提供完整 macOS UI。

**Architecture:** 采用 Core Library + SwiftUI App 分层设计。Core Library 不依赖 SwiftUI，通过 `LiveTunnelRuntime` actor 暴露 tunnel 生命周期；SwiftUI App 通过 `AppViewModel` 连接 Core Library 的 control channel 和 event streams。

**Tech Stack:** Swift 6.2, Network.framework (NWConnection/NWListener), CryptoKit, Yams, SwiftUI, NetworkExtension (PacketTunnelProvider)

---

## 文件结构映射

| 文件 | 操作 |
|------|------|
| `Sources/Riptide/Models/ProxyModels.swift` | 修改 — ProxyNode 新增字段 |
| `Sources/Riptide/Config/ClashConfigParser.swift` | 修改 — 扩展 proxy-groups/dns 解析 |
| `Sources/Riptide/Connection/ProxyConnector.swift` | 修改 — 接入 VLESS/Trojan |
| `Sources/Riptide/Transport/TLSTransport.swift` | 修改 — 修复 skipCertVerify + timeout |
| `Sources/Riptide/Transport/WSTransport.swift` | 重写 — 实现 WebSocket |
| `Sources/Riptide/Protocols/VLESS/VLESSStream.swift` | 修改 — 修复 IPv6 + protobuf |
| `Sources/Riptide/Protocols/Trojan/TrojanStream.swift` | 修改 — 修复 SHA-224 + framing |
| `Sources/Riptide/Tunnel/LiveTunnelRuntime.swift` | 修改 — 接入 group resolver + DNS |
| `Sources/Riptide/DNS/DNSPipeline.swift` | 修改 — 暴露 isFakeIP/cidr 初始化 |
| `Sources/Riptide/Groups/ProxyGroupResolver.swift` | 新建 — Select 类型实现 |
| `Sources/RiptideApp/AppViewModel.swift` | 重写 — 完整数据层 |
| `Sources/RiptideApp/RiptideApp.swift` | 重写 — 状态栏 + TabView |
| `Sources/RiptideApp/Views/` | 新建 — 5 个 Tab View |
| `Sources/Riptide/VPN/VPNTunnelManager.swift` | 修改 — 接入 NETunnelProviderManager |
| `Sources/Riptide/VPN/TunnelProviderBridge.swift` | 新建 — App ↔ Extension 通信 |


---

## Phase 1: 模型与解析基础

### Task 1: 扩展 ProxyNode 模型

**Files:**
- Modify: `Sources/Riptide/Models/ProxyModels.swift`

- [ ] **Step 1: 添加新字段到 ProxyNode initializer**

在 `ProxyModels.swift` 的 `ProxyNode` 结构体中，`password` 之后添加新参数并更新 initializer：

```swift
public struct ProxyNode: Equatable, Sendable {
    public let name: String
    public let kind: ProxyKind
    public let server: String
    public let port: Int
    public let cipher: String?
    public let password: String?
    // --- 新增 ---
    public let uuid: String?
    public let flow: String?
    public let alterId: Int?
    public let security: String?
    public let sni: String?
    public let alpn: [String]?
    public let skipCertVerify: Bool?
    public let network: String?
    public let wsPath: String?
    public let wsHost: String?
    public let grpcServiceName: String?

    public init(
        name: String,
        kind: ProxyKind,
        server: String,
        port: Int,
        cipher: String? = nil,
        password: String? = nil,
        // --- 新增参数 ---
        uuid: String? = nil,
        flow: String? = nil,
        alterId: Int? = nil,
        security: String? = nil,
        sni: String? = nil,
        alpn: [String]? = nil,
        skipCertVerify: Bool? = nil,
        network: String? = nil,
        wsPath: String? = nil,
        wsHost: String? = nil,
        grpcServiceName: String? = nil
    ) {
        self.name = name
        self.kind = kind
        self.server = server
        self.port = port
        self.cipher = cipher
        self.password = password
        // --- 新增赋值 ---
        self.uuid = uuid
        self.flow = flow
        self.alterId = alterId
        self.security = security
        self.sni = sni
        self.alpn = alpn
        self.skipCertVerify = skipCertVerify
        self.network = network
        self.wsPath = wsPath
        self.wsHost = wsHost
        self.grpcServiceName = grpcServiceName
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `swift build --filter Riptide`
Expected: 编译成功，无错误

- [ ] **Step 3: Commit**

```bash
git add Sources/Riptide/Models/ProxyModels.swift
git commit -m "feat(models): extend ProxyNode with VLESS/TLS/WS fields"
```

---

### Task 2: 扩展 ClashConfigParser — proxy-groups 解析

**Files:**
- Modify: `Sources/Riptide/Config/ClashConfigParser.swift`

首先读取完整文件以了解现有结构，然后：

- [ ] **Step 1: 添加 ClashRawProxyGroup struct**

在 `ClashRawConfig` 之前添加：

```swift
private struct ClashRawProxyGroup: Codable {
    let name: String?
    let `type`: String?
    let proxies: [String]?
    let interval: Int?
    let tolerance: Int?
    let strategy: String?
    let url: String?
    let intervalAttr: String?  // YAML: "interval" can be string "300" or int 300

    private enum CodingKeys: String, CodingKey {
        case name = "name"
        case type = "type"
        case proxies = "proxies"
        case interval = "interval"
        case tolerance = "tolerance"
        case strategy = "strategy"
        case url = "url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        proxies = try container.decodeIfPresent([String].self, forKey: .proxies)
        tolerance = try container.decodeIfPresent(Int.self, forKey: .tolerance)
        strategy = try container.decodeIfPresent(String.self, forKey: .strategy)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        // interval 可以是 Int 或 String (e.g. "300s")
        if let intVal = try? container.decodeIfPresent(Int.self, forKey: .interval) {
            interval = intVal
        } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .interval) {
            // 去掉 "s" 后缀，解析数字
            interval = Int(strVal.replacingOccurrences(of: "s", with: ""))
        } else {
            interval = nil
        }
    }
}
```

- [ ] **Step 2: 添加 ClashRawDNS struct**

```swift
private struct ClashRawDNS: Codable {
    let enable: Bool?
    let listen: String?
    let `enhancedMode`: String?  // "fake-ip", "redir-host"
    let fakeIPRange: String?
    let fakeIPFilter: [String]?
    let nameserver: [String]?
    let fallback: [String]?
    let nameserverPolicy: [String: [String]]?

    private enum CodingKeys: String, CodingKey {
        case enable = "enable"
        case listen = "listen"
        case enhancedMode = "enhanced-mode"
        case fakeIPRange = "fake-ip-range"
        case fakeIPFilter = "fake-ip-filter"
        case nameserver = "nameserver"
        case fallback = "fallback"
        case nameserverPolicy = "nameserver-policy"
    }
}
```

- [ ] **Step 3: 扩展 ClashRawConfig 添加 proxy-groups 和 dns**

在 `ClashRawConfig` struct 中添加：

```swift
private struct ClashRawConfig: Codable {
    var mode: String?
    var proxies: [ClashRawProxy]?
    var proxyGroups: [ClashRawProxyGroup]?
    var dns: ClashRawDNS?
    var rules: [String]?
    var unallocated: Data?

    private enum CodingKeys: String, CodingKey {
        case mode, proxies, rules
        case proxyGroups = "proxy-groups"
        case dns
    }

    // 处理未知字段
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        proxies = try container.decodeIfPresent([ClashRawProxy].self, forKey: .proxies)
        proxyGroups = try container.decodeIfPresent([ClashRawProxyGroup].self, forKey: .proxyGroups)
        dns = try container.decodeIfPresent(ClashRawDNS.self, forKey: .dns)
        rules = try container.decodeIfPresent([String].self, forKey: .rules)
        // 收集未分配的 key（警告用）
        unallocated = nil
    }
}
```

- [ ] **Step 4: 扩展 ClashRawProxy 添加新字段**

在 `ClashRawProxy` 中添加：

```swift
private struct ClashRawProxy: Codable {
    let name: String?
    let type: String?
    let server: String?
    let port: Int?
    let cipher: String?
    let password: String?
    let uuid: String?           // VMess / VLESS
    let alterId: Int?           // VMess
    let security: String?       // VMess
    let flow: String?           // VLESS
    let network: String?        // "tcp" / "ws" / "grpc"
    let tls: Bool?
    let sni: String?
    let alpn: [String]?
    let skipCertVerify: Bool?   // "skip-cert-verify" in YAML
    let wsOpts: WSOpts?
    let grpcOpts: GRPCOpts?

    struct WSOpts: Codable {
        let path: String?
        let headers: [String: String]?
    }

    struct GRPCOpts: Codable {
        let grpcServiceName: String?

        private enum CodingKeys: String, CodingKey {
            case grpcServiceName = "grpc-service-name"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name, type, server, port, cipher, password
        case uuid, alterId, security, flow, network, tls, sni, alpn
        case skipCertVerify = "skip-cert-verify"
        case wsOpts = "ws-opts"
        case grpcOpts = "grpc-opts"
    }
}
```

- [ ] **Step 5: 扩展 parseProxyKind 支持 vless 和 trojan**

在 `ClashConfigParser.swift` 的 `parseProxyKind` 函数中，在 `case "ss"` 之后添加：

```swift
case "vless":
    return .vless
case "trojan":
    return .trojan
```

删除或注释掉原来的 fallback `throw` 中的 `vmess/vless/trojan/hysteria2` 类型，因为现在已有对应解析。

- [ ] **Step 6: 在 parseProxies 中添加 vless 和 trojan 分支**

在 `parseProxies` 的 switch kind 中，`.shadowsocks` 分支之后添加：

```swift
case .vless:
    guard let uuid = proxy.uuid, !uuid.isEmpty else {
        throw ClashConfigError.invalidProxy(index: index, reason: "uuid is required for VLESS")
    }
    return ProxyNode(
        name: proxy.name,
        kind: .vless,
        server: proxy.server,
        port: port,
        uuid: uuid,
        flow: proxy.flow,
        network: proxy.network,
        sni: proxy.sni,
        alpn: proxy.alpn,
        skipCertVerify: proxy.skipCertVerify,
        wsPath: proxy.wsOpts?.path,
        wsHost: proxy.wsOpts?.headers?["Host"],
        grpcServiceName: proxy.grpcOpts?.grpcServiceName
    )

case .trojan:
    guard let password = proxy.password, !password.isEmpty else {
        throw ClashConfigError.invalidProxy(index: index, reason: "password is required for Trojan")
    }
    return ProxyNode(
        name: proxy.name,
        kind: .trojan,
        server: proxy.server,
        port: port,
        password: password,
        sni: proxy.sni,
        alpn: proxy.alpn,
        skipCertVerify: proxy.skipCertVerify,
        network: proxy.network
    )
```

- [ ] **Step 7: 添加 parseProxyGroups 函数**

在 `parseProxies` 之后添加：

```swift
private static func parseProxyGroups(_ rawGroups: [ClashRawProxyGroup]?) throws -> [ProxyGroup] {
    guard let rawGroups, !rawGroups.isEmpty else {
        return []
    }
    return try rawGroups.enumerated().map { index, group in
        guard let id = group.name, !id.isEmpty else {
            // proxy-group 可以没有 name 但有 "name" key
            throw ClashConfigError.invalidProxy(index: index, reason: "proxy-group name is required")
        }
        guard let typeStr = group.type else {
            throw ClashConfigError.invalidProxy(index: index, reason: "proxy-group type is required")
        }
        let kind: ProxyGroupKind
        switch typeStr {
        case "select": kind = .select
        case "url-test", "url-test": kind = .urlTest
        case "fallback": kind = .fallback
        case "load-balance": kind = .loadBalance
        default:
            throw ClashConfigError.invalidProxy(index: index, reason: "unsupported proxy-group type: \(typeStr)")
        }
        let strategy: LBStrategy?
        if let s = group.strategy {
            strategy = (s == "consistent-hashing") ? .consistentHashing : .roundRobin
        } else {
            strategy = nil
        }
        return ProxyGroup(
            id: id,
            kind: kind,
            proxies: group.proxies ?? [],
            interval: group.interval,
            tolerance: group.tolerance,
            strategy: strategy
        )
    }
}
```

- [ ] **Step 8: 修改 parse 返回值接入 proxyGroups**

将 `parse` 方法中的返回值改为：

```swift
let proxyGroups = try parseProxyGroups(raw.proxyGroups)
return RiptideConfig(mode: mode, proxies: proxies, rules: rules, proxyGroups: proxyGroups)
```

- [ ] **Step 9: 验证编译**

Run: `swift build --filter Riptide`
Expected: 编译成功

- [ ] **Step 10: Commit**

```bash
git add Sources/Riptide/Config/ClashConfigParser.swift
git commit -m "feat(config): parse proxy-groups and VLESS/Trojan proxy types"
```

---

### Task 3: 添加 DNS 配置解析

**Files:**
- Modify: `Sources/Riptide/Config/ClashConfigParser.swift`

- [ ] **Step 1: 读取现有 DNSPolicy 模型**

检查 `Sources/Riptide/DNS/` 下是否有 `DNSPolicy.swift` 文件。如果没有，需要新建一个 DNSPolicy 模型。先搜索：

Run: `ls Sources/Riptide/DNS/`

根据结果决定是新建还是修改现有文件。

假设需要新建 `DNSPolicy.swift`，内容如下：

```swift
import Foundation

public struct DNSPolicy: Equatable, Sendable {
    public let enable: Bool
    public let listen: String?        // "0.0.0.0:53"
    public let enhancedMode: DNSEnhancedMode
    public let fakeIPRange: String?   // "198.18.0.0/15"
    public let fakeIPFilter: [String]
    public let nameserver: [String]
    public let fallback: [String]?
    public let nameserverPolicy: [String: [String]]

    public init(
        enable: Bool = true,
        listen: String? = nil,
        enhancedMode: DNSEnhancedMode = .realIP,
        fakeIPRange: String? = "198.18.0.0/15",
        fakeIPFilter: [String] = [],
        nameserver: [String] = ["8.8.8.8", "1.1.1.1"],
        fallback: [String]? = nil,
        nameserverPolicy: [String: [String]] = [:]
    ) {
        self.enable = enable
        self.listen = listen
        self.enhancedMode = enhancedMode
        self.fakeIPRange = fakeIPRange
        self.fakeIPFilter = fakeIPFilter
        self.nameserver = nameserver
        self.fallback = fallback
        self.nameserverPolicy = nameserverPolicy
    }
}

public enum DNSEnhancedMode: Equatable, Sendable {
    case realIP
    case fakeIP
}
```

- [ ] **Step 2: 添加 parseDNSPolicy 函数**

在 `ClashConfigParser.swift` 中：

```swift
private static func parseDNSPolicy(_ raw: ClashRawDNS?) -> DNSPolicy {
    guard let raw, raw.enable != false else {
        return DNSPolicy(enable: false)
    }
    let enhancedMode: DNSEnhancedMode = (raw.enhancedMode == "fake-ip") ? .fakeIP : .realIP
    return DNSPolicy(
        enable: raw.enable ?? true,
        listen: raw.listen,
        enhancedMode: enhancedMode,
        fakeIPRange: raw.fakeIPRange ?? "198.18.0.0/15",
        fakeIPFilter: raw.fakeIPFilter ?? [],
        nameserver: raw.nameserver ?? ["8.8.8.8", "1.1.1.1"],
        fallback: raw.fallback,
        nameserverPolicy: raw.nameserverPolicy ?? [:]
    )
}
```

- [ ] **Step 3: 扩展 RiptideConfig 包含 dnsPolicy**

在 `RiptideConfig` struct 中添加 `dnsPolicy` 字段（如果不存在）：

```swift
public struct RiptideConfig: Equatable, Sendable {
    public let mode: ProxyMode
    public let proxies: [ProxyNode]
    public let rules: [ProxyRule]
    public let proxyGroups: [ProxyGroup]
    public let dnsPolicy: DNSPolicy

    public init(mode: ProxyMode, proxies: [ProxyNode], rules: [ProxyRule],
                proxyGroups: [ProxyGroup] = [], dnsPolicy: DNSPolicy = DNSPolicy()) {
        self.mode = mode
        self.proxies = proxies
        self.rules = rules
        self.proxyGroups = proxyGroups
        self.dnsPolicy = dnsPolicy
    }
}
```

- [ ] **Step 4: 更新 parse 返回值**

```swift
let dnsPolicy = parseDNSPolicy(raw.dns)
return RiptideConfig(mode: mode, proxies: proxies, rules: rules,
                     proxyGroups: proxyGroups, dnsPolicy: dnsPolicy)
```

- [ ] **Step 5: 验证编译**

Run: `swift build --filter Riptide`
Expected: 编译成功

- [ ] **Step 6: Commit**

```bash
git add Sources/Riptide/Config/ClashConfigParser.swift Sources/Riptide/Models/RiptideConfig.swift Sources/Riptide/DNS/DNSPolicy.swift
git commit -m "feat(config): parse dns section into DNSPolicy model"
```


---

## Phase 2: 传输层

### Task 4: 修复 TLSTransport

**Files:**
- Modify: `Sources/Riptide/Transport/TLSTransport.swift`

- [ ] **Step 1: 读取当前 TLSTransport 实现**

Run: `cat Sources/Riptide/Transport/TLSTransport.swift`

了解现有结构后再做修改。预期需要修改 `TLSTransportDialer.openSession` 方法。

- [ ] **Step 2: 修复 skipCertVerify**

在 `NWParameters` 配置中添加：

```swift
let tlsOptions = NWProtocolTLS.Options()
if skipCertVerify {
    sec_protocol_options_set_tls_verify_peer(tlsOptions.securityProtocolOptions, false)
}
let parameters = NWParameters(tls: tlsOptions, tcp: TCPTransportDialer().makeTCPParameters())
```

- [ ] **Step 3: 添加超时和 task cancellation**

在 `openSession` 的 `connection.stateUpdateHandler` 中添加：

```swift
case .cancelled:
    resumeContinuation(throwing: TransportError.cancelled)
    return
case .waiting(let error):
    // 超时或其他等待状态
    resumeContinuation(throwing: TransportError.connectionFailed("connection waiting: \(error)"))
    return
```

添加一个 15 秒超时 Task：

```swift
let timeoutTask = Task {
    try await Task.sleep(for: .seconds(15))
    connection.cancel()
}
```

在连接成功后取消 timeoutTask：

```swift
case .ready:
    timeoutTask.cancel()
    let session = NWTransportSession(connection: connection, hostname: hostname)
    resumeContinuation(returning: session)
    return
```

- [ ] **Step 4: 验证编译**

Run: `swift build --filter Riptide`
Expected: 编译成功

- [ ] **Step 5: Commit**

```bash
git add Sources/Riptide/Transport/TLSTransport.swift
git commit -m "fix(transport): TLSTransport skipCertVerify, timeout, and cancellation"
```

---

### Task 5: 实现 WSTransport

**Files:**
- Modify: `Sources/Riptide/Transport/WSTransport.swift`

**完全重写此文件。** 使用 `URLSessionWebSocketTask` 实现。

- [ ] **Step 1: 定义 WSTransportSession actor**

```swift
import Foundation

public enum TransportError: Error, Equatable, Sendable {
    case connectionFailed(String)
    case invalidResponse(String)
    case unsupportedSessionOperation
    case cancelled
    case timeout
}

public actor WSTransportSession: TransportSession {
    private let task: URLSessionWebSocketTask
    private var receiveTask: Task<Void, Never>?
    private let inboundBuffer: AsyncStream<Data>.Continuation
    public let inbound: AsyncStream<Data>
    private var closed = false

    init(task: URLSessionWebSocketTask) {
        self.task = task
        var continuation: AsyncStream<Data>.Continuation!
        self.inbound = AsyncStream { continuation = $0 }
        self.inboundBuffer = continuation
        task.resume()
    }

    public func send(_ data: Data) async throws {
        guard !closed else { throw TransportError.cancelled }
        try await task.send(.data(data))
    }

    public func receive() async throws -> Data {
        guard !closed else { throw TransportError.cancelled }
        let message = try await task.receive()
        switch message {
        case .data(let d): return d
        case .string(let s): return Data(s.utf8)
        @unknown default: throw TransportError.invalidResponse("unknown message type")
        }
    }

    public func close() {
        guard !closed else { return }
        closed = true
        receiveTask?.cancel()
        task.cancel(with: .normalClosure, reason: nil)
        inboundBuffer.finish()
    }
}

public struct WSTransportDialer: TransportDialer {
    public let path: String
    public let host: String
    public let port: Int

    public init(path: String = "/", host: String, port: Int) {
        self.path = path
        self.host = host
        self.port = port
    }

    public func openSession(to node: ProxyNode) async throws -> any TransportSession {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = node.wsHost ?? node.server
        components.port = node.port
        components.path = node.wsPath ?? "/"
        guard let url = components.url else {
            throw TransportError.connectionFailed("invalid WebSocket URL")
        }
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        return WSTransportSession(task: task)
    }
}
```

- [ ] **Step 2: 验证编译**

Run: `swift build --filter Riptide`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add Sources/Riptide/Transport/WSTransport.swift
git commit -m "feat(transport): implement WSTransport with URLSessionWebSocketTask"
```

---

### Task 6: ProxyConnector transport 选择

**Files:**
- Modify: `Sources/Riptide/Connection/ProxyConnector.swift`

- [ ] **Step 1: 在 TransportConnectionPool 中添加 withDialer 扩展方法**

在 `TransportConnectionPool.swift` 中添加：

```swift
public func acquire(for node: ProxyNode, using dialer: any TransportDialer) async throws -> PooledTransportConnection {
    let key = PoolKey(from: node)
    await evictStale(key: key)
    let session = try await dialer.openSession(to: node)
    return PooledTransportConnection(node: node, session: session)
}
```

这样避免修改现有 `acquire(for:)` 方法。

- [ ] **Step 2: 添加 selectDialer 函数**

在 `ProxyConnector` 中添加：

```swift
private func selectDialer(for node: ProxyNode) -> any TransportDialer {
    let useTLS = node.port == 443 || node.sni != nil || node.skipCertVerify != nil
    if node.network == "ws" || node.network == "grpc" {
        // WebSocket dialer: WSTransportDialer（Phase 2 Task 5 实现后替换）
        return TLSTransportDialer(skipCertVerify: node.skipCertVerify ?? false)
    } else if useTLS {
        return TLSTransportDialer(skipCertVerify: node.skipCertVerify ?? false)
    } else {
        return TCPTransportDialer()
    }
}
```

- [ ] **Step 3: 修改 pool.acquire 调用**

将：
```swift
let connection = try await pool.acquire(for: node)
```
替换为：
```swift
let dialer = selectDialer(for: node)
let connection = try await pool.acquire(for: node, using: dialer)
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Riptide/Connection/ProxyConnector.swift
git commit -m "feat(connector): select transport based on node TLS/WS config"
```


---

## Phase 3: 协议接入

### Task 7: 修复 VLESSStream

**Files:**
- Modify: `Sources/Riptide/Protocols/VLESS/VLESSStream.swift`

**关键修复点：**

1. **IPv6 编码 bug（第 60 行）**: 当前用 `contains(":")` 判断后编码为 domain-style（length-prefixed string），但 IPv6 应编码为 raw 16 字节 binary，ATYP=3。
2. **Addons 应为 protobuf**: 当前直接写 raw UTF-8 string，需要改用 protobuf encode。

先读取完整文件：

Run: `cat Sources/Riptide/Protocols/VLESS/VLESSStream.swift`

然后做以下修改：

- [ ] **Step 1: 修复 IPv6 编码**

在 `encodeAddress` 方法中，将：

```swift
if host.contains(":") {
    atyp = 3
    addrData = Data(host.utf8)
}
```

改为（检测是否为纯 IPv6）：

```swift
if let _ = IPv6AddressParser.parse(host) {
    atyp = 4  // IPv6: ATYP=4
    addrData = Data(parseIPv6(host))
} else if host.contains(":") {
    // domain containing colon (rare)
    atyp = 3
    var data = Data()
    data.append(UInt8(host.utf8.count))
    data.append(contentsOf: host.utf8)
    addrData = data
}
```

实现 `parseIPv6` 辅助函数，将 IPv6 string 转为 16 字节 Data：

```swift
private func parseIPv6(_ addr: String) -> Data {
    var sin6 = sockaddr_in6()
    addr.withCString { ptr in
        inet_pton(AF_INET6, ptr, &sin6.sin6_addr)
    }
    return Data(bytes: &sin6.sin6_addr, count: 16)
}
```

- [ ] **Step 2: Addons 改为 protobuf**

安装 `swift-protobuf` 或使用手写简单 protobuf encode。推荐使用 `swift-protobuf`（需在 Package.swift 中添加依赖）。

如果用 swift-protobuf，定义：

```swift
import SwiftProtobuf

message VLESSSession {
    string name = 1;
    string flow = 2;
}
```

在 `connect` 方法中序列化：

```swift
let session = VLESSSession.with { $0.flow = flow ?? "" }
let addonData = try session.serializedBytes()
var addonFrame = Data([UInt8(addonData.count)])
addonFrame.append(addonData)
```

- [ ] **Step 3: 验证编译**

Run: `swift build --filter Riptide`
Expected: 编译成功

- [ ] **Step 4: Commit**

```bash
git add Sources/Riptide/Protocols/VLESS/VLESSStream.swift
git commit -m "fix(protocol): VLESS IPv6 raw encoding and protobuf addons"
```

---

### Task 8: 修复 TrojanStream

**Files:**
- Modify: `Sources/Riptide/Protocols/Trojan/TrojanStream.swift`

**关键修复点：**

1. **SHA-256 → SHA-224**: 协议规定 password hash 应用 SHA-224。
2. **Outbound framing**: 每帧格式 `{hex_length}\r\n{data}\r\n`。
3. **Inbound parsing**: 读取 hex-length + CRLF，再读 data + 尾部 CRLF。
4. **TLS 强制检查**: `connect` 开始时检查是否在 TLS session 上。

读取文件：

Run: `cat Sources/Riptide/Protocols/Trojan/TrojanStream.swift`

然后：

- [ ] **Step 1: 修复 SHA-224**

在 `connect` 方法顶部，当前用 `SHA256`：

```swift
let passwordHash = SHA256.hash(data: Data(password.utf8))
    .map { String(format: "%02x", $0) }
    .joined()
    .prefix(56)
```

改为：

```swift
import CryptoKit
let passwordData = Data(password.utf8)
let sha224 = Insecure.SHA224.hash(data: passwordData)
let passwordHash = sha224.map { String(format: "%02x", $0) }.joined()
```

- [ ] **Step 2: 添加 outbound hex-length CRLF framing**

在 `send` 方法中，发送前包装数据：

```swift
public func send(_ data: Data) async throws {
    let hexLen = String(data.count, radix: 16)
    let frame = "\(hexLen)\r\n"
    try await session.send(Data(frame.utf8))
    try await session.send(data)
    try await session.send(Data("\r\n".utf8))
}
```

- [ ] **Step 3: 添加 inbound length parsing**

在 `receive` 方法中：

```swift
public func receive() async throws -> Data {
    // 1. 读取 hex-length + CRLF
    var lenBuf = Data()
    while true {
        let b = try await session.receive()
        if b.count == 1 && b[0] == 0x0D {
            // 遇到 \r，等待 \n
            let n = try await session.receive()
            if n.count == 1 && n[0] == 0x0A {
                break
            }
        }
        lenBuf.append(b)
    }
    guard let count = Int(String(data: lenBuf, encoding: .utf8) ?? "", radix: 16) else {
        throw ProtocolError.malformedResponse("invalid Trojan length prefix")
    }
    // 2. 读取 data
    var body = Data()
    var remaining = count
    while remaining > 0 {
        let chunk = try await session.receive()
        body.append(chunk)
        remaining -= chunk.count
    }
    // 3. 读取尾部 \r\n
    _ = try await session.receive()  // \r
    _ = try await session.receive()  // \n
    return body
}
```

- [ ] **Step 4: 添加 TLS 强制检查**

在 `connect` 方法开头：

```swift
// Trojan 必须通过 TLS 连接，否则密码以明文传输
// 检查 session 是否有 TLS 标识（通过检查 node.port 或 sni）
if session is TLSTransportSession {
    // OK
} else if session is NWTransportSession {
    // OK — NWTransportSession 内部可能已带 TLS
} else {
    throw ProtocolError.missingTLS("Trojan requires TLS transport")
}
```

（实际实现可能需要调整类型检查方式，取决于 session 的具体类型）

- [ ] **Step 5: 验证编译**

Run: `swift build --filter Riptide`
Expected: 编译成功

- [ ] **Step 6: Commit**

```bash
git add Sources/Riptide/Protocols/Trojan/TrojanStream.swift
git commit -m "fix(protocol): Trojan SHA-224, hex-length CRLF framing, TLS enforcement"
```

---

### Task 9: ProxyConnector 接入 VLESS 和 Trojan

**Files:**
- Modify: `Sources/Riptide/Connection/ProxyConnector.swift`

- [ ] **Step 1: 添加 import**

在文件顶部添加：

```swift
import Riptide // For VLESSStream, TrojanStream
```

- [ ] **Step 2: 在 connect 的 switch 中添加 vless 和 trojan case**

将：

```swift
case .vmess, .vless, .trojan, .hysteria2:
    throw ProtocolError.malformedResponse("\(node.kind) protocol connector not yet implemented")
```

替换为：

```swift
case .vless:
    return try await performVLESSConnect(connection: connection, node: node, target: target)
case .trojan:
    return try await performTrojanConnect(connection: connection, node: node, target: target)
case .vmess, .hysteria2:
    throw ProtocolError.malformedResponse("\(node.kind) protocol not supported yet")
```

- [ ] **Step 3: 实现 performVLESSConnect**

在 `performShadowsocksConnect` 之后添加：

```swift
private func performVLESSConnect(
    connection: PooledTransportConnection,
    node: ProxyNode,
    target: ConnectionTarget
) async throws -> ConnectedProxyContext {
    guard let uuid = node.uuid else {
        throw ProtocolError.malformedResponse("VLESS node missing uuid")
    }
    let vlessStream = VLESSStream(session: connection.session, uuid: uuid)
    try await vlessStream.connect(to: target, flow: node.flow)
    return ConnectedProxyContext(node: node, connection: connection)
}
```

- [ ] **Step 4: 实现 performTrojanConnect**

```swift
private func performTrojanConnect(
    connection: PooledTransportConnection,
    node: ProxyNode,
    target: ConnectionTarget
) async throws -> ConnectedProxyContext {
    guard let password = node.password else {
        throw ProtocolError.malformedResponse("Trojan node missing password")
    }
    let trojanStream = TrojanStream(session: connection.session, password: password)
    try await trojanStream.connect(to: target)
    return ConnectedProxyContext(node: node, connection: connection)
}
```

- [ ] **Step 5: 更新 ConnectedProxyContext**

`ConnectedProxyContext` 当前有 `encryptedStream: ShadowsocksStream?` 字段。对 VLESS/Trojan，encrypted stream 由各自的 Stream actor 管理，不需要这个字段。保持现状（传 nil）即可。

- [ ] **Step 6: 验证编译**

Run: `swift build --filter Riptide`
Expected: 编译成功

- [ ] **Step 7: Commit**

```bash
git add Sources/Riptide/Connection/ProxyConnector.swift
git commit -m "feat(connector): wire VLESS and Trojan protocols into ProxyConnector"
```


---

## Phase 4: 运行时集成

### Task 10: 新建 ProxyGroupResolver

**Files:**
- Create: `Sources/Riptide/Groups/ProxyGroupResolver.swift`
- Modify: `Sources/Riptide/Tunnel/LiveTunnelRuntime.swift`

- [ ] **Step 1: 创建 ProxyGroupResolver actor**

```swift
import Foundation

public actor ProxyGroupResolver {
    private var selections: [String: String] = [:]  // groupID -> selected node name
    private let healthChecker: HealthChecker

    public init(healthChecker: HealthChecker = HealthChecker()) {
        self.healthChecker = healthChecker
    }

    /// Resolve a group reference to a concrete proxy node name.
    /// Returns the selected node name, or nil if not found.
    public func resolve(groupID: String, group: ProxyGroup, allProxies: [ProxyNode]) -> String? {
        switch group.kind {
        case .select:
            return resolveSelect(group: group)
        case .urlTest:
            return resolveURLTest(group: group, allProxies: allProxies)
        case .fallback:
            return resolveFallback(group: group, allProxies: allProxies)
        case .loadBalance:
            return resolveLoadBalance(group: group, allProxies: allProxies)
        }
    }

    private func resolveSelect(group: ProxyGroup) -> String {
        // Return persisted selection or default to first proxy
        if let saved = selections[group.id] {
            return saved
        }
        let first = group.proxies.first ?? "DIRECT"
        selections[group.id] = first
        return first
    }

    private func resolveURLTest(group: ProxyGroup, allProxies: [ProxyNode]) -> String {
        // Return proxy with lowest latency from health checker
        // For now, return first alive proxy
        for name in group.proxies {
            if let proxy = allProxies.first(where: { $0.name == name }),
               let delay = healthChecker.cachedDelay(for: proxy.name),
               delay < 300 {
                return name
            }
        }
        return group.proxies.first ?? "DIRECT"
    }

    private func resolveFallback(group: ProxyGroup, allProxies: [ProxyNode]) -> String {
        for name in group.proxies {
            if let proxy = allProxies.first(where: { $0.name == name }),
               healthChecker.isAlive(proxy.name) {
                return name
            }
        }
        return group.proxies.first ?? "DIRECT"
    }

    private func resolveLoadBalance(group: ProxyGroup, allProxies: [ProxyNode]) -> String {
        guard !group.proxies.isEmpty else { return "DIRECT" }
        let idx = Int.random(in: 0..<group.proxies.count)
        return group.proxies[idx]
    }

    /// Set user's manual selection for a select-type group.
    public func setSelection(groupID: String, nodeName: String) {
        selections[groupID] = nodeName
    }

    /// Clear all persisted selections.
    public func reset() {
        selections.removeAll()
    }
}
```

- [ ] **Step 2: 在 LiveTunnelRuntime 中注入 ProxyGroupResolver**

在 `LiveTunnelRuntime.init` 中添加：

```swift
public actor LiveTunnelRuntime: TunnelRuntime {
    private let proxyDialer: any TransportDialer
    private let directDialer: any TransportDialer
    private let geoIPResolver: GeoIPResolver
    private var proxyPool: TransportConnectionPool
    private var directPool: TransportConnectionPool
    private var connector: ProxyConnector
    private var groupResolver: ProxyGroupResolver  // 新增
    private var currentProfile: TunnelProfile?
    // ...
}
```

- [ ] **Step 3: 修改 openConnection 中的 .proxyNode 分支**

在 `openConnection` 方法的 `case .proxyNode(let name):` 分支中：

```swift
case .proxyNode(let name):
    // Resolve group if name matches a proxy group
    if let group = currentProfile?.config.proxyGroups.first(where: { $0.id == name }) {
        guard let resolvedName = await groupResolver.resolve(
            groupID: name,
            group: group,
            allProxies: currentProfile?.config.proxies ?? []
        ) else {
            throw LiveTunnelRuntimeError.missingProxyNode(name)
        }
        guard let node = currentProfile?.config.proxies.first(where: { $0.name == resolvedName }) else {
            throw LiveTunnelRuntimeError.missingProxyNode(resolvedName)
        }
        let context = try await connector.connect(via: node, to: target)
        // ...
    } else {
        // Direct proxy node reference
        guard let node = currentProfile?.config.proxies.first(where: { $0.name == name }) else {
            throw LiveTunnelRuntimeError.missingProxyNode(name)
        }
        let context = try await connector.connect(via: node, to: target)
        // ...
    }
```

- [ ] **Step 4: 验证编译**

Run: `swift build --filter Riptide`
Expected: 编译成功

- [ ] **Step 5: Commit**

```bash
git add Sources/Riptide/Groups/ProxyGroupResolver.swift Sources/Riptide/Tunnel/LiveTunnelRuntime.swift
git commit -m "feat(runtime): integrate ProxyGroupResolver into LiveTunnelRuntime"
```

---

### Task 11: DNSPipeline 接入

**Files:**
- Modify: `Sources/Riptide/Tunnel/LiveTunnelRuntime.swift`

- [ ] **Step 1: 在 LiveTunnelRuntime 中注入 DNSPipeline**

```swift
private let dnsPipeline: DNSPipeline

public init(
    proxyDialer: any TransportDialer,
    directDialer: any TransportDialer,
    geoIPResolver: GeoIPResolver = .none,
    dnsPipeline: DNSPipeline  // 新增
) {
    self.proxyDialer = proxyDialer
    self.directDialer = directDialer
    self.geoIPResolver = geoIPResolver
    self.dnsPipeline = dnsPipeline  // 新增
    // ...
}
```

- [ ] **Step 2: 在 start 中初始化 Fake-IP 池**

```swift
public func start(profile: TunnelProfile) async throws {
    currentProfile = profile
    // ...
    // Initialize Fake-IP pool if enabled
    if profile.config.dnsPolicy.enhancedMode == .fakeIP,
       let cidr = profile.config.dnsPolicy.fakeIPRange {
        await dnsPipeline.startFakeIPPool(cidr: cidr)
    }
}
```

- [ ] **Step 3: 在 resolvePolicy 中集成 DNS 解析**

在 `resolvePolicy` 方法开头添加：

```swift
private func resolvePolicy(profile: TunnelProfile, target: ConnectionTarget) -> RoutingPolicy {
    // Resolve domain to IP via DNS pipeline
    var resolvedHost = target.host
    if IPv4AddressParser.parse(target.host) == nil && IPv6AddressParser.parse(target.host) == nil {
        // It's a domain name
        let ips = try? await dnsPipeline.resolve(target.host)
        if let firstIP = ips?.first {
            resolvedHost = firstIP
        }
    }
    // ... 后续使用 resolvedHost 而非 target.host 做 IP 匹配
}
```

- [ ] **Step 4: 验证编译**

Run: `swift build --filter Riptide`
Expected: 编译成功

- [ ] **Step 5: Commit**

```bash
git add Sources/Riptide/Tunnel/LiveTunnelRuntime.swift
git commit -m "feat(runtime): integrate DNSPipeline into LiveTunnelRuntime"
```


---

## Phase 5: TUN 模式

### Task 12: 创建 RiptideTunnel Network Extension target

**Files:**
- Create: `Sources/RiptideTunnel/PacketTunnelProvider.swift`
- Modify: `Riptide.yml` (XcodeGen project.yml)

> Network Extension target 需要在 Xcode 项目中添加，Package.swift 不支持 Network Extension。需要在 `project.yml` 中配置。

- [ ] **Step 1: 创建 PacketTunnelProvider.swift**

在 `Sources/RiptideTunnel/` 目录（需新建）：

```swift
import NetworkExtension
import Riptide

class RiptidePacketTunnelProvider: PacketTunnelProvider {
    private var runtime: LiveTunnelRuntime?
    private var dnsPipeline: DNSPipeline?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        Task {
            do {
                // Read configuration from protocolConfiguration
                guard let tunnelConfig = protocolConfiguration as? NETunnelProviderSession else {
                    completionHandler(TunnelError.invalidConfiguration)
                    return
                }

                let profile = tunnelConfig.extractProfile()  // 需要从协议配置中提取
                let dnsPipeline = DNSPipeline(dnsPolicy: profile.config.dnsPolicy)

                let proxyDialer = TCPTransportDialer()
                let directDialer = TCPTransportDialer()
                let runtime = LiveTunnelRuntime(
                    proxyDialer: proxyDialer,
                    directDialer: directDialer,
                    dnsPipeline: dnsPipeline
                )

                try await runtime.start(profile: profile)
                self.runtime = runtime
                self.dnsPipeline = dnsPipeline

                // Configure network settings
                let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
                networkSettings.ipv4Settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
                networkSettings.ipv6Settings = NEIPv6Settings(addresses: ["fdfe:dcba:9876::1"], networkPrefixLengths: [16])
                networkSettings.dnsSettings = NEDNSSettings(servers: ["198.18.0.1"])

                try await setTunnelNetworkSettings(networkSettings)

                // Start reading packets
                startPacketFlow()

                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        Task {
            try? await runtime?.stop()
            completionHandler()
        }
    }

    private func startPacketFlow() {
        packetFlow.readPackets { [weak self] packets, protocols in
            self?.handlePackets(packets, protocols: protocols)
            self?.startPacketFlow()  // Re-register
        }
    }

    private func handlePackets(_ packets: [Data], protocols: [NSNumber]) {
        for (packet, proto) in zip(packets, protocols) {
            let handler = PacketHandler()
            if let ipPacket = handler.parse(packet) {
                Task {
                    await routePacket(ipPacket, protocolFamily: proto.intValue)
                }
            }
        }
    }

    private func routePacket(_ packet: IPacket, protocolFamily: Int) async {
        // Route based on packet type: TCP → UserSpaceTCP; UDP DNS → Fake-IP; others → direct
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Handle messages from the containing app via TunnelProviderBridge
        completionHandler?(nil)
    }
}

enum TunnelError: Error {
    case invalidConfiguration
}
```

- [ ] **Step 2: 在 project.yml 中添加 Network Extension target**

```yaml
targets:
  RiptideTunnel:
    type: app-extension
    platform: macOS
    sources:
      - path: Sources/RiptideTunnel
    dependencies:
      - target: Riptide
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.riptide.tunnel
      SKIP_INSTALL: YES
      CODE_SIGN_ENTITLEMENTS: Sources/RiptideTunnel/RiptideTunnel.entitlements
      INFOPLIST_FILE: Sources/RiptideTunnel/Info.plist
```

- [ ] **Step 3: 创建 entitlements 文件**

`Sources/RiptideTunnel/RiptideTunnel.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.networking.networkextension</key>
    <array>
        <string>packet-tunnel-provider</string>
    </array>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.riptide.app</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 4: 创建 Info.plist**

`Sources/RiptideTunnel/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.networkextension.packet-tunnel</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).RiptidePacketTunnelProvider</string>
    </dict>
</dict>
</plist>
```

- [ ] **Step 5: 验证编译**

Run: `swift build --filter RiptideTunnel`
Expected: 编译成功（需要 XcodeGen 先生成项目）

- [ ] **Step 6: Commit**

```bash
git add Sources/RiptideTunnel/ project.yml
git commit -m "feat(tunnel): add RiptideTunnel Network Extension target"
```

---

### Task 13: VPNTunnelManager 和 TunnelProviderBridge

**Files:**
- Create: `Sources/Riptide/VPN/TunnelProviderBridge.swift`
- Modify: `Sources/Riptide/VPN/VPNTunnelManager.swift`

- [ ] **Step 1: 创建 TunnelProviderBridge**

```swift
import Foundation
import NetworkExtension

/// Bidirectional communication channel between the main app and the tunnel extension.
public actor TunnelProviderBridge {
    private var connection: NETunnelProviderSession?

    public init() {}

    /// Connect to a running tunnel extension.
    public func connect(to bundleID: String = "com.riptide.tunnel") throws {
        guard let manager = NETunnelProviderManager.allManagers().values.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == bundleID
        }) else {
            throw TunnelBridgeError.managerNotFound
        }
        connection = manager.connection as? NETunnelProviderSession
    }

    /// Send a command to the tunnel extension.
    public func sendCommand(_ command: TunnelCommand) async throws {
        guard let connection = connection else {
            throw TunnelBridgeError.notConnected
        }
        let data = try JSONEncoder().encode(command)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                try connection.sendProviderMessage(data) { response in
                    continuation.resume()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Receive events from the tunnel extension.
    public func receiveEvents() -> AsyncStream<TunnelEvent> {
        AsyncStream { continuation in
            // Register with the extension's event publisher
        }
    }
}

public enum TunnelCommand: Codable {
    case start(profile: Data)
    case stop
    case switchProfile(Data)
    case selectProxy(groupID: String, nodeName: String)
}

public enum TunnelEvent: Codable {
    case stateChanged(TunnelState)
    case trafficUpdated(up: UInt64, down: UInt64)
    case logEntry(String)
    case error(String)
}

public enum TunnelBridgeError: Error {
    case managerNotFound
    case notConnected
}
```

- [ ] **Step 2: 更新 VPNTunnelManager 接入 NETunnelProviderManager**

将 `VPNTunnelManager.swift` 从 stub 实现为真实实现，使用 `NETunnelProviderManager` 管理 VPN 配置生命周期。

- [ ] **Step 3: Commit**

```bash
git add Sources/Riptide/VPN/TunnelProviderBridge.swift Sources/Riptide/VPN/VPNTunnelManager.swift
git commit -m "feat(tunnel): implement TunnelProviderBridge and VPNTunnelManager"
```


---

## Phase 6: UI

### Task 14: 重写 AppViewModel

**Files:**
- Modify: `Sources/RiptideApp/AppViewModel.swift`

完全重写，替换现有的 mock 实现。

- [ ] **Step 1: 定义 Display 模型**

```swift
import Foundation
import Observation

// --- Display models (UI-only, derived from Core models) ---

public struct ProxyNodeDisplay: Identifiable {
    public let id: String
    public let name: String
    public let kind: ProxyKind
    public let delayMs: Int?
    public let isSelected: Bool
    public let status: ProxyStatus

    public enum ProxyStatus {
        case available, timeout, error
    }
}

public struct ProxyGroupDisplay: Identifiable {
    public let id: String
    public let name: String
    public let kind: ProxyGroupKind
    public let nodes: [ProxyNodeDisplay]
    public let selectedNodeName: String?
}

public struct ConnectionInfo: Identifiable {
    public let id: UUID
    public let host: String
    public let port: Int
    public let protocol_: String
    public let proxyName: String
    public let connectionCount: Int
}

public struct RuleMatchLog: Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let domain: String
    public let matchedRule: String
    public let resolvedNode: String
}

public struct LogEntry: Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
}

public enum LogLevel: String, CaseIterable {
    case all, info, warn, error
}
```

- [ ] **Step 2: 重写 AppViewModel**

```swift
import Foundation
import Observation
import Riptide

@MainActor
@Observable
public final class AppViewModel: ObservableObject {
    // Tunnel state
    public private(set) var tunnelState: TunnelState = .stopped
    public private(set) var proxyMode: ProxyMode = .rule
    public private(set) var connectionMode: ConnectionMode = .systemProxy

    // Config
    public private(set) var profiles: [Profile] = []
    public private(set) var activeProfile: Profile?
    public private(set) var subscriptions: [Subscription] = []

    // Proxies
    public private(set) var proxyGroups: [ProxyGroupDisplay] = []
    public private(set) var allProxies: [ProxyNodeDisplay] = []

    // Traffic
    public private(set) var currentSpeed: (up: Int64, down: Int64) = (0, 0)
    public private(set) var totalTraffic: (up: Int64, down: Int64) = (0, 0)
    public private(set) var activeConnections: [ConnectionInfo] = []

    // Rules
    public private(set) var rules: [ProxyRule] = []
    public private(set) var ruleMatches: [RuleMatchLog] = []

    // Logs
    public private(set) var logEntries: [LogEntry] = []
    public var logLevel: LogLevel = .all

    // Errors
    public private(set) var lastError: String?

    // Private
    private let controlChannel: InProcessTunnelControlChannel
    private let bridge: TunnelProviderBridge?
    private var statsTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var runtime: LiveTunnelRuntime?

    public init() {
        // For now, use in-process channel
        let manager = TunnelLifecycleManager(runtime: LiveTunnelRuntime(
            proxyDialer: TCPTransportDialer(),
            directDialer: TCPTransportDialer(),
            geoIPResolver: .none,
            dnsPipeline: DNSPipeline(dnsPolicy: DNSPolicy())
        ))
        self.controlChannel = InProcessTunnelControlChannel(lifecycleManager: manager)
        self.bridge = nil  // Will be non-nil when TUN mode is configured
    }

    // MARK: - Actions

    public func toggleTunnel() async {
        if tunnelState == .running {
            await stop()
        } else {
            await start()
        }
    }

    public func start() async {
        guard let profile = activeProfile else {
            lastError = "No active profile"
            return
        }
        do {
            let response = try await controlChannel.send(.start(profile))
            guard case .ack = response else { throw AppControlError.startFailed }
            tunnelState = .running
            await refreshStatus()
            startStatsPolling()
        } catch {
            lastError = String(describing: error)
        }
    }

    public func stop() async {
        do {
            let response = try await controlChannel.send(.stop)
            guard case .ack = response else { throw AppControlError.stopFailed }
            tunnelState = .stopped
            stopStatsPolling()
        } catch {
            lastError = String(describing: error)
        }
    }

    public func switchMode(_ mode: ProxyMode) async {
        proxyMode = mode
        // Update profile mode and send update command
    }

    public func switchConnectionMode(_ mode: ConnectionMode) async {
        connectionMode = mode
        // Switch between system proxy and TUN
    }

    public func selectProxy(groupID: String, nodeName: String) async {
        // Persist selection and notify group resolver
    }

    public func testDelay(groupID: String? = nil) async {
        // Run health check for all or specified group
    }

    public func importConfig(url: URL) async {
        // Import local YAML or remote URL
    }

    public func addSubscription(url: String, name: String) async {
        // Fetch and parse subscription
    }

    private func refreshStatus() async {
        // Pull status from control channel
    }

    private func startStatsPolling() {
        statsTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await refreshStatus()
            }
        }
    }

    private func stopStatsPolling() {
        statsTask?.cancel()
        statsTask = nil
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/RiptideApp/AppViewModel.swift
git commit -m "feat(app): rewrite AppViewModel with full data layer"
```

---

### Task 15: 重写 RiptideApp — 状态栏 + TabView

**Files:**
- Modify: `Sources/RiptideApp/RiptideApp.swift`
- Create: `Sources/RiptideApp/Views/` (5 个 Tab View)

- [ ] **Step 1: 重写 RiptideApp.swift**

```swift
import SwiftUI
import Riptide

@main
struct RiptideApp: App {
    @State private var appVM = AppViewModel()
    @State private var showMainWindow = false

    var body: some Scene {
        // No default window — all interaction via status bar
        // For development/debug, keep a hidden window
        #if DEBUG
        WindowGroup {
            MainTabView(vm: appVM)
        }
        #endif

        // Status bar managed via NSApplication lifecycle
        Settings {
            StatusBarManager(vm: appVM)
        }
    }
}

// MARK: - Status Bar Manager

class StatusBarController {
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private let vm: AppViewModel

    init(vm: AppViewModel) {
        self.vm = vm
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()

        buildMenu()
        updateStatusItem()
    }

    func buildMenu() {
        // Connection status section
        // Mode selection section
        // Proxy groups section
        // Open main window
        // Quit
    }

    func updateStatusItem() {
        // Update icon color based on tunnelState
        // green = running, gray = stopped, yellow = starting
    }
}
```

- [ ] **Step 2: 创建 MainTabView**

`Sources/RiptideApp/Views/MainTabView.swift`:

```swift
import SwiftUI

struct MainTabView: View {
    @Bindable var vm: AppViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ConfigTabView(vm: vm)
                .tabItem { Label("配置", systemImage: "doc.text") }
                .tag(0)

            ProxyTabView(vm: vm)
                .tabItem { Label("代理", systemImage: "server.rack") }
                .tag(1)

            TrafficTabView(vm: vm)
                .tabItem { Label("流量", systemImage: "chart.bar") }
                .tag(2)

            RulesTabView(vm: vm)
                .tabItem { Label("规则", systemImage: "list.bullet") }
                .tag(3)

            LogTabView(vm: vm)
                .tabItem { Label("日志", systemImage: "terminal") }
                .tag(4)
        }
        .tint(Color(hex: "#0fbcf9"))
        .preferredColorScheme(.dark)
    }
}
```

- [ ] **Step 3: 创建各 Tab View**

创建以下文件，每个实现对应的 UI：
- `Sources/RiptideApp/Views/ConfigTabView.swift`
- `Sources/RiptideApp/Views/ProxyTabView.swift`
- `Sources/RiptideApp/Views/TrafficTabView.swift`
- `Sources/RiptideApp/Views/RulesTabView.swift`
- `Sources/RiptideApp/Views/LogTabView.swift`

每个 Tab View 遵循以下深色主题规范：
- 背景: `#1a1a2e` → `#16213e` 渐变（通过 SwiftUI 的 `LinearGradient` 或背景修饰符实现）
- 卡片: `.ultraThinMaterial` 毛玻璃
- 圆角: `12` 像素
- 强调色: `#0fbcf9` (连接蓝), `#0be881` (绿色), `#fd7272` (红色)

示例 ProxyTabView 骨架：

```swift
struct ProxyTabView: View {
    @Bindable var vm: AppViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(vm.proxyGroups) { group in
                    ProxyGroupCard(group: group, vm: vm)
                }
            }
            .padding()
        }
        .background(Color(hex: "#1a1a2e"))
        .toolbar {
            ToolbarItem {
                Button("全部延迟测试") {
                    Task { await vm.testDelay() }
                }
            }
        }
    }
}

struct ProxyGroupCard: View {
    let group: ProxyGroupDisplay
    @Bindable var vm: AppViewModel
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(Color(hex: "#0fbcf9"))
                Text(group.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(group.kind.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }

            if isExpanded {
                ForEach(group.nodes) { node in
                    ProxyNodeRow(node: node) {
                        Task {
                            await vm.selectProxy(groupID: group.id, nodeName: node.name)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

- [ ] **Step 4: 验证编译**

Run: `swift build --filter RiptideApp`
Expected: 编译成功

- [ ] **Step 5: Commit**

```bash
git add Sources/RiptideApp/RiptideApp.swift Sources/RiptideApp/AppViewModel.swift Sources/RiptideApp/Views/
git commit -m "feat(app): rewrite RiptideApp with status bar and 5-tab main window"
```


---

## 依赖关系总览

```
Phase 1 ──→ Phase 4 (GroupResolver 需要 ProxyGroup 模型)
    │
    └─→ Phase 2 ──→ Phase 3 ──→ Phase 4 ──→ Phase 5 (TUN)
                                              │
Phase 1 (DNS 解析基础) ───────────────────────┘
                                              │
Phase 6 (UI 骨架可在任何时候开始，数据绑定等 Phase 4 后接入)
```

**并行机会:**
- Phase 1 Task 1, 2, 3 可并行（不同文件）
- Phase 2 Task 4, 5 可并行（不同文件）
- Phase 6 UI 骨架可在 Phase 1 开始后同步进行

**总任务数: 15 tasks**

**建议执行顺序:**
1. Phase 1 Task 1 → Task 2 → Task 3（模型和解析）
2. Phase 2 Task 4 → Task 5 → Task 6（传输层）
3. Phase 3 Task 7 → Task 8 → Task 9（协议接入）
4. Phase 4 Task 10 → Task 11（运行时集成）
5. Phase 5 Task 12 → Task 13（TUN 模式）
6. Phase 6 Task 14 → Task 15（UI）

