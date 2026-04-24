# Riptide 竞品对齐路线图 (2026 Q2–Q3)

> **目标**：在 3–6 个月内，让 Riptide 在核心功能与 UX 上追平 **Clash Verge Rev**，并吸收 **Hiddify Next** 的跨平台与协议广度优势，同时发挥 Swift 原生引擎的差异化价值。
>
> **范围**：对齐功能 (Feature Parity) + UX/UI 现代化。不含移动端 (iOS/Android)、Linux 原生端 —— 这些归入长期愿景 (6M+)。
>
> **前置文档**：
> - `docs/IMPROVEMENT-PLAN.md` (对标 Clash Verge Rev，4 月初版)
> - `docs/improvement-plan-design-2026.md` (sing-box 双内核架构决策)
> - `ROADMAP.md` (早期 3 阶段基础路线图)
>
> 本文档是这三份的**整合 + 升级版**，侧重"与竞品的可观测差距 → 可执行里程碑"。

---

## 0. TL;DR

| 竞品 | 我们已持平 | 明显落后 | 反超机会 |
|------|----------|---------|---------|
| **Clash Verge Rev** | 协议覆盖、订阅 CRUD、REST API 兼容、TUN (sidecar)、WebDAV | ⚠️ **规则可视化编辑器** / **Merge+Script Profile** / **内核切换** / **CSS Injection** / **Service Mode** / 流量图表细节 | 🚀 Swift 原生体验 / 内存占用 / 启动速度 / macOS 深度集成 (Menu Bar Extra、Shortcuts、Focus Filter) |
| **Hiddify Next** | 基础订阅、节点选择、主题 | ⚠️ **Reality / ShadowTLS / TUIC / WireGuard / NaiveProxy / ECH** / **Per-App Proxy** / **自动诊断 / 一键修复** / **多平台覆盖** / 商店分发 | 🚀 原生性能 / 非 Flutter 的 macOS 设计语言 / 更强的 XPC/系统守护 |

**6 个月结束后的目标状态**：
- Riptide 1.2 面向 macOS 用户时，**无需再建议"迁移到 Clash Verge Rev"**
- 协议覆盖从当前 8 种扩到 12+（加入 Reality、ShadowTLS、TUIC、WireGuard 的 sing-box 路径）
- UI 达到"可截图做宣传"的完成度（规则编辑器 / 流量图 / 连接详情三件套）

---

## 1. 差距矩阵 (Gap Matrix)

图例：✅ 已实现 · 🟡 部分实现 · ❌ 缺失 · 🚫 不在范围 (移动端等)

### 1.1 协议与传输层

| 协议 / 传输 | Riptide | Verge Rev | Hiddify | 差距等级 |
|------------|:-------:|:---------:|:-------:|:-------:|
| Shadowsocks (AEAD + AEAD-2022) | 🟡 AEAD | ✅ | ✅ | **P2** 升级 AEAD-2022 |
| VMess (AEAD) | ✅ | ✅ | ✅ | — |
| VLESS (XTLS-Vision) | 🟡 无 Reality | ✅ via mihomo | ✅ via sing-box | **P0** Reality |
| Trojan | ✅ | ✅ | ✅ | — |
| Hysteria 1 | ❌ | ✅ | ✅ | **P2** |
| Hysteria 2 | ✅ | ✅ | ✅ | — |
| Snell v2/v3 | ✅ (独有) | ❌ | ❌ | 反超 |
| TUIC v5 | ❌ | ✅ | ✅ | **P1** |
| WireGuard | ❌ | ✅ (mihomo) | ✅ (sing-box) | **P1** |
| ShadowTLS | ❌ | 🟡 | ✅ | **P1** |
| NaiveProxy | ❌ | ❌ | ✅ | P3 |
| SSH Outbound | ❌ | ❌ | ✅ | P3 |
| AnyTLS | ❌ | 🟡 | 🟡 | P3 |
| ECH | ❌ | 🟡 | ✅ | **P2** |
| uTLS 指纹 | ❌ | ✅ | ✅ | **P1** |
| HTTPUpgrade | ❌ | ✅ | ✅ | **P2** |
| gRPC 传输 | ❌ | ✅ | ✅ | **P1** |
| HTTP/3 (QUIC) | 🟡 Hy2 内 | ✅ | ✅ | P3 |

