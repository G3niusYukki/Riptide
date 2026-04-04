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

### 1.2 关键功能缺失（vs Clash Verge Rev）

| 功能 | Clash Verge Rev | Riptide 现状 |
|------|----------------|-------------|
| **延迟测试** | 完整 TCP 延迟测试 | 仅 UI stub |
| **订阅管理** | 自动更新 + 多订阅 | 基础解析，无自动更新 |
| **TUN 模式** | 稳定运行 | 框架存在，未真实测试 |
| **系统代理守卫** | 自动恢复 | 无守卫逻辑 |
| **代理组策略** | url-test/fallback 真实工作 | 仅配置解析 |
| **规则集自动更新** | 定时下载更新 | 框架存在，未集成 |
| **可视化编辑器** | 节点/规则可视化编辑 | 仅 YAML 导入 |
| **日志与诊断** | 实时日志 + 流量图表 | 基础日志 stub |
| **多语言支持** | 完整国际化 | 仅中文 |

---

## 2. 改进路线图

### Phase 1: 核心功能闭环（2-3 周）
**目标：实现可真实运行的基础代理客户端**

#### Week 1: 延迟测试 + 代理组策略
- [ ] 实现 TCP 延迟测试（通过 mihomo API `/proxies/{name}/delay`）
- [ ] 代理组 url-test 自动测试 + 自动选择
- [ ] 代理组 fallback 健康检查
- [ ] UI 显示延迟数值 + 颜色标识

#### Week 2: 订阅管理 + 自动更新
- [ ] 订阅源持久化存储
- [ ] 定时自动更新（每小时/每天）
- [ ] 更新通知 + 冲突处理
- [ ] 多订阅源合并管理

#### Week 3: 系统代理守卫 + TUN 稳定化
- [ ] 系统代理状态监控
- [ ] 代理被外部修改时自动恢复
- [ ] TUN 模式错误处理完善
- [ ] 首次安装引导流程

### Phase 2: 用户体验提升（2-3 周）
**目标：达到可用产品的体验标准**

#### Week 4-5: 可视化编辑器
- [ ] 节点信息可视化编辑面板
- [ ] 规则可视化编辑（拖拽/表格）
- [ ] 配置 Merge 功能（基础版）
- [ ] 配置导入预览

#### Week 6: 日志与诊断
- [ ] 实时日志流（WebSocket 或轮询）
- [ ] 日志级别过滤
- [ ] 基础流量图表（Swift Charts）
- [ ] 连接列表实时显示

### Phase 3: 高级功能（可选/长期）
- [ ] 脚本配置支持（基础 JavaScript 引擎）
- [ ] WebDav 配置同步
- [ ] 多语言国际化
- [ ] 主题颜色自定义
- [ ] 托盘图标自定义

---

## 3. 详细任务分解

### 3.1 延迟测试实现

**技术方案：**
```swift
// 1. 通过 mihomo API 测试延迟
MihomoAPIClient.testProxyDelay(name: String, url: String?, timeout: Int) async throws -> Int

// 2. 代理组自动测试
actor ProxyGroupManager {
    func testAllProxies(in group: String) async -> [String: Int]
    func autoSelectBestProxy(in group: String) async
}

// 3. 定时健康检查（url-test/fallback）
actor HealthCheckScheduler {
    func startPeriodicCheck(group: ProxyGroup, interval: TimeInterval)
}
```

**UI 更新：**
- ProxyTabView 添加延迟显示
- 延迟颜色：绿色(<100ms) / 黄色(<300ms) / 红色(>300ms)
- 一键测试所有节点按钮

### 3.2 订阅管理实现

**数据模型：**
```swift
public struct Subscription: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var url: String
    public var autoUpdate: Bool
    public var updateInterval: TimeInterval  // 默认 3600s
    public var lastUpdated: Date?
    public var lastError: String?
}
```

**功能点：**
- 订阅 CRUD（增删改查）
- 定时更新（BackgroundTaskScheduler）
- 更新冲突处理（同名节点覆盖/保留策略）
- 多订阅合并到同一 Profile

### 3.3 系统代理守卫

**实现方案：**
```swift
actor SystemProxyGuard {
    private var isEnabled: Bool = false
    private var expectedProxy: ProxySettings?
    
    func enableGuard(settings: ProxySettings) {
        isEnabled = true
        expectedProxy = settings
        startMonitoring()
    }
    
    private func startMonitoring() {
        // 每 5 秒检查系统代理设置
        // 如果被外部修改，自动恢复
    }
}
```

### 3.4 TUN 模式稳定化

**需要完善的点：**
1. 错误处理细化（权限不足/内核未安装等具体错误）
2. 首次安装引导（SMJobBless 流程优化）
3. TUN 模式与系统代理切换的稳定性
4. 断网/重连自动恢复

---

## 4. 技术债务清理

### 4.1 当前警告修复
- [x] `TunnelProviderMessages.swift` - 自引用 import 警告
- [ ] `StatusBarController.swift` - deprecated `view` API
- [ ] `SMJobBlessManager.swift` - deprecated SMJobBless API（迁移到 SMAppService）

### 4.2 架构改进
- [ ] 统一错误处理（RiptideError 枚举）
- [ ] 配置文件备份/回滚机制
- [ ] 更好的日志系统（统一日志接口）

---

## 5. 优先级建议

### 立即执行（本周）
1. ✅ 修复编译错误
2. 实现延迟测试 API 调用
3. 代理组显示延迟数值

### 高优先级（本月）
1. 订阅自动更新
2. 系统代理守卫
3. 基础流量统计 UI

### 中优先级（下月）
1. 可视化配置编辑器
2. 日志流实时显示
3. TUN 模式稳定性

### 低优先级（长期）
1. 国际化
2. 主题系统
3. WebDav 同步

---

## 6. 验收标准

**Phase 1 完成标准：**
- [ ] 可以一键测试所有节点延迟
- [ ] url-test 组自动选择延迟最低节点
- [ ] 订阅每天自动更新，更新失败有通知
- [ ] 系统代理被其他软件修改后自动恢复
- [ ] TUN 模式可以稳定运行 24 小时

**Phase 2 完成标准：**
- [ ] 可以可视化编辑节点信息（不改 YAML）
- [ ] 实时流量图表
- [ ] 连接列表实时刷新
- [ ] 日志可以按级别过滤

---

## 附录：Clash Verge Rev 功能清单参考

### 核心功能（已实现）
- [x] 代理节点管理
- [x] 配置导入导出
- [x] System Proxy 模式
- [x] TUN 模式（基础）

### 需要追赶的功能
- [ ] 延迟测试（TCP）
- [ ] 订阅自动更新
- [ ] 系统代理守卫
- [ ] 流量统计图表
- [ ] 实时日志
- [ ] 连接管理
- [ ] 可视化编辑器
- [ ] 配置 Merge/Script
- [ ] WebDav 同步
