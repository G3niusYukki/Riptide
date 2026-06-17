# Riptide 技术债清理与改进计划

> 基于 v2.7.0 (commit ca216a8) 真实代码扫描生成
> 日期: 2026-06-17

## 1. 技术债清单（按优先级）

### P0 — 死代码：SingBoxRuntimeManager + SingBoxDownloader

**现状:**
- `Sources/Riptide/SingBox/SingBoxRuntimeManager.swift` — 78行骨架代码
- `Sources/Riptide/SingBox/SingBoxDownloader.swift` — 31行，硬编码 `PLACEHOLDER_SHA256`
- 两文件标注 "v2.4.1 Phase 1 skeleton"，`start()` 直接 `throw .notImplemented`
- **实际运行时从未被调用** — grep 确认无任何外部引用
- 真正的 sing-box 集成走 `GoCoreTunnelRuntime` + 内进程 `libgocore.a`

**风险:** `PLACEHOLDER_SHA256` 是安全隐患 — 若未来有人误调用 `SingBoxDownloader`，二进制完整性校验形同虚设

**方案:** 直接删除两个文件 + 相关测试。sing-box 的运行时管理已由 `GoCoreTunnelRuntime` 和 `TunDaemonController` 完全接管

**涉及文件:**
- `Sources/Riptide/SingBox/SingBoxRuntimeManager.swift` → 删除
- `Sources/Riptide/SingBox/SingBoxDownloader.swift` → 删除
- `Tests/RiptideTests/` 下相关测试（如有）→ 删除
- 检查 `EngineRouter` 是否有 `.singbox` 分支引用 → 清理

---

### P0 — AppViewModel God Object 拆分

**现状:**
- `Sources/RiptideApp/AppViewModel.swift` — 1590 行
- 超过 SwiftLint `file_length` error 阈值 (1500)
- 顶部 `swiftlint:disable file_length type_body_length` 压制了两个 error
- 一个文件包含 **8 个模型定义 + 主 ViewModel + 1 个协议扩展**:

| 行范围 | 内容 | 应提取到 |
|---|---|---|
| 11-34 | `Profile`, `ProfileSource` | `Sources/RiptideApp/Models/AppModels.swift` |
| 39-62 | `SubscriptionDisplay` | 同上 |
| 66-81 | `RuleSetDisplay` | 同上 |
| 84-97 | `ProxyNodeDisplay` | 同上 |
| 99-105 | `ProxyGroupDisplay` | 同上 |
| 107-167 | `ConnectionInfo` | 同上 |
| 161-167 | `RuleMatchLog` | 同上 |
| 169-192 | `ConnectionMode` | 同上 |
| 194-1577 | `AppViewModel` | 保留在 `AppViewModel.swift` |
| 1579-1590 | `MihomoDownloadProgressDelegate` ext | `Sources/RiptideApp/Extensions/` |

**方案:**
1. 创建 `Sources/RiptideApp/Models/AppModels.swift`，迁移 8 个模型定义
2. 创建 `Sources/RiptideApp/Extensions/AppViewModel+DownloadProgress.swift`，迁移协议扩展
3. 删除 `AppViewModel.swift` 第 1 行的 `swiftlint:disable`
4. 确保 `AppViewModel.swift` 降到 1400 行以下

**风险:** 低 — 纯文件搬迁，不改逻辑。编译器会捕获遗漏的 import

---

### P1 — 过期 Task 注释 (NOTE Task 16/17)

**现状:** 6 处 `NOTE(Task 16/17)` 注释，但 Task 16/17 **已经完成**:
- `ClashConfigParser.swift:153` — reality/anytls/ssh 已在解析
- `ClashConfigParser.swift:154` — 注释说 "parse once data fields land"，但 195-198 行已在读 realityServerName/realityPublicKey 等
- `ProxyConnector.swift:68` — 注释说 "wire up connectors"，但 35-36 行已有 VLESS+Reality 连接逻辑
- `EditableProxyNode.swift:150, 262` — 注释说 "sensible defaults once data fields land"
- `ProxyNodeValidator.swift:124` — 注释说 "add field validation"
- `ConfigMerger.swift:203` — 注释说 "map to mihomo type string once data fields land"

