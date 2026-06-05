# Riptide Windows Changelog

> Windows 端 (`riptide-windows/`, Tauri 2 + Rust + React/TypeScript) 的版本变更记录。
> 所有条目反向自顶 `CHANGELOG.md` 与 `git log riptide-windows/` 整理,
> 与顶 `CHANGELOG.md` 内容保持一致。本文件直到 v2.4.1-Win.0 之前一直没有
> 同步更新,2026-06-05 Phase A (A1.4) 一次性反向补全 v0.1.0 → v2.4.1。

---

## [2.4.1] — 2026-06-04

> 顶 `CHANGELOG.md` v2.4.1 主要面向 macOS (Helper LPE 修复 / Sing-box skeleton /
> EngineBenchmark)。Windows 端此版本无新功能,只是版本号 bump。

### Changed
- 版本号 bump:`2.4.0` → `2.4.1` (`riptide-windows/package.json`、
  `src-tauri/Cargo.toml`、`src-tauri/tauri.conf.json`、`README.md`)
  (ref: 60b231f)

### Known limitations
- Helper LPE-class 修复只针对 macOS XPC;Windows 端 SCM-registered
  `riptide-tun-service.exe` 不受影响 (ref: 顶 CHANGELOG L10-L22)
- Sing-box skeleton / EngineBenchmark 暂时仅 macOS 落地 (ref: 顶 L35-L48)

---

## [2.4.0] — 2026-06-03

> 顶 `CHANGELOG.md` v2.4.0 / W3-2a 主要面向 macOS (Logbook 数据层 + 诊断 tab)。
> Windows 端无对应交付,只 bump 版本号。

### Changed
- 版本号 bump:`2.3.0` → `2.4.0` (ref: 1f58b5f)

### Known limitations
- Logbook (`LogbookStore` / `LogbookWriter` / `ClosedConnectionWatcher`)、
  诊断 tab (EventLogSection / ConnectionHistorySection) 暂未在 Windows 端
  落地,Phase B (B3 Logbook 数据层) 是 W2 之后的工作
  (ref: 顶 L51-L83, 见 `docs/WINDOWS-CATCHUP-PLAN.md` B3)

---

## [2.3.0] — 2026-06-02

> v2.3.0 顶 `CHANGELOG.md` (Override 数据层 / Decision ADRs / Visual rule editor
> hit preview / Node QR) 全部面向 macOS。Windows 端此版本无新功能,只 bump。

### Changed
- 版本号 bump:`2.2.0` → `2.3.0` (ref: a8b8462)

### Known limitations
- Override 数据层 / ADR-0001~0003 / Visual rule editor hit preview /
  Node QR (`ProxyURISerializer` + `QRCodeGenerator`) 全部 macOS-only
  (ref: 顶 L84-L143)
- `Override` UI / `OverrideStore` / `ProxyURISerializer` Windows 端要等
  Phase C (C2 Override UI + C3 Node QR UI) (ref: 顶 L138-L141)

---

## [2.2.0] — 2026-05-29

> v2.2.0 集中修了"三平台构建"问题:Swift build / Linux cargo check /
> Windows TS build。Windows 端有 4 个 fix + 7 个 Linux cross-compile 修复
> (虽然 Linux 端不是 Windows 代码,但 `src-tauri/` 是共享 tree)。

### Added
- `WindowsDirs::config_dir()` 用于 `rewrite.rs` 的原子写 (tmp + rename 模式)
- 4 个 Tauri 命令接入 `services/tauri.ts`:`enableGateway` / `disableGateway` /
  `isGatewayEnabled` / `getGatewayDevices` + `GatewayDevice` 类型
- `Gateway` 模块加 `#[cfg(windows)]` gate,Linux 编译不拉
  (ref: 2e7ae2d, 6ebc692)

### Fixed
- TS 编译错误:Dashboard `Download` / `useState` 未使用 import、
  `setActiveTab` 缺失 store method;`RecoveryTab` 传了不存在的 `showDiagnostics`
  prop (ref: 3fdda0f)
