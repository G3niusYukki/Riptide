# Riptide 改进计划 (对标 Clash Verge Rev)

> 目标：构建一个可真实运行的 macOS 原生代理客户端，实现 Clash Verge Rev 的核心基础功能。

---

## 1. 现状分析

### 1.1 已完成的基础架构
- ✅ Swift 6 + SwiftUI 技术栈
- ✅ mihomo 核心集成（通过 XPC + 特权助手）
- ✅ 配置解析（Clash YAML）
- ✅ 代理协议模型：SS, VMess, VLESS, Trojan, Hysteria2, HTTP, SOCKS5
- ✅ 规则引擎基础（DOMAIN, IP-CIDR, GEOIP, RULE-SET 等）
- ✅ 基础 UI 框架（标签页、代理选择、流量显示）

### 1.2 关键功能状态（vs Clash Verge Rev）

| 功能 | Clash Verge Rev | Riptide 现状 |
|------|----------------|-------------|
| **延迟测试** | 完整 TCP 延迟测试 | ✅ 通过 mihomo API，ProxyTabView 颜色编码 |
| **订阅管理** | 自动更新 + 多订阅 | ✅ SubscriptionManager + 5分钟自动更新调度器 |
| **TUN 模式** | 稳定运行 | ✅ mihomo gvisor + 10秒健康监控 + 自动恢复 |
| **系统代理守卫** | 自动恢复 | ✅ SystemProxyGuard + SystemProxyMonitor（5秒检测） |
| **代理组策略** | url-test/fallback 真实工作 | ✅ 通过 mihomo API，延迟结果追踪 |
| **规则集自动更新** | 定时下载更新 | ⚠️ 框架存在，未集成 |
| **可视化编辑器** | 节点/规则可视化编辑 | ⚠️ 仅 YAML 导入 |
| **日志与诊断** | 实时日志 + 流量图表 | ✅ 实时轮询（1秒），TrafficChartView + ConnectionListView |
| **多语言支持** | 完整国际化 | ✅ 4语言：en, zh-Hans, ja, ru |
| **模式切换** | 平滑切换 | ✅ switchMode() 原子化切换 + 500ms 冷却 |
| **首次引导** | 引导式安装 | ✅ 4步向导（OnboardingView） |
| **SMAppService** | 现代 API | ✅ macOS 13+ SMAppService + SMJobBless fallback |

---

## 2. 改进路线图

### Phase 1: 核心功能闭环 ✅ 已完成
**目标：实现可真实运行的基础代理客户端**

#### Week 1: 延迟测试 + 代理组策略 ✅
- [x] 实现 TCP 延迟测试（通过 mihomo API `/proxies/{name}/delay`）
- [x] 代理组 url-test 自动测试 + 自动选择
- [x] 代理组 fallback 健康检查
- [x] UI 显示延迟数值 + 颜色标识

#### Week 2: 订阅管理 + 自动更新 ✅
- [x] 订阅源持久化存储
- [x] 定时自动更新（每 5 分钟检查）
- [x] 更新通知 + 冲突处理
- [x] 多订阅源合并管理

#### Week 3: 系统代理守卫 + TUN 稳定化 ✅
- [x] 系统代理状态监控（5秒间隔）
- [x] 代理被外部修改时自动恢复
- [x] TUN 模式错误处理（10秒健康监控 + 自动重启）
- [x] 首次安装引导流程

### Phase 2: 用户体验提升
**目标：达到可用产品的体验标准**

#### 可视化编辑器 ⬜ 未开始
- [ ] 节点信息可视化编辑面板
- [ ] 规则可视化编辑（拖拽/表格）
- [ ] 配置 Merge 功能（基础版）
- [ ] 配置导入预览

#### 日志与诊断 ✅ 已完成
- [x] 实时日志流（1秒轮询）
- [x] 日志级别过滤
- [x] 基础流量图表（Swift Charts — TrafficChartView）
- [x] 连接列表实时显示（ConnectionListView — 搜索/关闭）

### Phase 3: 高级功能
- [x] WebDav 配置同步
- [x] 多语言国际化（4语言）
- [x] 主题颜色自定义（System / Light / Dark）
- [x] 托盘图标自定义
- [ ] 脚本配置支持（基础 JavaScript 引擎 — 框架存在）

---

## 3. 已完成的详细实现

### 3.1 延迟测试 ✅

**实现方式：** 通过 mihomo REST API（非库内 HealthChecker）