**方案:** 逐条审查，删除已完成任务注释。对仍缺的验证逻辑，要么补上，要么改成明确的 `// TODO:` 标注

**涉及文件:** 6 个，每个改 1-3 行

---

### P1 — OverrideMerger 过期注释

**现状:**
- `OverrideMerger.swift:42` — `// MARK: - Map merge (stub for Task 4; full impl in Task 5+)`
- `OverrideMerger.swift:46` — `// nested maps recurse. meta.replace / removed: handled in Task 6+.`
- 但代码**已完全实现**: `mergeMaps`, `mergeValue`, `mergeLists`, `applyRemovals` 全在，`replaceMode` 和 `removedList` 都在用

**方案:** 更新注释为描述实际行为，删除 Task 引用

---

### P1 — AGENTS.md 文档失真

**现状:**
| 字段 | AGENTS.md 声称 | 实际 |
|---|---|---|
| 测试数 | 593 | 968 test 函数 |
| 测试套件 | 93 | 103 文件 |
| 版本 | v2.4.0 | v2.7.0 |
| SwiftLint | "strict is green on new code" | 4 处 disable |

**方案:**
1. 更新 §1 "Current state" 的版本号和测试数
2. 更新 §7 Tests 的文件/测试数
3. 在 §13 Validation Expectations 中加入 "下载包 smoke test" 要求（教训来自 v2.1-v2.6 启动崩溃）

---

### P2 — GatewayEnabler 半成品

**现状:**
- `Sources/Riptide/AppShell/GatewayEnabler.swift` — 后端完整实现（IP转发、NAT、DHCP via pfctl）
- `Sources/RiptideApp/Views/Settings/SettingsTabView.swift:373` — UI 只是占位符 `GatewaySettingsPlaceholderView`
- SettingsTabView:59 注释 `// Gateway settings placeholder — backend ready`

**方案（二选一）:**
- **A)** 完成 Gateway UI — 工作量较大，需设计完整的网关设置界面
- **B)** 标记为实验性 — 在 UI 上加 🟡 badge，注释标明 "v2.7.0: backend ready, UI pending"

**建议:** 选 B，除非 Gateway 模式是近期路线图优先项

---

### P2 — SceneEditorView 假数据

**现状:**
- `Sources/RiptideApp/Views/Scenes/SceneEditorView.swift:160`
- `currentSSID = "MyHomeWiFi"` — 硬编码假 SSID
- `detectedSSIDs = ["MyHomeWiFi", "OfficeWiFi", ...]` — 假列表

**方案:** 接入真实 SSID 检测（CoreWLAN `CWWiFiClient`），或至少用 `#if DEBUG` 包裹假数据

---

### P3 — ModeCoordinator uptime 未实现

**现状:**
- `ModeCoordinator.swift:235` — `uptimeSeconds: nil // uptime tracking not yet implemented`

**方案:** 在 ModeCoordinator actor 中加一个 `connectedAt: Date?` 属性，启动时记录，返回 `Date.now.timeIntervalSince(connectedAt)`

---

### P3 — HTTP2 Transport 未实现

**现状:**
- `TransportConnectionPool.swift:42` — `// HTTP2 transport not yet implemented; fall back to TLS`

**方案:** 低优先级 — sing-box/mihomo 原生处理 HTTP2 gRPC，纯 Swift 引擎的 HTTP2 transport 不是必需。保留注释即可，或标记为 "won't fix — delegated to core"

---

### P3 — WireGuard 原生传输

**现状:**
- `ProxyConnector.swift:301` — 抛错 "Use mihomo runtime for WireGuard nodes"