### 1.2 DNS / 路由 / 规则

| 能力 | Riptide | Verge Rev | Hiddify | 差距 |
|------|:-------:|:---------:|:-------:|:----:|
| DoH/DoT/DoQ/UDP/TCP DNS | ✅ | ✅ | ✅ | — |
| FakeIP | ✅ | ✅ | ✅ | — |
| 分流 DNS (nameserver-policy) | 🟡 | ✅ | ✅ | **P1** |
| GEOIP / GEOSITE / ASN | ✅ | ✅ | ✅ | — |
| RULE-SET (Clash + sing-box 格式) | 🟡 仅 Clash | ✅ 双格式 | ✅ | **P1** |
| SCRIPT (JS) 规则 | ✅ | ✅ | ❌ | — |
| **规则可视化编辑器** | ❌ | ✅ | 🟡 | **P0** |
| 连接实时命中规则显示 | 🟡 | ✅ | ✅ | **P1** |
| Logical Rules (AND/OR/NOT) | 🟡 仅 NOT | ✅ | ✅ | **P2** |

### 1.3 订阅与配置管理

| 能力 | Riptide | Verge Rev | Hiddify | 差距 |
|------|:-------:|:---------:|:-------:|:----:|
| Clash YAML 订阅 | ✅ | ✅ | ✅ | — |
| Sing-box JSON 订阅 | ❌ | ❌ | ✅ | **P1** |
| Base64 / V2Ray 聚合订阅 | 🟡 ProxyURIParser | ✅ | ✅ | **P1** |
| 订阅流量/到期显示 | ❌ | ✅ | ✅ | **P0** |
| 自动更新 | ✅ | ✅ | ✅ | — |
| **Merge Profile** (拼接增强) | ❌ | ✅ | ❌ | **P0** |
| **Script Profile** (JS 增强) | ❌ | ✅ | ❌ | **P1** |
| 配置语法提示 / 错误定位 | ❌ | ✅ | 🟡 | **P1** |
| 订阅 UA 自定义 | 🟡 | ✅ | ✅ | **P2** |
| 配置备份/回滚 | 🟡 仅单份 .bak | ✅ 历史版本 | 🟡 | **P1** |

### 1.4 运行模式与系统集成

| 能力 | Riptide | Verge Rev | Hiddify | 差距 |
|------|:-------:|:---------:|:-------:|:----:|
| 系统代理模式 | ✅ | ✅ | ✅ | — |
| 系统代理守护 (外部改动回滚) | ✅ | ✅ | ✅ | — |
| TUN 模式 (via mihomo) | ✅ | ✅ | ✅ | — |
| **TUN Stack 选择** (gVisor/system/mixed) | ❌ | ✅ | ✅ | **P1** |
| **Service Mode** (后台常驻 + 非管理员可用) | ❌ | ✅ | 🟡 | **P0** |
| **分应用代理** (Per-App / Process-level) | 🟡 仅规则层 | 🟡 | ✅ | **P1** |
| **轻量模式** (Mini/Lite 窗) | ❌ | ✅ | ❌ | **P2** |
| 菜单栏 Extra (速度 / 切换) | ✅ | ✅ | ❌ | 反超保持 |
| 全局热键 | ✅ | ✅ | 🟡 | — |
| 开机启动 | ✅ | ✅ | ✅ | — |
| **内核切换** (Stable ↔ Alpha mihomo / sing-box) | 🟡 规划中 | ✅ | ✅ | **P0** |
| macOS Shortcuts / Focus Filter 集成 | ❌ | ❌ | ❌ | 🚀 **反超机会** |

### 1.5 UI / UX