```swift
// ModeCoordinator 中实现
public func testProxyDelay(proxyName: String, url: String?, timeout: Int) async -> Int?
public func testAllProxies(proxies: [ProxyNode]) async
public func healthResult(for name: String) -> HealthResult?
```

**UI：** ProxyTabView 已实现
- 延迟颜色：绿色(<100ms) / 黄色(<300ms) / 红色(>300ms)
- "延迟测试" 工具栏按钮
- 结果存储在 ModeCoordinator 中

### 3.2 订阅管理 ✅

**数据模型：**
```swift
public struct Subscription: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var url: String
    public var autoUpdate: Bool
    public var updateInterval: TimeInterval
    public var lastUpdated: Date?
    public var lastError: String?
}
```

**功能：**
- 订阅 CRUD（增删改查）
- `SubscriptionUpdateScheduler` 定时更新（5分钟检查间隔）
- 更新冲突处理
- 多订阅源合并
- UserDefaults 持久化

### 3.3 系统代理守卫 ✅

**实现方案：**
```swift
public actor SystemProxyGuard {
    func enable(expectedHTTPPort: Int, expectedSOCKSPort: Int?) async throws
    func disable()
    func checkForViolation() -> Bool
    func restore() async throws
}

public actor SystemProxyMonitor {
    func start(interval: TimeInterval, guard: SystemProxyGuard)
    func stop()
}
```

**集成：** ModeCoordinator 生命周期中自动启动/停止
- 注入 `systemProxyController` 时启用守卫
- 5秒间隔检测 + 自动恢复
- 无 controller 注入时优雅跳过（测试安全）

### 3.4 TUN 模式稳定化 ✅

**已实现：**
1. ✅ TUN 接口健康监控（10秒间隔 `verifyTUNInterface()`）
2. ✅ 自动恢复（`attemptTUNRecovery()` — 停止 → 2秒冷却 → 重启）
3. ✅ 原子模式切换（`switchMode()` — 500ms 冷却）
4. ✅ DNS 缓存清理加固（返回成功/失败 + 日志）
5. ✅ TUN 配置增强（LAN 路由排除）
6. ✅ 首次安装引导（OnboardingView + SMAppService）

---

## 4. 技术债务清理

### 4.1 当前警告修复
- [x] `TunnelProviderMessages.swift` - 自引用 import 警告
- [x] `SMJobBlessManager.swift` - deprecated SMJobBless API（已迁移到 SMAppService）
- [ ] `StatusBarController.swift` - deprecated `view` API
- [ ] Swift 6 strict concurrency warnings（`#SendableClosureCaptures`）

### 4.2 架构改进
- [ ] 统一错误处理（RiptideError 枚举）
- [ ] 配置文件备份/回滚机制
- [ ] 更好的日志系统（统一日志接口）

---

## 5. 剩余优先级

### 高优先级
1. 可视化配置编辑器（节点/规则）
2. 规则集自动更新
3. 清理 Swift 6 strict concurrency warnings

### 中优先级
1. 统一错误处理
2. 配置文件备份/回滚

### 低优先级
1. 脚本配置支持
2. Release workflow DMG/MSI glob 路径修复

---

## 6. 验收标准

**Phase 1 完成标准** ✅ 全部达成：
- [x] 可以一键测试所有节点延迟
- [x] url-test 组自动选择延迟最低节点
- [x] 订阅自动更新，更新失败有通知
- [x] 系统代理被其他软件修改后自动恢复
- [x] TUN 模式健康监控 + 自动恢复

**Phase 2 完成标准** ✅ 大部分达成：
- [ ] 可以可视化编辑节点信息（不改 YAML）— 未实现
- [x] 实时流量图表
- [x] 连接列表实时刷新
- [x] 日志可以按级别过滤

---

## 附录：Clash Verge Rev 功能清单参考

### 核心功能（已实现）✅
- [x] 代理节点管理
- [x] 配置导入导出
- [x] System Proxy 模式 + 系统代理守卫
- [x] TUN 模式 + 自动恢复
- [x] 延迟测试（TCP via mihomo API）
- [x] 订阅自动更新
- [x] 流量统计图表
- [x] 实时日志
- [x] 连接管理
- [x] 多语言国际化
- [x] 主题系统
- [x] WebDav 同步
- [x] 首次启动引导

### 需要追赶的功能
- [ ] 可视化编辑器
- [ ] 配置 Merge/Script
- [ ] 规则集自动更新