- `RewriteAction` 改为 flat struct (action_type + 可选字段),
  跟 `serde` enum 内部 tagged mismatch 解开;TS 端同步改 interface
  (ref: 91e0188)
- Linux cross-compile fix (虽然目标是 Linux,但改的是共享 tree):
  `WindowsDirs` 跨平台化、`creation_flags` → `no_window`、`#[cfg]` guards
  (ref: 75d2bdf, e6bab70, 72ad377, 81081b8, 8d4c6a3, 3578b3e)
- 三平台构建修复:Swift 编译、Linux cargo check、Docs deploy
  (ref: 12915d3, 9764782)

### Known limitations
- 此版本未加 Windows 端 Logbook / Override / CodeMirror;UI parity
  仍是 W2-W9 工作 (ref: 顶 L212-L277)

---

## [2.1.0] — 2026-05-27

> v2.1.0 是 Windows 端第一个 macOS 同步"急追"版本。3 个 feat(windows) 提交
> 把 Dashboard quota / connection details / 8 语言 / DNS policy / diagnostics
> tab、HTTP Rewrite 引擎 + Tauri updater、Appearance themes + Gateway ICS
> 都拉到了与 macOS v2.1.0 同档。

### Added
- **Dashboard 配额与连接面板** — 订阅 quota 卡片 (用量条 + 到期倒计时) +
  recent connections 列表;Connections 页展开行带 5-tuple、rule hit tracing、
  proxy chain、traffic + timing 统计 (ref: c535c56)
- **i18n 8 语言** — zh-CN / en-US / ja-JP / ko-KR / ru-RU / fa-IR /
  pt-BR / vi-VN,real translations (比 macOS v2.1.0 少 es,
  这是 v3 之前的已知 gap) (ref: c535c56, 顶 L313)
- **DnsTab** — Settings 下新 dns 子页,`nameserver-policy` 编辑器
  (每行 `domain=resolver`) (ref: c535c56)
- **Diagnostics tab** — Settings 下新子页 (Phase 1 entry,
  后续 Phase A1.1 + C1 完整化) (ref: c535c56)
- **HTTP Rewrite 引擎** — `config/rewrite.rs` + `cmds/rewrite.rs`
  (RewriteRule CRUD + JSON 持久化),5 个 Tauri 命令
  (get/set/add/delete/toggle),新 `RewriteTab.tsx` 含 pattern 编辑器、
  action 选择器、per-rule enable/disable;Settings 8 tabs (ref: e712953)
- **Tauri auto-update 接入** — `tauri-plugin-updater` (Cargo.toml + lib.rs +
  tauri.conf.json),pubkey 占位 `REPLACE_WITH_YOUR_PUBLIC_KEY` 等 Phase D 配
  (ref: e712953, 顶 L300 Sparkle 2.9.2 对位)
- **AppearanceSettings** — 5 主题 picker 实际激活
  (dark / light / nord / dracula / solarized-dark),主题 token 已生效
  (ref: 6397645, 0b9b0d8)
- **GatewayTab** — Windows ICS (Internet Connection Sharing) 通过 `netsh`
  实现 enable/disable/show devices from ARP cache;`core/gateway.rs` +
  `cmds/gateway.rs` 共 4 个 Tauri 命令;Settings 10 tabs
  (ref: 6397645)
- 版本号 bump:`2.0.0` → `2.1.0` (ref: e712953, 8405815)

### Known limitations
- Tauri updater pubkey 仍占位,Phase D (D5) 才配 signing keypair
  (ref: 顶 L300 + `tauri.conf.json:84`)
- 8 语言 (缺 es) 计划在 Phase D (D3) 补 (ref: 顶 L313, 顶 L13 现状表)

---

## [2.0.0] — 2026-05-18

> v2.0.0 是 Windows 端从 "Phase 0-3 production-ready" 跳到 "macOS 同档
> 8 语言 + CodeMirror 编辑器 + semantic theme" 的拐点。1 个 Stream C/D 跨端
> 提交 (4e58ad1) 一次把 CodeMirror 6 YAML 编辑器 + semantic theme tokens
> 全部带进 Windows 端。