| 能力 | Riptide | Verge Rev | Hiddify | 差距 |
|------|:-------:|:---------:|:-------:|:----:|
| 仪表盘 (首页) | 🟡 基础 | ✅ | ✅ | **P0** |
| 节点卡片 + 延迟颜色 | ✅ | ✅ | ✅ | — |
| 一键延迟测试 | ✅ | ✅ | ✅ | — |
| **实时流量图表** (Swift Charts) | 🟡 数值 | ✅ 图表 | ✅ 图表 | **P0** |
| 连接详情面板 (5元组+规则命中) | 🟡 表格 | ✅ 详情抽屉 | ✅ | **P0** |
| 日志级别过滤 + 搜索 | ✅ | ✅ | ✅ | — |
| 日志导出 | ✅ | ✅ | 🟡 | — |
| 自定义主题色 | 🟡 L/D/System | ✅ 8+ 色 | ✅ | **P1** |
| **CSS Injection / 自定义样式** | ❌ | ✅ | ❌ | P3 |
| 多语言 | ✅ zh/en | ✅ 10+ 语 | ✅ 30+ 语 | **P2** 扩 ja/ko/ru/fa |
| 无障碍 (VoiceOver / 键盘导航) | ❓ 未验证 | 🟡 | 🟡 | P3 |
| **新手引导 / 首次使用 Checklist** | 🟡 仅 Helper 安装 | ✅ | ✅ 自动诊断 | **P1** |
| 节点二维码扫描/生成 | ❌ | ✅ 生成 | ✅ 双向 | **P2** |
| 拖拽导入 .yaml | ✅ | ✅ | ✅ | — |

### 1.6 高级 / 差异化

| 能力 | Riptide | Verge Rev | Hiddify | 差距 |
|------|:-------:|:---------:|:-------:|:----:|
| MITM 框架 | 🟡 脚手架 | ❌ | ❌ | 反超潜力 |
| WebDAV 同步 | ✅ | ✅ | 🟡 | — |
| **一键网络诊断** | ❌ | 🟡 | ✅ Auto-Diagnostic | **P1** |
| **Warp 内置** | ❌ | ❌ | ✅ | P3 |
| 节点测速 (Download/Speed Test) | ❌ | ✅ | ✅ | **P2** |
| 配置加密 | ❌ | ❌ | ✅ | P3 |
| 托盘动态图标 | 🟡 | ✅ 自定义 | ❌ | **P2** |
| 自更新 (sparkle / 内置) | 🟡 Homebrew | ✅ 内置 | ✅ | **P1** |

### 1.7 跨平台矩阵

| 平台 | Riptide | Verge Rev | Hiddify |
|------|:-------:|:---------:|:-------:|
| macOS (arm64 + x86_64) | ✅ 1.x | ✅ | ✅ |
| Windows 10/11 | 🟡 1.1 (Tauri port) | ✅ 核心 | ✅ 完整 |
| Linux | ❌ | ✅ | ✅ |
| iOS | ❌ | ❌ | ✅ App Store |
| Android | ❌ | ❌ | ✅ Play Store |

---

## 2. 核心差距归纳

把上面的 🟡/❌ 聚合为**五大差距主题**：

### Gap-1. 规则与配置的"可编辑性"
Riptide 目前只支持 YAML 文本导入。Verge Rev 的**规则可视化编辑器 + Merge/Script Profile** 是高频使用场景，直接影响日常可用性。

### Gap-2. 协议广度与"抗墙"能力
缺 **Reality / ShadowTLS / TUIC / WireGuard / uTLS 指纹** — 这些是 2024+ 用户选型的决定性因素。改进计划设计规范已确认引入 sing-box 作为第二内核，但尚未落地。

### Gap-3. 观测性（流量/连接/规则命中）
UI 的流量显示仍是数字，缺 **Swift Charts 折线图、连接详情抽屉、命中规则溯源**。这是 UX 对标 Verge Rev 最直接的鸿沟。

### Gap-4. 常驻与分发
- **Service Mode**: 现在 TUN 必须每次输密码启动 helper；Verge Rev/Hiddify 都有后台服务常驻模式
- **内核切换 UI**: 无 UI 让用户在 mihomo stable / alpha / sing-box 之间切
- **内置自动更新**: 依赖 Homebrew，非 brew 安装的用户无法获取新版

### Gap-5. 新手上手
缺 **一键诊断 / 首次使用向导 / 订阅流量到期可视化** — Hiddify 在这一块做得极好，是新用户留存的关键。

---

## 3. 3–6 个月分阶段路线图