**方案:** 这是设计决策而非技术债 — WireGuard Noise IK 握手复杂，交给 mihomo。保持现状，确保文档明确

---

## 2. 执行计划

### Phase 1 — 清理（1-2 小时，低风险）

| 步骤 | 文件 | 操作 | 预计行数变化 |
|---|---|---|---|
| 1.1 | `SingBoxRuntimeManager.swift` | 删除 | -78 |
| 1.2 | `SingBoxDownloader.swift` | 删除 | -31 |
| 1.3 | 搜索 `SingBoxRuntimeManager` 引用 | 清理 EngineRouter 等 | -~20 |
| 1.4 | 6 个 NOTE(Task 16/17) 注释 | 更新/删除 | ~0 |
| 1.5 | `OverrideMerger.swift:42,46` | 更新注释 | ~0 |
| 1.6 | `ModeCoordinator.swift:235` | 实现 uptime | +5 |

**验证:** `swift build && swift test`

---

### Phase 2 — AppViewModel 拆分（2-3 小时，中风险）

| 步骤 | 操作 |
|---|---|
| 2.1 | 创建 `Sources/RiptideApp/Models/AppModels.swift` |
| 2.2 | 迁移 8 个模型 struct/enum（Profile, ProfileSource, SubscriptionDisplay, RuleSetDisplay, ProxyNodeDisplay, ProxyGroupDisplay, ConnectionInfo, RuleMatchLog, ConnectionMode） |
| 2.3 | 创建 `Sources/RiptideApp/Extensions/AppViewModel+DownloadProgress.swift` |
| 2.4 | 迁移 MihomoDownloadProgressDelegate 扩展 |
| 2.5 | 删除 `AppViewModel.swift:1` 的 swiftlint:disable |
| 2.6 | 更新 Package.swift 的 resources（如有需要） |

**验证:** `swift build && swift test && swiftlint lint --strict Sources/RiptideApp/AppViewModel.swift Sources/RiptideApp/Models/AppModels.swift`

---

### Phase 3 — 文档同步（30 分钟，低风险）

| 步骤 | 操作 |
|---|---|
| 3.1 | 更新 AGENTS.md §1 版本号 v2.4.0 → v2.7.0 |
| 3.2 | 更新 AGENTS.md §1 测试数 593→968, 93→103 |
| 3.3 | 更新 AGENTS.md §7 同步 |
| 3.4 | 在 §13 加入 "release 下载包 smoke test" 要求 |
| 3.5 | 更新 CHANGELOG.md 记录本次清理 |

---

### Phase 4 — 可选改进（按需）

| 项目 | 工作量 | 价值 |
|---|---|---|
| GatewayEnabler UI 完成 | 1-2 天 | 中 — 取决于路线图 |
| SceneEditorView 真实 SSID | 2 小时 | 中 — 用户体验 |
| 协议层测试补齐 | 1-2 天 | 高 — 14 种协议测试薄 |
| 发布流程 smoke test | 3 小时 | 高 — 防止 v2.1-v2.6 崩溃重演 |

---

## 3. 验证清单

每个 Phase 完成后:

```
swift build                    # 编译通过
swift test                     # 全部测试通过
swiftlint lint --strict        # 0 violations on changed files
git diff --stat                # 确认变更范围符合预期
```

Phase 4 额外:
```
swift run RiptideApp           # app 能启动
./Scripts/build-release.sh     # release 包能构建
```

---

## 4. 不做的事项

- **不碰 MARK: 注释** — 622 个 MARK: 是 Swift 代码组织约定，不是技术债
- **不拆 ClashConfigParser (1000行)** — 虽然大，但逻辑内聚（YAML 解析），拆开反而降低可读性
- **不拆 MihomoRuntimeManager (883行)** — 同上，进程管理逻辑集中是合理的
- **不补 HTTP2 transport** — 已委托给 sing-box/mihomo core
- **不补 WireGuard 原生** — 设计决策，非技术债
