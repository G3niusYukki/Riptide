# Riptide Windows 端追赶 v2.4.1 详细方案

> 作者:Mavis / 2026-06-05
> 范围:`riptide-windows/`(Tauri 2 / Rust + React/TS)对标 macOS v2.4.1 的全量差距
> 目标:把 Windows 端的功能、UI、测试、CI、文档 全部追到与 macOS 同档 v2.4.1,并为 v2.5.0(Reality/AnyTLS/Sing-box 默认开启)铺好基础设施

---

## 0. 现状基线(参考点)

| 维度 | macOS(v2.4.1) | Windows | 差距 |
|---|---|---|---|
| 生产代码 | 234 Swift / 40,419 LoC | 58 Rust + 38 TS/TSX / 14,560 LoC | 3.7×(结构性,合理) |
| 测试 | 593 tests / 93 suites + 38 UI tests | ~0(只有 inline `cfg(test)`) | 全面缺失 |
| 主路由/tab | 8 | 7 | 缺 Config / Traffic 独立 tab |
| 设置子 tab | ~6 | 10 | 反过来 Win 多 4 个 |
| Tauri 命令 | n/a(REST 走库) | ~70 个 | 数量合理 |
| CI 工作流 | 6 个(ci/bench/release/sparkle/homebrew/deploy-docs) | **0 个** | 全面缺失 |
| CHANGELOG | v2.4.1 详尽 | 停 0.1.0 | 缺治理 |
| AGENTS.md | 342 行 | 无 | 缺治理 |
| ADR | 6 份 | 无 | 缺治理 |
| 文档站 | VitePress | 无 | 缺治理 |
| 规则集仓库 | 4 套 | 无 | 缺生态 |
| 平台打包 | DMG + ZIP | MSI + NSIS | 持平 |
| i18n | 10 语言 | 8 语言 | 缺 es |

工程量基准:1 人天 = 1 个熟悉 Tauri + 现有代码库的资深工程师满负荷 8 小时。下面所有估算以"2 人并行"为基础。

---

## 1. 追赶原则

1. **追平 > 创新**:不在这轮做新 feature,只把 macOS 已有的搬到 Windows,并修好现有 bug。
2. **结构化优于偷工**:每个 feature 必须包含 backend Rust + frontend UI + 测试 + 文档,缺一不可。
3. **平台差异要明确**:macOS-only 的(Sparkle、TouchBar、WidgetKit、QuickLook)不上,留 todo;Win-only 的(WARP、kill_switch、recovery_watchdog、gateway、tls_tricks、region_presets)反向给 macOS 时单独评估。
4. **测试先行**:先把测试基础设施和 CI 跑通,再写新功能 — 否则会陷入"补 1 个 feature 引入 5 个回归"。
5. **可灰度**:每个 phase 结束时,Windows 端能出一个可发布的 v2.X.0-Win.0 镜像。

---

## 2. 阶段划分(4 phase,约 12 周)

| Phase | 周期 | 目标 | 结束时产出 |
|---|---|---|---|
| **A. 紧急修复 + 治理基线** | W1(1 周) | 修 4 个 Windows bug + 写 AGENTS/CHANGELOG/ADR + 补 .version | `v2.4.1-Win.0` 可发 |
| **B. 基础设施 + 测试 + CI** | W2-W4(3 周) | 测试框架、CI 工作流、Logbook 数据层、URI Serializer | `v2.4.2-Win.0` 可发 |
| **C. 功能 + UI 补全** | W5-W9(5 周) | Logbook UI、Override UI、QR、URL Scheme 6 action、KernelSwitcher、EngineBenchmark、MITM、SceneEditor、SurgeScript、Appearance、Notification、WARP 反向 | `v2.4.3-Win.0` 可发 |
| **D. 治理 + 生态** | W10-W12(3 周) | VitePress docs 站、规则集仓库、Homebrew 等价物(WinGet/Scoop)、i18n 补 es、Sparkle 升级到 Tauri updater、ADR 体系 | `v2.4.4-Win.0` 与 macOS 平 |

> 周期是预估,实际由 2 人并行团队决定。每个 phase 结束有 demo + regression test 必须绿。

---

## 3. 任务清单(分领域,带 ID/依赖/工程量/验收)

### Phase A — 紧急修复 + 治理基线(W1,共 4 人天)

#### A1. 修 4 个明显 Bug(1.5 人天)
- **A1.1** `riptide-windows/src/components/Settings/index.tsx:71` — diagnostics tab 渲染错组件
  - 修法:新增 `DiagnosticsTab.tsx` 或暂时从 tab 列表移除 diagnostics entry
  - 验收:点 diagnostics tab 不再显示 recovery 内容
- **A1.2** `riptide-windows/src/components/Settings/index.tsx:110` — 硬编码 `Riptide v2.0.0`
  - 修法:从 `@tauri-apps/api/app` 读 `getVersion()` 或 invoke 后端 `app_version` 命令
  - 验收:About 页显示当前真实版本
- **A1.3** `riptide-windows/src-tauri/Cargo.toml:17` — tauri crate 没 pin minor
  - 修法:`tauri = { version = "=2.10", features = ["tray-icon"] }`
  - 验收:`cargo update -p tauri` 不会拉到 2.11+
- **A1.4** 顶层 `riptide-windows/CHANGELOG.md` 停 0.1.0
  - 修法:补 v0.2.0 - v2.4.1 之间所有 milestone 的反向 changelog
  - 验收:可读懂 Windows 端从初始版到当前的所有变更