> **基准时间**：2026-04-21
> 阶段节奏：每阶段 ~6 周，共 3 阶段；每阶段末出一个 minor 版本。

### 📍 Phase 1 · 体验闭环 (v1.2, 2026-04-21 → 2026-06-02, 6 周)

**目标**：可对外宣传的"功能完整 + 体验不输 Verge Rev"的 macOS 版。

**成功标准**：
- 任意用户从 Verge Rev 迁移过来，**不会因"功能缺失"而切回去**
- UI 能截图做产品宣传页
- macOS daily driver 使用 2 周不出现需要重启 app 的问题

#### 里程碑 M1.1 · 观测性三件套 (2 周)
- [ ] **T1.1.1** Swift Charts 实时流量图（上下行折线、60s/10m/1h 切换）—— `Views/TrafficView/` 新增 `TrafficChartView.swift`
- [ ] **T1.1.2** 连接详情抽屉（5 元组、协议、命中规则、出站节点、耗时、已传字节）—— 复用 `/connections` WebSocket + 规则溯源
- [ ] **T1.1.3** 首页仪表盘（顶部三卡：当前模式 + 当前节点 + 速度；中部订阅卡；底部最近连接）—— `Views/DashboardView.swift` 新建

#### 里程碑 M1.2 · 订阅与 Profile 增强 (2 周)
- [ ] **T1.2.1** 订阅头 `subscription-userinfo` 解析，展示流量 / 到期 / 重置日
- [ ] **T1.2.2** Merge Profile 基础版：允许用户定义一份 merge.yaml，自动与订阅深度合并（复用现有 `ConfigMerger`）
- [ ] **T1.2.3** Sing-box JSON 订阅解析（新建 `Sources/Riptide/Subscription/SingBoxSubscriptionParser.swift`）
- [ ] **T1.2.4** 配置备份历史（保留最近 10 份带时间戳，UI 可回滚）

#### 里程碑 M1.3 · Service Mode + 内核切换 UI (2 周)
- [ ] **T1.3.1** Helper 改造为 LaunchDaemon 常驻（SMAppService 迁移；现在是 SMJobBless），避免每次启动输密码
- [ ] **T1.3.2** 内核切换 UI：Settings → Kernels → mihomo stable / mihomo alpha / sing-box（路径 + 版本 + 下载按钮）
- [ ] **T1.3.3** `Scripts/download-mihomo.sh` 扩展为 `download-kernels.sh`，支持三种内核

#### 非功能
- [ ] **T1.N.1** 修复 `MockURLProtocol` 的 16 个竞态测试失败（RELEASE-REPORT 里列出的 known issue）
- [ ] **T1.N.2** CI 增加 `swift test --parallel` 稳定性回归

---

### 📍 Phase 2 · 协议广度 (v1.3, 2026-06-02 → 2026-07-14, 6 周)

**目标**：协议覆盖追平 sing-box 主流，消除"Riptide 不支持 Reality 所以没法用"的退用理由。

**成功标准**：
- 至少 **3 种新协议** (Reality、WireGuard、TUIC) 可用
- sing-box 内核落地，用户可在 UI 选择某些协议走 sing-box
- 协议选择不再成为用户流失原因

#### 里程碑 M2.1 · sing-box 内核集成 (2 周)
- [ ] **T2.1.1** `Sources/Riptide/SingBox/SingBoxCore.swift` 落地：进程管理、配置生成、REST API 客户端
- [ ] **T2.1.2** `ModeCoordinator` 扩展为三内核路由（Swift Engine / mihomo / sing-box）
- [ ] **T2.1.3** 协议 → 内核映射表（按 `docs/improvement-plan-design-2026.md` §2.1）
- [ ] **T2.1.4** 内核切换的无缝热重载（切换不断开现有连接）

#### 里程碑 M2.2 · 新增协议（sing-box 路径）(2 周)
- [ ] **T2.2.1** **VLESS + Reality** 配置生成 + UI 表单
- [ ] **T2.2.2** **WireGuard** 配置生成 + UI 表单（包含 MTU / endpoint / peer 配置）
- [ ] **T2.2.3** **TUIC v5** 配置生成 + UI 表单
- [ ] **T2.2.4** **ShadowTLS v3** 配置生成

