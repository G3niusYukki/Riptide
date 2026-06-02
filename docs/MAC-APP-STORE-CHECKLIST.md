# Mac App Store 提交准备清单

> **状态 (2026-06-02):** 准备就绪,但 v3.0.0 GA 不立即提交 Mac App Store。
> 预计提交时间: v3.1.0 或 v3.2.0 (根据用户反馈决定)。
>
> 本文档是 v3.0.0 GA 之后的 roadmap 项,**不是** 当前 GA 发布的承诺。Riptide v3.0.0 GA 通过 DMG + Homebrew + Sparkle 三渠道分发。

---

## 为什么 v3.0.0 GA 不上 Mac App Store?

| 限制 | 说明 |
|------|------|
| **App Sandbox** | MAS 强制要求开启 Sandbox。当前 `Riptide.entitlements` 中 `app-sandbox: false` (符合直接分发需求) |
| **Helper Tool 限制** | MAS 不允许使用 `SMAppService` 安装 privileged helper。Helper 必须用 Network Extension (额外申请) |
| **TUN 模式** | 需 `com.apple.developer.networking.networkextension` 证书和 Packet Tunnel Provider extension,需重新设计架构 |
| **IAP 抽成** | 如使用订阅功能,30% 抽成会显著影响商业模式 |
| **审核周期** | MAS 审核通常 24-48h,版本迭代速度受限 |

## 替代分发渠道 (已就绪)

- ✅ **直接分发 DMG** (代码签名 + Apple 公证,见 `.github/workflows/release.yml`)
- ✅ **Homebrew** (`.github/workflows/homebrew.yml` 自动更新 tap)
- ✅ **Sparkle 自动升级** (`.github/workflows/sparkle.yml` + edDSA 签名)

---

## 必要条件 (提交前需完成)

### 1. Apple Developer Program