#### A2. 写 `riptide-windows/AGENTS.md`(1 人天)
- 从 macOS `AGENTS.md` 裁剪,补充:
  - Windows-specific 工具链约束(Tauri 2 minor 对齐、Cargo workspace 单一 default-run = riptide-windows、wintun.dll 要求、MSI 安装的 WebView2 依赖)
  - `WindowsDirs` 路径规则(`%APPDATA%\Riptide\` 不要用 bundle id)
  - YAML 编辑 round-trip 必须用 `serde_yaml::Value` 保留未知 key
  - 测试命令:`cargo test`、`cargo check`、`npm run tsc`
  - Release 流程:`tauri build` + GitHub release 双 artifact
- 验收:新人读后能跑通 dev 模式 + 一次 release 构建

#### A3. 写 `docs/decisions/0007-...`(0.5 人天)
- ADR-0007:Windows 端 KernelRouter 选型(sing-box sidecar 路径)
- 验收:含上下文/决策/后果三段

#### A4. 同步 `.version` + `package.json` + tauri.conf.json 自动化(1 人天)
- 写 `Scripts/bump-version.ps1` 对标 macOS 的 `bump-version.sh`
  - 改 `.version`
  - 改 `riptide-windows/package.json`
  - 改 `riptide-windows/src-tauri/tauri.conf.json`
  - 改 `riptide-windows/src-tauri/Cargo.toml`(`version` 字段)
  - 改 `riptide-windows/CHANGELOG.md` 顶部加新条目占位
- CI check:在 PR 时跑 diff,任何跟 `.version` 不一致 → 失败
- 验收:`./bump-version.ps1 2.4.2` 后 4 个文件全部对齐

#### A5. 验证 Phase A(0 人天,集成验证)
- 跑 `cargo check` + `npm run tsc` + `npm run tauri build` 必须过

---

### Phase B — 基础设施 + 测试 + CI(W2-W4,共 25 人天)

#### B1. 测试基础设施(8 人天)
- **B1.1** 在 `riptide-windows/src-tauri/tests/` 建独立测试目录(1 人天)
  - 结构:`tests/{unit,integration,fixtures}/`
  - 把所有现有 `#[cfg(test)] mod tests` 抽出来到独立文件
  - 加 `#[tokio::test]` / `#[test]` 模板注释
- **B1.2** Rust 测试套件:核心 8 模块(6 人天)
  - `core/mode_coordinator.rs` — 模式切换状态机(3 个测试)
  - `core/sysproxy.rs` + `windows_sysproxy.rs` — 系统代理(4 个)
  - `core/recovery_watchdog.rs` — 恢复(2 个)
  - `core/kill_switch.rs` — 杀死开关(2 个)
  - `core/mihomo_bootstrap.rs` — SHA-256 校验(3 个)
  - `core/subscription_scheduler.rs` — 调度(3 个)
  - `core/webdav.rs` + `secrets.rs` — 加密 + 上传下载(4 个)
  - `core/warp.rs` — x25519 密钥 + 注册(2 个)
  - 目标:从 0 → ~25 Rust tests
- **B1.3** 前端测试套件:核心 5 模块(1 人天)
  - 选 vitest + @testing-library/react
  - `services/tauri.ts` — IPC wrapper mock(2 个)
  - `stores/riptide.ts` — Zustand store 状态(3 个)
  - `hooks/useProxies.ts` — 代理数据流(2 个)
  - `hooks/useTraffic.ts` — 流量轮询(2 个)
  - `i18n/index.ts` — 语言切换(2 个)
  - 目标:~11 TS tests

#### B2. CI 工作流(4 个)(6 人天)
- **B2.1** `riptide-windows/.github/workflows/ci.yml`(2 人天)
  - 触发:PR + push to master
  - 步骤:
    1. setup-node 20 + setup-rust 1.75+
    2. `npm ci` + `cargo fetch`
    3. `cargo fmt --all -- --check`
    4. `cargo clippy --all-targets -- -D warnings`
    5. `cargo test`
    6. `npm run tsc -- --noEmit`
    7. `npm run test`(vitest)
  - 缓存:`~/.cargo`、`node_modules`、tauri 缓存
- **B2.2** `riptide-windows/.github/workflows/release.yml`(1.5 人天)
  - 触发:tag push `vX.Y.Z`
  - 矩阵:`windows-latest` x `x64` / `arm64`
  - 步骤:`npm ci` → `npm run tauri build` → 收集 NSIS + MSI → 上传 GitHub Release
  - 跟 macOS 端 `release.yml` 协调时间(避免冲突)
- **B2.3** `riptide-windows/.github/workflows/lint.yml`(0.5 人天)
  - rustfmt + clippy + tsc + eslint + prettier
- **B2.4** `riptide-windows/.github/workflows/bench.yml`(2 人天,跨端)
  - 跟 macOS 端 bench.yml 协调
  - 跑 mihomo 启动时间 / 内存 / 端口绑定 / 模式切换时间
  - 报告 artifact upload
- 验收:4 个工作流第一次跑全绿;之后每次 PR 必跑 ci.yml

#### B3. Logbook 数据层(移植 macOS `Sources/Riptide/Logbook/`)(6 人天)
- **B3.1** Rust 后端:`riptide-windows/src-tauri/src/core/logbook/`(3 人天)
  - `LogEntry` / `LogbookPaths` / `LogbookWriter`(fire-and-forget)+ `LogbookStore` (actor 用 `tokio::sync::Mutex` 等价)
  - 路径:`%APPDATA%\Riptide\logbook\YYYY-MM-DD.jsonl`
  - 注入模式:5 个模块(ModeCoordinator、SubscriptionScheduler、ServiceControlHandler、SystemProxyController、RecoveryWatchdog)接 `setLogbookWriter` async setter
- **B3.2** Tauri 命令暴露(0.5 人天)
  - `logbook_query(limit, level, category, from, to) -> Vec<LogEntry>`
  - `logbook_clear(category, before_date) -> ()`
  - `logbook_export(from, to, path) -> ()`
- **B3.3** 前端 store + hook(1 人天)
  - `stores/logbook.ts`(Zustand) + `hooks/useLogbook.ts`(TanStack Query)
- **B3.4** 测试(1.5 人天)
  - `tests/logbook_writer.rs` — 8 个测试
  - `tests/logbook_store.rs` — 6 个
  - `tests/logbook_paths.rs` — 3 个
  - 目标:Logbook 测试 17 个,跟 macOS 对齐
- 验收:6 注入点全部接入;JSONL 文件可读可查可清可导

#### B4. URI Serializer(移植 macOS `Sources/Riptide/Subscription/ProxyURISerializer.swift`)(3 人天)
- **B4.1** Rust 后端 `riptide-windows/src-tauri/src/config/uri_serializer.rs`(1.5 人天)
  - 实现 6 协议 share URI 生成:ss / vmess / vless / trojan / hy2 / tuic
  - 跟现有 `config/uri.rs` parser 配套
- **B4.2** Tauri 命令(0.5 人天)
  - `serialize_proxy_to_uri(proxy: ClashProxy) -> String`
  - `serialize_proxies_to_uris(profile_id: String) -> Vec<(name, uri)>`
- **B4.3** 测试(1 人天)
  - 跟 macOS `ProxyURISerializerTests` 18 个测试对齐
  - 每个协议 round-trip 3 个 = 18 个
- 验收:Node editor 右键节点 → "Share as QR Code" 走的命令可生成合法 URI

#### B5. 验证 Phase B(0 人天,集成验证)
- 全测试套件绿:目标 ≥ 53 个 Rust tests + 11 个 TS tests
- CI 4 个工作流第一次全跑绿

---

### Phase C — 功能 + UI 补全(W5-W9,共 80 人天)

#### C1. Logbook UI(6 人天)
- **C1.1** `src/components/Logbook/` 目录(2 人天)
  - `LogbookView.tsx` 主面板(按 level / category / date 范围过滤)
  - `LogbookEntryRow.tsx` 单条
  - `LogbookFilters.tsx` 过滤栏
- **C1.2** 路由接入(0.5 人天)
  - 加 `/logbook` 路由
  - Sidebar 加日志本图标(跟 LogViewer 分开)
- **C1.3** "诊断" sub-tab 接入(0.5 人天)
  - 修 A1.1 留下来的 diagnostics tab 接入 Logbook 视图
- **C1.4** Export / Clear 按钮 + 确认对话框(1 人天)
- **C1.5** 测试(2 人天)
  - React Testing Library:filter / sort / clear / export(8 个测试)
- 验收:跟 macOS `DiagnosticsTabView` + `EventLogSection` 视觉+功能一致

#### C2. Override(8 人天)
- **C2.1** Rust 后端 `riptide-windows/src-tauri/src/core/override/`(2 人天)
  - `Override` value struct + serde
  - `OverrideStore`(actor 模式,文件 sidecar JSON + per-override `<UUID>.yaml`)
  - `OverrideMerger`(meta.replace / removed: 语义)
  - `OverrideApplyError` enum
- **C2.2** Tauri 命令(1 人天)
  - `override_list() -> Vec<Override>`
  - `override_get(id) -> Override`
  - `override_create(name, raw_yaml) -> Override`
  - `override_update(id, name?, raw_yaml?) -> Override`
  - `override_delete(id) -> ()`
  - `override_apply(id, profile_id) -> ApplyResult`
- **C2.3** ConfigMerger 扩展(0.5 人天)
  - 让 mihomo config 合并时考虑 active override
- **C2.4** 前端 `src/components/Overrides/`(2 人天)
  - `OverrideListView.tsx` 列表
  - `OverrideEditorView.tsx` YAML 编辑(CodeMirror)
  - `OverrideApplyView.tsx` 预览 + apply
- **C2.5** 路由接入(0.5 人天)
  - 新增 `/overrides` 路由
  - Config tab 内加 override 入口
- **C2.6** 测试(2 人天)
  - Rust OverrideStore 4 个 + OverrideMerger 6 个(round-trip / meta.replace / removed: 边界)
  - 前端 4 个
  - 目标:10 Rust + 4 TS
- 验收:跟 macOS `Sources/Riptide/Override/` 行为兼容

#### C3. Node QR + Share URI UI(4 人天)
- **C3.1** 前端 QR 渲染库(0.5 人天)
  - 加 `qrcode` npm 包(或 `qrcode.react`)
- **C3.2** `NodeQRSheet.tsx` 组件(1 人天)
  - 节点列表的 QR 网格
  - "Copy All URIs" + "Save All as PNGs" + 关闭
- **C3.3** NodeEditor 接入(0.5 人天)
  - 每个节点 row 加 "Share as QR Code" contextMenu
  - 工具栏 "Share All"
- **C3.4** 触发 B4 命令(0.5 人天)
  - `serialize_proxy_to_uri` → 喂给 QR 渲染
- **C3.5** 测试(1 人天)
  - 5 个 TS test(SSR 渲染、Copy All、Save All、空列表、错误)
- 验收:跟 macOS `NodeQRSheet` 视觉+功能一致

#### C4. URL Scheme 多 action(3 人天)
- **C4.1** Rust 后端增强(0.5 人天)
  - 现有 `riptide-windows/src-tauri/src/lib.rs` 注册 deep-link handler(已存在)
  - 扩展 action 解析:6 个 action = switch-group / select-node / mode / import / diagnostics / open-config
- **C4.2** 前端 router dispatch(1.5 人天)
  - `App.tsx` 的 `handleDeepLink` 改成派发到 6 个 action
  - switch-group → 跳转 Proxies 页 + 选组
  - select-node → Proxies 页 + 选节点
  - mode → 跳 mode coordinator 命令
  - import → 现有
  - diagnostics → 跳 Logbook/Overlays
  - open-config → 打开 ConfigImportPreview
- **C4.3** 测试(1 人天)
  - 8 个 TS test(各 action 1 个 + malformed URL 2 个)
- 验收:macOS 6 个 deep link action 在 Windows 端全可用

#### C5. KernelSwitcher / EngineRouter(6 人天)
- **C5.1** Rust 后端 `riptide-windows/src-tauri/src/core/engines/`(1.5 人天)
  - `ProxyEngine` trait(Send + Sync,跟 macOS 协议对齐)
  - `EngineRouter` struct(Policy = defaultMihomo / explicitSingbox)
  - `MihomoEngine` 实现
  - `SingBoxEngine` 实现(调 mihomo + sing-box 共享流程)
- **C5.2** Sing-box sidecar(1.5 人天)
  - `core/singbox.rs`:`SingBoxDownloader`(从 GitHub release 拉 v1.13.0+)+ `SingBoxRuntimeManager`
  - 跟 macOS `Sources/Riptide/SingBox/` 对齐
  - Reality / AnyTLS 协议支持(为 v2.5.0 准备)
- **C5.3** Tauri 命令(0.5 人天)
  - `engine_current() -> ProxyEngineKind`
  - `engine_set_policy(Policy) -> ()`
  - `engine_supported_kinds() -> Set<ProxyKind>`
  - `engine_status() -> {name, kind, version, last_error}`(status-only Phase 1)
- **C5.4** 前端 `Settings/KernelSwitcherView.tsx`(1 人天)
  - 状态面板(只读 Phase 1)
  - mihomo / sing-box 各自版本 + 运行状态
- **C5.5** 测试(1.5 人天)
  - 8 Rust:Router 路由、Engine generateConfig 形状、SingBox 下载 SHA-256
  - 2 TS:UI 状态展示
- 验收:跟 macOS `EngineRouterTests` 行为一致;Phase 1 status-only

#### C6. EngineBenchmark harness(4 人天,跨端)
- **C6.1** Rust harness `riptide-windows/src-tauri/src/bench/`(2 人天)
  - 5 维:HTTP CONNECT p50/p99、throughput、idle memory、CPU、startup
  - 测对象:mihomo(主)、sing-box(对比)、纯 Swift 不适用
- **C6.2** Tauri 命令(0.5 人天)
  - `bench_run(dimensions, iterations) -> BenchmarkReport`
- **C6.3** CI 集成(0.5 人天)
  - 跟 B2.4 bench.yml 接通
  - 报告作为 artifact upload
- **C6.4** 测试(1 人天)
  - 4 个 Rust bench self-tests
- 验收:CI 每次 release 都会跑 bench 并上传报告

#### C7. MITM 设置 UI(3 天)
- **C7.1** Rust 后端 `riptide-windows/src-tauri/src/core/mitm/`(1 天)
  - `MITMConfig` + `MITMManager`(mihomo 已支持,我们做配置面板)
  - CA 证书生成 + install
  - Host 白名单 CRUD
- **C7.2** Tauri 命令(0.5 天)
  - `mitm_get_config` / `mitm_set_config` / `mitm_install_ca` / `mitm_uninstall_ca` / `mitm_get_hosts`
- **C7.3** 前端 `Settings/MITMTab.tsx`(1 天)
  - CA 状态卡片 + install 按钮
  - Host 白名单 CRUD
- **C7.4** 测试(0.5 天)
  - 4 个测试
- 验收:跟 macOS `MITMSettingsView` 功能一致,状态保持 🟡 experimental(警告文案 + 显式开关)

#### C8. SceneEditor(3 天)
- **C8.1** Rust 后端 `riptide-windows/src-tauri/src/core/scenes/`(1 天)
  - `Scene` value struct
  - `SceneStore`(actor 模式)
  - Scene 解析(process / domain / IP-set matcher)
- **C8.2** Tauri 命令(0.5 天)
  - `scene_list / scene_create / scene_update / scene_delete / scene_apply`
- **C8.3** 前端 `Rules/SceneEditorView.tsx`(1 天)
  - 可视化编辑器(进程 / 域名 / IP 集 matcher)
  - 模式 override 选择
- **C8.4** 测试(0.5 天)
  - 5 个测试
- 验收:跟 macOS `SceneEditorView` 一致

#### C9. SurgeScript / JS Scripting(5 天)
- **C9.1** Rust 后端选型(0.5 天)
  - 选项:`boa_engine`(纯 Rust)或 `rquickjs`(Rust 绑定 quickjs)
  - 推荐 `rquickjs` — 体积小、快、跟 mihomo 用法接近
- **C9.2** `riptide-windows/src-tauri/src/core/scripting/`(2 天)
  - `ScriptEngine` 包装 rquickjs
  - `SurgeScriptBridge` 注入 `$request`、`$response`、`$done`、`$persistentStore`、`$notification`
  - mihomo 配置 `script:` 字段解析
- **C9.3** Tauri 命令(0.5 天)
  - `script_eval(name, code, context) -> ScriptResult`
- **C9.4** 前端编辑(0.5 天)
  - `Rules/ScriptEditorView.tsx`(CodeMirror + 实时 lint)
- **C9.5** 测试(1.5 天)
  - 8 个测试:API 注入、$persistentStore 持久化、错误传播、超时
- 验收:跟 macOS `SurgeScriptBridge` 行为一致

#### C10. Appearance(2 天)
- 跟 macOS `ThemeManager` 对齐
- **C10.1** 主题切换 UI(1 天)
  - 已有 `useTheme` hook,补全 light 主题的 Tailwind token(目前 light 主题变量未定义)
  - `App.tsx:67-86` 的 apply 逻辑改成监听 system + user 切换
- **C10.2** 字体 / 间距 / 圆角一致性(1 天)
  - 全局 CSS variable
- 验收:Settings → Appearance 三档切换实际改变颜色,不只是 toggle class

#### C11. Notification(3 天)
- **C11.1** 跨平台抽象(0.5 天)
  - macOS 走 `UNUserNotificationCenter`,Windows 走 `tauri-plugin-notification` 的 toast
  - 统一 API:runtime alerts、helper install 错误、订阅过期、config reload
- **C11.2** 事件总线(1 天)
  - 跟 macOS `NotificationManager` 等价的 Rust 端 `NotificationDispatcher`
- **C11.3** 前端 hook(0.5 天)
  - `useNotification(toast) -> { subscribe }`
  - `stores/toast.ts` 已有,接 tauri event
- **C11.4** 测试(1 天)
  - 5 个测试:emit 路径、用户拒绝权限 fallback、批量去重
- 验收:5 个关键事件能产生本地通知

#### C12. WARP 反向给 macOS(0 天,本计划外但记录)
- macOS 没有 WARP 注册功能
- 这是个可移植 feature,具体要不要做单独起 plan

#### C13. Config 独立 tab + Traffic 独立 tab(2 天)
- **C13.1** 把 ConfigMergeView / ConfigImportPreview 提到顶级 tab(0.5 天)
  - 加 `/config` 路由
  - 把 Settings 里的"重写"等子 tab 拆出来
- **C13.2** 把 TrafficChart 提到顶级 tab(0.5 天)
  - 加 `/traffic` 路由
  - 从 Dashboard 拆出来
- **C13.3** 测试(1 天)
  - 路由切换 4 个 test
- 验收:跟 macOS 8 个 tab 一致

#### C14. 验证 Phase C(0 天,集成验证)
- 全测试套件:目标 ≥ 200 Rust tests + 50 TS tests
- 路由:从 7 涨到 9(+ config + traffic)
- 所有新增 feature 跑通 + 文档更新

---

### Phase D — 治理 + 生态(W10-W12,共 30 人天)

#### D1. VitePress docs 站(7 天)
- **D1.1** `site/` 目录(1 天)
  - 跟 macOS `site/` 一样
  - 配置:config-format / development / getting-started / mitm / rule-engine / windows-platform / windows-build
- **D1.2** Windows platform 文档(2 天)
  - `windows-platform.md`:Windows 特有的 SCM 服务、wintun、kill_switch、recovery_watchdog、gateway、WARP
  - `windows-build.md`:Tauri minor 对齐、Cargo 依赖、签名、打包
- **D1.3** `.github/workflows/deploy-docs.yml` Windows 分发(0.5 天)
  - 跟 macOS 端分开或合并
- **D1.4** 跨平台搜索(0.5 天)
  - VitePress 默认本地搜索
- **D1.5** 测试(0.5 天)
  - 链接有效性测试
- **D1.6** README 改写(1 天)
  - Windows 端 README 引用 docs
- **D1.7** 翻译(1 天)
  - 至少 en + zh-CN
- 验收:`pnpm dev` 起 docs 站,链接全活,跟 macOS 端 docs 同级

#### D2. 规则集仓库(2 天)
- **D2.1** `rules/` 移植(1 天)
  - `cn-domain.yaml` / `geoip-cn.yaml` / `reject-ads.yaml` / `apple-services.yaml` / `index.yaml`
  - 跟 macOS 端同一份,共用
- **D2.2** `RuleMarketView.tsx`(0.5 天)
  - Windows 端展示规则集 + 一键 install
  - 调用 `subscribe` URL 风格
- **D2.3** 测试(0.5 天)
  - 4 个
- 验收:`/rules` 路由或 Rules tab 内的市场可显示并 install

#### D3. i18n 补 es(0.5 天)
- 加 `src/locales/es-ES.json`
- 翻译键 100% 覆盖(从 en-US 镜像)
- 跑 `npm run tsc`

#### D4. Homebrew 等价物(4 天)
- **D4.1** WinGet manifest(1.5 天)
  - `G3niusYukki/Riptide` 加 winget-pkgs PR 模板
  - 自动同步:`.github/workflows/winget.yml` 监听新 tag → 更新 manifest
- **D4.2** Chocolatey package(1.5 天)
  - `riptide` 包,自动从 GitHub release 拉 MSI
  - `.github/workflows/chocolatey.yml`
- **D4.3** Scoop bucket(1 天)
  - 复用 winget 自动同步
- 验收:三个包管理器都能 `winget install riptide` / `choco install riptide` / `scoop install riptide`

#### D5. Tauri updater 启用(3 天)
- **D5.1** 生成 Tauri signing keypair(0.5 天)
  - `tauri signer generate -w ~/.tauri/riptide.key`
  - 公钥填入 `tauri.conf.json:84`(`"pubkey": "REPLACE_WITH_YOUR_PUBLIC_KEY"`)
  - 私钥存到 GitHub Actions secret `TAURI_SIGNING_PRIVATE_KEY`
- **D5.2** 签名 + 发布脚本(1.5 天)
  - `Scripts/sign-and-build.ps1`:本地签名 → 生成 latest.json + .sig → 上传
  - CI 集成(在 release.yml 里)
- **D5.3** 前端 in-app update flow(0.5 天)
  - 已有 `checkUpdate` 命令(返回最新版本信息)
  - 改成自动弹 Tauri updater dialog
- **D5.4** 测试(0.5 天)
  - 3 个测试
- 验收:从 Windows 应用内点"检查更新" → 自动下载 → 自动重启

#### D6. ADR 体系补全(2 天)
- ADR-0008:Windows 端 WARP 选型(走 Cloudflare 公开 API)
- ADR-0009:Windows 端 SCM service vs 用户态 helper 选型
- ADR-0010:Windows 端 sing-box 集成路径
- ADR-0011:Windows 端测试金字塔(target:Rust 200 / TS 100 / Playwright UI 20)

#### D7. `.harness/` 配 mavis team(1.5 天)
- 跟 bootstrap_check 配合,创建项目专属 reins:
  - `windows-rust-engineer`(专做 src-tauri/src)
  - `windows-frontend-engineer`(专做 src/)
  - `windows-qa`(专做 tests + CI)
  - `windows-doc-writer`(专做 docs/)
- 验收:`mavis team plan` 能直接拉这套人去推 Phase B/C/D

#### D8. 验证 Phase D(0 天)
- 最终全测试套件:目标 ≥ 300 Rust + 100 TS + 30 Playwright UI
- 文档站可访问
- 3 个包管理器都能装
- in-app update 跑通
- 所有 ADR 在 docs/decisions/

---

## 4. 任务依赖图(关键路径)

```
A1(修 bug) ─┐
A2(AGENTS) ─┼─→ B1(测试基础设施) ─┐
A3(ADR-0007)│                     │
A4(bump脚本)│                     ├─→ B2(CI) ─┐
A5(Phase A 验证)┘                  │           │
                                   │           │
                                   ├─→ B3(Logbook 数据) ─┐
                                   ├─→ B4(URI Serializer) ┤
                                   │                       ├─→ C1(Logbook UI)
                                   │                       ├─→ C3(Node QR UI)
                                   │                       ├─→ C4(URL Scheme)
                                   │                       │
                                   ├─→ C2(Override 完整)  │
                                   ├─→ C5(KernelSwitcher) │
                                   ├─→ C6(EngineBenchmark)│
                                   ├─→ C7(MITM UI)        │
                                   ├─→ C8(SceneEditor)    │
                                   ├─→ C9(SurgeScript)    │
                                   ├─→ C10(Appearance)    │
                                   ├─→ C11(Notification)  │
                                   └─→ C13(独立 tab) ─────┘
                                                            │
                                                            ▼
                                                       D1(VitePress)
                                                       D2(规则集)
                                                       D3(es)
                                                       D4(包管理器)
                                                       D5(updater)
                                                       D6(ADR 补)
                                                       D7(.harness)
                                                       D8(总验证)
```

**关键路径(总工期 12 周的瓶颈)**:
- B1(测试基础设施)→ B2(CI)→ B3/B4(数据层)→ C1/C3(UI)→ C2(Override 复杂)→ D1(Docs)→ D5(Updater)→ 验证

**可并行的快路径**:
- A 全部并行(4 人天)
- D1/D2/D3/D4/D6/D7 在 C 阶段末期即可启动
- 测试可以边写边补,不阻塞 C

---

## 5. 测试策略

### 5.1 目标分布

| 层级 | Phase A | Phase B 末 | Phase C 末 | Phase D 末 |
|---|---:|---:|---:|---:|
| Rust 单元 + 集成 | 0 | 53 | 200 | 300 |
| TS 单元(React Testing Library)| 0 | 11 | 50 | 100 |
| Playwright UI(E2E) | 0 | 0 | 0 | 30 |
| **合计** | **0** | **64** | **250** | **430** |

### 5.2 工具选型

| 层 | 工具 | 备注 |
|---|---|---|
| Rust unit | `cargo test` 内联 + 独立 `tests/` | tokio-test for async |
| Rust 集成 | `wiremock` for mihomo API mock | 端口 9090 mock |
| Rust 平台 | `mockall` for Windows API mock | 避免 UAC 触发 |
| TS unit | vitest + @testing-library/react | 已有 vite 配置 |
| TS store | 直接调 Zustand store | |
| TS IPC | `vi.mock('@tauri-apps/api/core')` | mock invoke |
| E2E | Playwright + `tauri-driver` | tauri 官方 webdriver |

### 5.3 跟 macOS 测试对齐

- `OverrideStoreTests`、`OverrideMergerTests` → Rust 对应 + 同名
- `ProxyURISerializerTests`(18 个)→ Rust 对应
- `LogbookWriterTests`、`LogbookStoreTests`、`LogbookPathsTests` → Rust 对应
- `EngineRouterTests` → Rust 对应
- `EngineBenchmarkTests` → Rust 对应
- 命名风格:Rust 文件以行为命名(`override_store.rs`),不是 Suite 后缀

---

## 6. CI/CD 策略

### 6.1 工作流矩阵

| 工作流 | 触发 | 跑在 | 时长目标 |
|---|---|---|---|
| `riptide-windows/.github/workflows/ci.yml` | PR + push to master | windows-latest | < 12 min |
| `riptide-windows/.github/workflows/release.yml` | tag `vX.Y.Z` | windows-latest x2(arm64 + x64)| < 25 min |
| `riptide-windows/.github/workflows/lint.yml` | PR | windows-latest | < 5 min |
| `riptide-windows/.github/workflows/bench.yml` | nightly + release | windows-latest | < 15 min |
| `riptide-windows/.github/workflows/winget.yml` | release 完成 | ubuntu-latest | < 2 min |
| `riptide-windows/.github/workflows/chocolatey.yml` | release 完成 | windows-latest | < 8 min |

### 6.2 缓存策略
- `~/.cargo/registry` / `~/.cargo/git`
- `node_modules/`
- `target/`
- tauri 自身:`~/.cargo/bin/cargo-tauri.exe`

### 6.3 跨端协调
- macOS 和 Windows release 流程合并到顶层 `.github/workflows/release.yml`,按 platform 矩阵跑
- 当前 macOS `release.yml` 应扩展 `windows-latest` job
- 不再分开两个 `release.yml`

---

## 7. 风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| Tauri 2 minor 升级断裂 JS/Rust 一致 | 中 | 高 | A1.3 锁定 minor + CI check |
| SingBox 在 Windows 上的 Reality 支持不成熟 | 中 | 中 | C5 阶段做小规模 PoC,失败则保留 status-only |
| WSL2 / Hyper-V 用户 TUN 冲突 | 中 | 中 | D 阶段 docs 解释,`kill_switch` 提供逃生口 |
| Rust 测试覆盖率工具(coverage)配置复杂 | 中 | 中 | 用 `cargo-llvm-cov`,Phase B 末接入 |
| Playwright + tauri-driver 跑 E2E 慢 | 高 | 中 | 只跑关键 5 流程,fast lane |
| WARP 注册 API 漂移 | 低 | 中 | 把响应 body log 完整(macOS 端没记) |
| SurgeScript rquickjs binding 性能 | 中 | 中 | Phase 1 选 rquickjs,失败回退到 boa_engine |
| WebView2 在 Win7 缺失 | 中 | 中 | MSI 提示用户升级或装 Edge,文档明示最低 Win10 |
| 中文 / 跨端 i18n key 漂移 | 中 | 低 | 引入 i18n key lint,从 macOS JSON 拉 keys 对照 |
| 团队人力不足,Phase C 拉长 | 中 | 中 | 已按 2 人并行 12 周估算;若人手 < 2,优先砍 SceneEditor + SurgeScript |

---

## 8. 团队分工建议(2 人并行 12 周)

### 角色 A:Windows Rust 后端工程师
- 全程负责 A1.1/A1.3 + B1.1 + B1.2 + B2.1/2/3/4 + B3.1/2/4 + B4.1/2/3 + C2.1/2/3/6 + C5.1/2/3/5 + C6.1/2/3/4 + C7.1/2/4 + C8.1/2/4 + C9.1/2/3/5 + C11.1/2/4
- 工作量:~110 人天

### 角色 B:Windows 前端 + 测试 + CI 工程师
- 全程负责 A1.2 + A2 + A4 + B1.3 + B2.1(yaml 部分) + B3.3 + C1 + C2.4/5 + C3.1/2/3/4/5 + C4.2/3 + C5.4 + C7.3 + C8.3 + C9.4 + C10 + C11.3 + C13 + D1/2/3/4/5/6/7
- 工作量:~100 人天

> 工作量加总 210 人天 ≈ 12 周 × 5 天 × 2 人 × 1.75 负载(留 buffer)

---

## 9. 验证标准(每个 phase 结束的 go/no-go)

### Phase A go criteria
- [ ] 4 个 Windows bug 全修
- [ ] `riptide-windows/AGENTS.md` 存在且 ≥ 150 行
- [ ] `docs/decisions/0007-...` 存在
- [ ] `Scripts/bump-version.ps1` 跑通,4 个文件一致
- [ ] `cargo check` + `npm run tsc` + `npm run tauri build` 全绿

### Phase B go criteria
- [ ] Rust tests ≥ 53 个,全绿
- [ ] TS tests ≥ 11 个,全绿
- [ ] 4 个 CI 工作流第一次跑全绿
- [ ] Logbook 数据层 5 注入点全部接入
- [ ] URI Serializer 6 协议 round-trip 全过

### Phase C go criteria
- [ ] Rust tests ≥ 200 个
- [ ] TS tests ≥ 50 个
- [ ] 主路由从 7 涨到 9
- [ ] Override UI 完整闭环(创建 → 编辑 → 预览 → apply)
- [ ] Node QR 6 协议都生成得出来
- [ ] Deep link 6 action 全部跑通
- [ ] EngineRouter + Sing-box sidecar PoC 跑起来
- [ ] 9 个新 feature 全部 demo 给用户看

### Phase D go criteria
- [ ] VitePress 站可访问,Windows platform + build 文档完整
- [ ] 规则集仓库跟 macOS 端共用,`/rules` UI 可 install
- [ ] es 语言补全
- [ ] winget + choco + scoop 三个包都能装
- [ ] in-app update 走通 Tauri updater
- [ ] 7 份 ADR 全部在 `docs/decisions/`
- [ ] `.harness/reins/` 配 4 个 agent,`mavis team plan` 可用
- [ ] 全测试 ≥ 430 个,全绿
- [ ] `npm run tauri build` + 签名 + 上传 GitHub Release 全自动

---

## 10. 附录

### 10.1 macOS 参考实现文件清单(迁移目标)

```
Sources/Riptide/Logbook/        → riptide-windows/src-tauri/src/core/logbook/
  LogbookEntry.swift
  LogbookPaths.swift
  LogbookStore.swift
  LogbookWriter.swift
  ClosedConnectionWatcher.swift (W3-2b 后续)
Sources/Riptide/Override/       → riptide-windows/src-tauri/src/core/override/
  Override.swift
  OverrideStore.swift
  OverrideMerger.swift
  OverrideApplyError.swift
Sources/Riptide/Engines/        → riptide-windows/src-tauri/src/core/engines/
  ProxyEngine.swift
  EngineRouter.swift
Sources/Riptide/SingBox/        → riptide-windows/src-tauri/src/core/singbox/
  SingBoxPaths.swift
  SingBoxConfigGenerator.swift
  SingBoxAPIClient.swift
  SingBoxDownloader.swift
  SingBoxRuntimeManager.swift
Sources/Riptide/Performance/    → riptide-windows/src-tauri/src/bench/
  EngineBenchmark.swift
  BenchmarkReport.swift
Sources/Riptide/QRCode/         → riptide-windows/src/components/NodeQR/ (前端)
  QRCodeGenerator.swift
Sources/Riptide/Scripting/      → riptide-windows/src-tauri/src/core/scripting/
  ScriptEngine.swift
  SurgeScriptBridge.swift
Sources/Riptide/Subscription/ProxyURISerializer.swift
                                → riptide-windows/src-tauri/src/config/uri_serializer.rs
Sources/Riptide/MITM/           → riptide-windows/src-tauri/src/core/mitm/
  MITMConfig.swift
  MITMManager.swift
Sources/RiptideApp/Views/       → riptide-windows/src/components/
  Diagnostics/* → Logbook/*
  SceneEditorView.swift → SceneEditorView.tsx
  PerAppRuleEditor.swift → PerAppRuleEditor.tsx
  NetworkEnvironmentSettingsView.swift → NetworkEnvSettings.tsx
  UpdateSettingsView.swift → UpdateSettings.tsx
Sources/RiptideApp/App/         → riptide-windows/src/components/App/
  ThemeManager.swift → stores/riptide.ts(setTheme 已有)
  URLSchemeHandler.swift → App.tsx(handleDeepLink 已有)
  StatusBarController.swift → components/Tray/ (Win tray icon)
  TouchBarProvider.swift → (Mac only,不移植)
Sources/RiptideApp/Intents/     → (Mac only,不移植)
```

### 10.2 Windows 端独有的(可反向给 macOS)

```
riptide-windows/src-tauri/src/core/
  warp.rs         (WARP 匿名注册)
  kill_switch.rs  (TUN 崩溃 blackhole)
  tls_tricks.rs   (mihomo 握手修改)
  region_presets.rs (CN/Iran/Russia 规则集 + DNS overlay)
  recovery_watchdog.rs (sleep/wake + 网络变化)
  gateway.rs      (Windows ICS 网关模式)
```

### 10.3 关键工程指标(Phase D 结束时)

- **代码量**:Windows 总计约 35,000-40,000 LoC(Rust 22-25K + TS 13-15K)
- **测试覆盖**:≥ 430 tests,关键模块 ≥ 70% line coverage
- **CI 健康度**:4 个工作流 + 3 个发布工作流,PR 必跑
- **文档**:VitePress 站 ≥ 20 页,7 份 ADR
- **打包**:MSI + NSIS + winget + choco + scoop 5 渠道
- **i18n**:8 → 9 语言

### 10.4 不要做的(避免范围蔓延)

- 不在这轮重写 Tauri 1 → 2(已经是 2.10)
- 不上 iOS(明确 out of scope for v3.0.0)
- 不上 Linux 桌面打包(只 cargo check)
- 不上 Mac App Store 分发(MAC-APP-STORE-CHECKLIST.md 已存在但不在本计划内)
- 不实现 SubscriptionUserinfo 之外的 Dashboard 营销页
- 不引入新的 IPC 框架(继续用 tauri + invoke)
- 不重构现有 i18n 结构(只加 es)
- 不重写 NodeEditor 现有 1267 行(只是接入新功能)

---

## 11. 总结

| | 数量 | 工期 |
|---|---:|---:|
| 总任务 | 64 个 | 12 周 |
| 总人天 | ~210 | 12 周 × 2 人 × 1.75 负载 |
| 新增 Rust 代码 | ~13,000 LoC | |
| 新增 TS 代码 | ~8,000 LoC | |
| 新增测试 | ~430 个 | |
| 新增工作流 | 6 个 | |
| 新增 ADR | 4 份 | |
| 新增语言 | 1(es)| |
| 新增分发渠道 | 3(winget/choco/scoop)| |

跑完这份方案,Windows 端可以拍胸脯说:"功能、UI、测试、CI、文档 跟 macOS v2.4.1 持平"。v2.5.0(Reality/AnyTLS/Sing-box 默认开启)再起一份计划。