### Added
- **Stream D — Semantic Theme System** (4e58ad1) — 新 `tokens.css` 引入
  semantic theme tokens,`App.css` 删 `.light` overrides,新 `useTheme.ts`
  hook + `AppearanceSettings.tsx` 组件 (ref: 4e58ad1)
- **Stream C — CodeMirror 6 YAML Editor** (4e58ad1) — 新 `YamlEditor.tsx`
  组件 + `yamlAutocomplete.ts` 提供 Clash YAML completions;`package.json`
  增 `@codemirror/lang-yaml` / `@codemirror/lint` / `@codemirror/state` /
  `@codemirror/view` / `codemirror` 依赖 (ref: 4e58ad1)
- 版本号 bump:`1.7.0` → `2.0.0` (ref: cdeaa43)

### Fixed
- 恢复 CI checks (6081bcf) (ref: 6081bcf)

---

## [0.2.0] — 2026-05-15

> 覆盖 v0.1.0 与 v2.0.0 之间所有 Windows 端交付:从 Tauri 2 骨架 → mihomo API
> 集成 → Phase 1-4 体验增强 → 编译修复 → Phase 0-3 production → WARP /
> NodeEditor / Theme / Polish。顶 `CHANGELOG.md` v2.0.0 (L334-L350) 的
> "Initial Release" 是 macOS 视角;Windows 端到 v0.2.0 才补齐 7 tab +
> Phase 0-3 完整运行 + 8 语言。

### Added
- **Tauri 2 骨架 + mihomo 集成** — Tauri 2.0 + React 19 + TS + Vite +
  TailwindCSS v4;Sidebar/Header/Dashboard(实时流量) + Proxies + Profiles
  (CRUD) + Rules + Connections + Settings;mihomo 进程生命周期、sysproxy
  crate、SCM 服务 scaffolding;CI workflow 起跑
  (ref: e8c125f, 09c0c8c, 4e5e926, c64ce71, 2e8f117..0a5c8cc, 5cff2e9)
- **Phase 1-4 体验增强** (4db9178) — Phase 1 fix(winapi dep、
  `static mut UB` in `windows_sysproxy`、Settings 开关、Rules 走真实
  mihomo API、capabilities 补全);Phase 2 exp(recharts 实时 traffic area
  chart、Logs 走 mihomo REST stream、YAML profile editor 弹窗);
  Phase 3 advanced(Share URI parser: ss/trojan/vless/vmess/hysteria2
  一键 import、i18n infra zh-CN/en-US、toast 系统);Phase 4 polish
  (GitHub Releases update checker、config templates) (ref: 4db9178)
- **Phase 0-3 production-ready + Phase 4/5 partial** (b28a89b) —
  Phase 0 Foundation:profile system disk-backed + stable UUID、
  `active.json` 持久化、mihomo auto-download + SHA-256 verify、
  real `generate_config` merge、single-instance guard、tracing logging;
  Phase 1 Modes & Service:**mihomo TUN via gVisor** (取代 wintun-direct
  死路)、**`riptide-tun-service.exe` 注册 SCM 跑 SYSTEM mihomo**、
  一次性 UAC elevation 装/卸 service、**system proxy drift guard** (3s
  轮询,自动恢复)、Mode Coordinator 序列化 Off/SystemProxy/TUN 切换;
  Phase 2 Subs & Config:subscription auto-refresh + `Subscription-Userinfo`
  解析、GeoIP/GeoSite auto-download、DnsPolicy overlay (DoH/DoT/DoQ +
  FakeIP)、WebDAV sync (HTTPS-only, DPAPI-encrypted pwd, zip backup)、
  剪贴板 import、`riptide://` deep link handler;
  Phase 3 Resilience:mihomo crash watcher (expected vs unexpected exit)、
  **kill_switch** (TUN 崩溃时 route-table blackhole)、
  **recovery_watchdog** (sleep/wake + 网络变化检测)、
  diagnostics report (versions, state, log tail;无 secrets);
  Phase 4 partial:**region_presets** (CN/Iran/Russia 规则 + DNS overlay)、
  **tls_tricks** (client-fingerprint stamping);
  Phase 5 partial:autostart + silent start、system tray menu、
  global hotkeys (Ctrl+Alt+P / Ctrl+Alt+M)、theme infra、
  i18n (zh-CN/en-US 完整, fa/ru/ja seeded)、tabbed Settings UI
  (ref: b28a89b)