#### 里程碑 M2.3 · 传输层与指纹 (2 周)
- [ ] **T2.3.1** **uTLS 指纹伪装**（Chrome/Firefox/Safari/Edge/iOS 可选）
- [ ] **T2.3.2** **gRPC 传输** (Swift 引擎，走 NIO)
- [ ] **T2.3.3** **HTTPUpgrade 传输**
- [ ] **T2.3.4** **Shadowsocks AEAD-2022** 加密套件

---

### 📍 Phase 3 · 可编辑性与打磨 (v1.4, 2026-07-14 → 2026-08-25, 6 周)

**目标**：规则/节点可视化编辑全面落地 + macOS 深度集成差异化。

**成功标准**：
- 非技术用户可以不打开 YAML 完成所有配置
- 在 macOS 生态"感觉更像一个 Mac App"，拉开与 Verge Rev/Hiddify 的体验差距

#### 里程碑 M3.1 · 规则可视化编辑器 (2.5 周)
- [ ] **T3.1.1** Rules 面板增加"编辑"模式：表格 + 拖拽排序 + 类型选择器
- [ ] **T3.1.2** 规则校验（语法、GEOIP/GEOSITE 存在性、Group 引用有效性）
- [ ] **T3.1.3** 一键测试规则命中（输入域名/IP 预览落入哪条规则）
- [ ] **T3.1.4** 导出合并后的 YAML 快照

#### 里程碑 M3.2 · 节点编辑 + 二维码 + Script Profile (1.5 周)
- [ ] **T3.2.1** 节点编辑器支持全协议（现在只覆盖部分）
- [ ] **T3.2.2** 节点分享二维码生成（vless://, vmess://, ss:// URI）
- [ ] **T3.2.3** Script Profile (JavaScriptCore) — 复用现有 `Scripting/ScriptEngine.swift`

#### 里程碑 M3.3 · macOS 深度集成 (差异化) (1 周)
- [ ] **T3.3.1** **Shortcuts App 支持**（"切换代理模式"、"选择订阅"、"切换节点"三个 Intent）
- [ ] **T3.3.2** **Focus Filter 支持**（工作模式自动 Direct / 娱乐模式全局代理）
- [ ] **T3.3.3** **Menu Bar Extra 速度气泡** 动态图标（参考 iStat Menus）
- [ ] **T3.3.4** **Sparkle 自更新** 集成（非 brew 用户也能 OTA）

#### 里程碑 M3.4 · 新手引导 + 自动诊断 (1 周)
- [ ] **T3.4.1** 首次启动引导流程（5 步：权限 → 订阅 → 模式 → 节点 → 完成）
- [ ] **T3.4.2** 一键诊断（检测：helper 状态、mihomo 可执行、订阅可达、DNS 解析、规则加载、节点连通）
- [ ] **T3.4.3** 常见问题自动修复（重装 helper、重置系统代理、清除 DNS 缓存）

---

## 4. 任务清单（扁平化，供排期）

### P0（v1.2 必须）
1. 实时流量图表 (Swift Charts)
2. 连接详情抽屉 + 规则命中
3. 首页仪表盘
4. 订阅流量/到期解析
5. Merge Profile
6. Service Mode (SMAppService)
7. 内核切换 UI
8. 修复 16 个 MockURLProtocol 竞态

### P1（v1.3）
9. sing-box 内核集成
10. Reality / WireGuard / TUIC / ShadowTLS
11. uTLS 指纹
12. gRPC / HTTPUpgrade 传输
13. Sing-box JSON 订阅
14. 配置备份历史
15. 分流 DNS (nameserver-policy)

### P2（v1.4）
16. 规则可视化编辑器
17. 节点编辑器全协议覆盖 + 二维码
18. Script Profile
19. macOS Shortcuts / Focus Filter
20. Sparkle 自更新
21. 首次引导 + 自动诊断
22. AEAD-2022 / ECH

### P3（v2.0+ / 长期）
23. Linux 原生端
24. iOS NetworkExtension 移植（复用现有 `AppExtensions/RiptideTunnelExtension`）
25. NaiveProxy / SSH / AnyTLS
26. Warp 内置
27. CSS Injection
28. Android (Kotlin + sing-box AAR)