- [ ] 已加入 Apple Developer Program ($99/年)
- [ ] 已知 Team ID (10 字符,可在 Apple Developer Portal 查看)
- [ ] App Store Connect 账户可访问且有创建 App 权限
- [ ] 同意最新的 [Apple Developer Program License Agreement](https://developer.apple.com/terms/)

### 2. 应用元数据 (App Store Connect)

- [ ] **应用名称:** Riptide
- [ ] **副标题:** "Native macOS proxy client"
- [ ] **类别:** Developer Tools (主) / Utilities (次)
- [ ] **关键词 (100 字符以内):** proxy, network, clash, mihomo, surge, vpn, tunnel
- [ ] **支持 URL:** <https://github.com/G3niusYukki/Riptide/issues>
- [ ] **隐私政策 URL:** 待创建 (建议放 `docs/PRIVACY.md` 并部署到 GitHub Pages)
- [ ] **营销 URL (可选):** <https://riptide.app>
- [ ] **描述 (4000 字符以内):** 中文 + 英文两个版本
- [ ] **What's New (每个版本):** 增量 changelog
- [ ] **截图:** 1280x800 (最少 1 张,推荐 5 张展示主要功能)
- [ ] **App 图标:** 1024x1024 PNG (无 alpha 通道,无圆角)
- [ ] **年龄分级问卷:** 完成分级问卷
- [ ] **版权信息:** 持有人 + 年份
- [ ] **联系信息:** 姓名、邮箱、电话

### 3. 技术要求 (代码与配置)

- [ ] **App Sandbox 启用** (`com.apple.security.app-sandbox = true` in entitlements)
- [ ] **entitlements 调整:** 移除 helper 依赖,精简网络权限,使用 MAS 允许的 API
- [ ] **Hardened Runtime 启用** (已在 `Riptide.entitlements` 中配置)
- [ ] **没有 NSAllowsArbitraryLoads** (或提供详细文档化理由)
- [ ] **没有 Mach-O 异常技术** (无运行时代码注入,无 dylib 劫持)
- [ ] **没有禁用 App Review 的 API** (无私有 API 调用)
- [ ] **Helper Tool 重构:** 必须用 Network Extension (Packet Tunnel) 替代 `SMAppService`
- [ ] **TUN 模式重构:** 从 sudo + gVisor 改为 Network Extension + PacketTunnelProvider
- [ ] **存档 (Archive) 配置:** 在 Xcode 中生成 Archive (不是 `swift build`)

### 4. 法律与合规

- [ ] **隐私标签 (Privacy Labels):** 在 App Store Connect 中声明所有数据收集
- [ ] **加密声明:** Riptide 使用标准 TLS 和加密,需提交 [CCATS](https://www.bis.doc.gov/index.php/policy-guidance/encryption) 申报或自分类报告
- [ ] **出口合规:** 加密软件需在 App Store Connect 提交年度加密使用报告
- [ ] **第三方许可:** 列明所有依赖 (mihomo, Sparkle, Yams, swift-certificates) 的许可证
- [ ] **用户协议 (EULA):** 或使用 Apple 标准 EULA

### 5. 测试与质量

- [ ] **App Review 指南合规:** <https://developer.apple.com/app-store/review/guidelines/>
- [ ] **Sandbox 兼容性测试:** 开启 Sandbox 后所有功能仍正常工作
- [ ] **崩溃率 < 0.1%:** 在 TestFlight Beta 测试期间收集数据
- [ ] **多语言测试:** zh-Hans, en 两种语言至少完整测试
- [ ] **辅助功能测试:** 支持 VoiceOver、键盘导航
- [ ] **深色模式适配:** UI 在深色模式下无视觉问题
- [ ] **macOS 版本兼容测试:** macOS 14, 15 (最新两个稳定版)

---

## 提交流程

### 第一步: 创建 App Store Connect 条目

1. 登录 [App Store Connect](https://appstoreconnect.apple.com)
2. 点击 **My Apps** → **+** → **New App**
3. 选择平台: **macOS**
4. 填写:
   - **Name:** Riptide
   - **Primary Language:** English (United States)
   - **Bundle ID:** `com.riptide.app` (必须在 Apple Developer 注册)
   - **SKU:** `riptide-macos-v3`

### 第二步: 准备构建

1. 在 Xcode 中打开项目 (需新建 `.xcodeproj` 或 `.xcworkspace` — 当前 SwiftPM 项目需要转换)
2. 配置 **Signing & Capabilities**:
   - Team: 你的 Apple Developer Team
   - Signing Certificate: **Apple Distribution**
   - Provisioning Profile: **Mac App Store**
3. 配置 entitlements:
   - 复制 `Riptide.entitlements` 并调整 (开启 sandbox,移除 helper 相关项)
4. 启用 **Hardened Runtime** (Signing & Capabilities → Hardened Runtime)
5. 选择 **Product → Archive**
6. 在 Organizer 中: **Distribute App** → **App Store Connect** → **Upload**

### 第三步: 上传与审核

1. 在 App Store Connect 中,选中上传的构建
2. 填写版本信息 (描述、截图、关键词等)
3. 选择构建版本号
4. 提交审核
5. 等待审核 (通常 24-48h,首次提交可能更长)
6. 如被拒绝,根据反馈修改后重新提交

### 第四步: 发布

1. 审核通过后,选择手动发布或自动发布
2. 发布后即可在 Mac App Store 搜索到
3. 监控用户反馈和崩溃报告,准备后续更新

---

## 已知风险与限制

| 风险 | 影响 | 缓解策略 |
|------|------|----------|
| **Sandbox 限制 mihomo 启动** | mihomo 作为 sidecar 需写入特定目录,App Sandbox 会限制 | 使用 `containerURL(forSecurityApplicationGroupIdentifier:)` 或 App Group |
| **TUN 模式需 Network Extension** | 需额外申请 Apple 开发者权限 + 重写 TUN 架构 | 在 v3.1.0 提前规划,准备 Network Extension 申请 |
| **Helper Tool 不能用 SMAppService** | MAS 限制,必须用 Network Extension 或 System Extension | 重构为 System Extension (需苹果额外批准) |
| **审核被拒** | 涉及 VPN/代理的 App 经常被严格审查 | 准备详细的功能说明文档,提前与 Apple 沟通 |
| **IAP 30% 抽成** | 如添加订阅功能,收入大幅缩水 | 考虑使用 Paddle/FastSpring 等第三方支付,或仅靠捐赠 |
| **版本号冲突** | MAS 不允许覆盖已有版本号 | 使用单调递增的版本号 (3.0.0 → 3.1.0 → 3.2.0) |

---

## 不提交 Store 的替代方案 (当前)

- ✅ **DMG 直接分发** (代码签名 + Apple 公证,`xattr -cr` 已不需要)
- ✅ **Homebrew** (自动 tap 更新)
- ✅ **Sparkle 自动升级** (edDSA 签名)
- ✅ **独立分发** (绕过 MAS 30% 抽成)
- ✅ **快速迭代** (无需等待 Apple 审核)

---

## 当前完成状态 (2026-06-02)

### ✅ 已完成 (基础设施就绪)

- [x] **Sparkle edDSA 密钥脚本** — `Scripts/sign-sparkle-update.sh` (keygen + sign 子命令)
- [x] **Sparkle 公钥占位** — `Riptide.entitlements` 中 `SUPublicEDKey` (待替换为真实公钥)
- [x] **公钥记录文件** — `Resources/sparkle-pubkey.pem` (占位符)
- [x] **代码签名 entitlements** — `Riptide.entitlements` (sandbox=false, hardened runtime)
- [x] **本地签名脚本** — `Scripts/setup-signing.sh`
- [x] **构建脚本** — `Scripts/build-release.sh` (生成 universal DMG)
- [x] **Release workflow** — `.github/workflows/release.yml` (macOS / Windows / Linux 三平台)
- [x] **Sparkle workflow** — `.github/workflows/sparkle.yml` (签名 + 部署 appcast)
- [x] **Homebrew workflow** — `.github/workflows/homebrew.yml` (自动更新 tap)
- [x] **INSTALL 文档** — `docs/INSTALL.md` (中文,覆盖三种安装方式)
- [x] **签名设置文档** — `docs/signing-setup.md` (macOS + Windows 双平台)
- [x] **README 移除 `xattr -cr`** — 仅在正向语境中提及 (说明已不需要)

### ⏳ 待完成 (需用户操作或后续版本)

- [ ] **真实 Developer ID 证书** — 等待用户提供 `MACOS_CERTIFICATE` 等 Secrets
- [ ] **真实 Apple 公证** — 等待 `APPLE_ID` / `APPLE_TEAM_ID` / `APPLE_APP_PASSWORD` Secrets
- [ ] **真实 Sparkle 私钥** — 等待 `SPARKLE_PRIVATE_KEY_PEM` Secret
- [ ] **Homebrew tap 仓库** — `G3niusYukki/homebrew-tap` 需首次 release 时由 workflow 创建
- [ ] **macOS App Store 提交** — v3.1.0 或 v3.2.0 计划,需先重构 Sandbox + TUN 架构
- [ ] **App Store Connect 元数据** — 描述、截图、隐私政策 URL 等
- [ ] **TestFlight Beta 测试** — 提交前 1-2 个版本的 Beta 测试周期
- [ ] **隐私政策** — `docs/PRIVACY.md` 文档 (需用户/法务审查)

### 🔮 远期目标

- [ ] **Network Extension 申请** — 为 v3.1.0 准备 TUN 模式重构
- [ ] **公证自动化** — 当前 notarytool 在 CI 中运行,需完善错误处理和重试
- [ ] **App Store 国际分发** — 当前计划仅分发到美国区,如需其他地区需额外配置

---

## 联系方式

- **仓库:** <https://github.com/G3niusYukki/Riptide>
- **Issues:** <https://github.com/G3niusYukki/Riptide/issues>
- **Discussions:** <https://github.com/G3niusYukki/Riptide/discussions>

如需协助 MAS 提交,请在 issue 中使用 `mas-submission` 标签。