- **Cloudflare WARP 匿名注册** — `core/warp.rs` x25519-dalek 密钥对 +
  CF `api.cloudflareclient.com/v0a2158/reg` POST + `reserved` 字节解码 +
  Clash `wireguard` proxy 装配;Profiles 工具栏新 "WARP" 按钮
  (ref: 849e7e8)
- **Node editor** — 协议专用表单 (SS/VMess/VLESS+Reality/Trojan/Hy2/
  TUIC/Snell/HTTP/SOCKS5),共享 transport block (WS/gRPC),YAML round-trip
  走 `serde_yaml::Value` 保留未知 key;AnyTLS 一级代理 + ShadowTLS 走
  SS 插件路径 (ref: 7a1de08, b8fe0ac)
- **Light theme + appearance** — `.light` CSS override layer 不改组件
  markup 切主题;Settings → About 加"外观"卡片 (主题 + 语言选择器)
  (ref: 0b9b0d8)

### Changed
- **UI polish** — Sidebar 64→208px 加品牌块 + 路由高亮 + 模式指示器;
  Header 加 local-proxy 地址 tag;Dashboard `StatCard` tone halo 统一
  (ref: 8289482)
- **Tauri build 解锁** — pin JS `~2.10` 对齐 Rust 2.10.3,Cargo.toml
  加 `default-run = "riptide-windows"` (ref: aefc5c6)

### Fixed
- **Unify data paths** — 全部走 `WindowsDirs` 避免 `%APPDATA%\com.riptide.app\`
  与 `%APPDATA%\Riptide\` 分裂;mihomo 落 `%APPDATA%\Riptide\mihomo\`
  (ref: 542c59e)
- **Hotkey 冲突容忍** — `register_default_hotkeys` 改 per-key
  `try_register`,单冲突不波及其他 (ref: 542c59e)
- **QueryClientProvider 包装** — 补 `QueryClient` 单例
  (retry 1, no refetch-on-focus) (ref: 1524a07)
- **MIHOMO_SHA256 pin** — v1.18.10 Windows amd64-compatible hash 填入
  `core/mihomo_bootstrap.rs` (ref: 82cf3d1)
- 9 个 build/compile 修复 (9d1b3ac、2ea60d7、f04c713、70b8fca、26fe898、
  064b7e8、cd480d8、91793ad 等) (ref: 9d1b3ac..91793ad)

### Known limitations
- TUN 之前 wintun-direct 是死路,b28a89b 切到 gVisor 行为已重做
- MIHOMO_SHA256 在 82cf3d1 之前是空常量、release-blocker 已知
- Full auto-updater (5.5) 等 Phase D (D5) 配 signing keypair
  (ref: `tauri.conf.json:84` 占位)

---

## [0.1.0] - 2026-04-12

### Added
- Initial Windows port of Riptide
- Core proxy functionality via mihomo
- System proxy toggle
- Basic profile management
- Connection monitoring
- Traffic statistics display
- Dark theme UI
- Windows proxy manager with mihomo integration
- System proxy configuration via WinHTTP API
- TUN mode support using wintun driver
- Full profile management (CRUD)
- Global hotkeys (Ctrl+Alt+P, Ctrl+Alt+M)
- System tray integration
- NSIS and MSI installer support
- WebView2 bootstrapper in installer
- Multi-language installer support (zh-CN, en-US)

### Changed
- Optimized Windows-specific UI styling for better font rendering
- Improved connection list grid layout for Windows displays
- Enhanced proxy card spacing and alignment

### Fixed
- UI alignment issues between macOS and Windows
- Font rendering on Windows (using Segoe UI font stack)
- Scrollbar styling consistency
- Input field focus states

### Known limitations
- TUN mode requires manual wintun.dll installation
- Hotkeys may conflict with other applications
- MSI installer requires elevated privileges for WebView2 installation