---

## 5. 验收指标

### 5.1 功能指标 (v1.4 结束时)
- [ ] 支持的协议数 ≥ 12（当前 8）
- [ ] 订阅显示流量到期信息
- [ ] 规则可视化编辑 + 无需 YAML 编辑的完整配置
- [ ] Service Mode 常驻，TUN 启动 < 2s
- [ ] sing-box 与 mihomo 可热切换

### 5.2 UX 指标
- [ ] 首页仪表盘 3 张卡关键信息 1 秒内可读
- [ ] 连接详情抽屉 ≤ 2 次点击打开
- [ ] 规则编辑器操作路径 ≤ 3 步
- [ ] 新用户从安装到第一次成功连接 ≤ 5 分钟（自动引导）

### 5.3 质量指标
- [ ] 测试套件 100% 稳定通过（消除 16 个 flaky）
- [ ] macOS 稳定运行 72 小时无崩溃 / 无需重启
- [ ] 内存占用 ≤ 80MB（Verge Rev ~150MB / Hiddify ~200MB）
- [ ] 启动冷启动 ≤ 1.5s

---

## 6. 风险与约束

| 风险 | 影响 | 缓解 |
|------|------|------|
| sing-box 引入增加二进制体积（+15MB） | 安装包变大 | 改为按需下载内核；安装包内只放 mihomo |
| Reality / uTLS 实现复杂度 | Phase 2 延期 | 优先走 sing-box sidecar，不急于 Swift 原生实现 |
| Service Mode (SMAppService) 对 macOS 13+ 要求 | 丢失部分用户 | 保留 SMJobBless 作为 fallback；最低要求保持 macOS 14 |
| Swift Charts 要求 macOS 13+ | 已满足（最低 14） | — |
| UI 重构量大 | 影响现有用户 | 保留 Classic 视图开关，灰度推出 |
| Merge/Script Profile 的 YAML 合并边界情况 | 配置出错 | 引入 dry-run 预览 + 一键回滚 |

---

## 7. 与现有文档的关系

| 文档 | 关系 |
|------|------|
| `ROADMAP.md` | 早期 3 阶段计划（Week 1-6）— 已部分完成，本文档**不再使用**其时间线 |
| `docs/IMPROVEMENT-PLAN.md` | 对标 Clash Verge Rev 的 P0-P3 清单 — **本文档整合其优先级矩阵**，把时间线细化到周 |
| `docs/improvement-plan-design-2026.md` | sing-box 双内核架构的技术决策 — **本文档的 Phase 2 就是它的执行版** |
| `docs/stage-plans/*.md` | 更早期的 Surge 对齐/1.0 兼容性 — 保留做历史参考 |

**建议**：本文档作为未来 6 个月的**主规划**。`docs/IMPROVEMENT-PLAN.md` 标注"Superseded by COMPETITIVE-ROADMAP-2026.md"。

---

## 附录 A · 竞品快照（2026-04）

### Clash Verge Rev
- Tauri 2 + Rust + TypeScript，内核 mihomo (可切 Alpha)
- 明确支持：Merge/Script Profile、可视化编辑、系统代理守护、TUN、WebDAV、CSS Injection、自定义主题、托盘图标自定义、内核切换
- 最新版 v2.4.7，~112k stars，活跃

### Hiddify Next (hiddify-app)
- Flutter + hiddify-core (Go/sing-box)，真正五平台
- 强项：协议广度（Reality/TUIC/WG/ECH 等）、自动诊断、订阅流量到期显示、区域化优化配置（伊朗/中国/俄罗斯）、官方商店分发
- 最新版 v4.1.1，~28.8k stars

### 我们的差异化锚点
1. **Swift 原生 = 低内存 + 快启动 + macOS 一等公民体验**
2. **库优先 = 协议逻辑可单元测试 + 不绑死单一内核**
3. **双（三）内核并存 = 可随生态演进而扩展，不丢历史用户**
4. **MITM 脚手架 = 为进阶用户（开发者/安全研究）预留差异化能力**

---

_文档版本: 1.0 · 最后更新: 2026-04-21 · 负责人: @G3niusYukki_
