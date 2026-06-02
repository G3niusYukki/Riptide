# Riptide 安装指南

> v3.0.0 GA 安装手册。如果你是第一次使用 Riptide,或者刚刚升级到 v3.0.0,请阅读本指南。
> 想要快速了解功能,请阅读 [README.md](../README.md)。

## 目录

- [系统要求](#系统要求)
- [安装方式](#安装方式) (推荐顺序)
  - [1. Homebrew (最简单)](#1-homebrew-最简单)
  - [2. DMG (图形安装)](#2-dmg-图形安装)
  - [3. 源码编译 (开发者)](#3-源码编译-开发者)
- [自动升级](#自动升级)
- [卸载](#卸载)
- [故障排除](#故障排除)
- [签名与公证](#签名与公证)

---

## 系统要求

- **操作系统:** macOS 14 (Sonoma) 或更高
- **磁盘空间:** 约 15 MB(应用本身),首次启动后会自动下载 mihomo 内核约 50 MB
- **TUN 模式:** 首次启动 helper 时需要管理员密码
- **网络:** 用于下载 mihomo 内核和订阅更新

---

## 安装方式

### 1. Homebrew (最简单)

```bash
brew tap G3niusYukki/riptide
brew install riptide
```

启动 Riptide:

- 从 Launchpad / Spotlight 搜索 "Riptide",或
- 终端执行 `open -a Riptide`

升级:

```bash
brew update && brew upgrade riptide
```

> **Tap 状态说明:** `G3niusYukki/homebrew-tap` 仓库会在第一次正式 release 后由 `.github/workflows/homebrew.yml` 自动创建。在那之前请使用 [DMG 安装](#2-dmg-图形安装)。

### 2. DMG (图形安装)

适合不熟悉命令行的用户。

1. 打开 [Releases 页面](https://github.com/G3niusYukki/Riptide/releases/latest)
2. 下载 `Riptide-X.Y.Z-universal.dmg` (支持 Intel 和 Apple Silicon)
3. 双击挂载 DMG
4. 拖动 **Riptide** 图标到 **Applications** 文件夹
5. 在 Applications 中双击启动

> **Gatekeeper 验证:** 正式 release 的 DMG 经过 Apple 公证 (notarized),首次启动 macOS 会自动验证签名,**不需要** 在终端运行 `xattr -cr` 之类的命令。如果你看到"无法验证开发者"或类似警告,说明你下载的不是正式 release,需要使用 Homebrew 或从源码构建。

### 3. 源码编译 (开发者)

适合需要修改代码或参与贡献的开发者。

```bash
# 克隆仓库
git clone https://github.com/G3niusYukki/Riptide.git
cd Riptide

# 下载 mihomo 内核 (System Proxy 模式需要)
./Scripts/download-mihomo.sh

# 构建所有 target
swift build

# 运行 GUI
swift run RiptideApp
```

> **本地构建未签名:** 首次启动会触发 macOS 隔离 (quarantine) 提示。开发时可以使用 [代码签名设置指南](signing-setup.md) 配置本地签名,或继续使用 unsigned build + 临时 `xattr` 解除 (不推荐生产环境)。

更多开发者信息,请参考 [CONTRIBUTING.md](../CONTRIBUTING.md)。

---

## 自动升级

Riptide 内置 [Sparkle](https://sparkle-project.org/) 自动升级:

- **触发方式:** 启动时后台检查,或 **Settings → Updates → Check Now**,或快捷键 **⌘⇧U**
- **签名验证:** 所有更新包都使用 edDSA 私钥签名,公钥嵌入 `Riptide.entitlements` 中,确保 appcast feed 不被篡改
- **渠道:** 稳定版 (Stable) 和 Beta 渠道可在 Settings 切换

---

## 卸载

### 应用本体

```bash
# 移除应用
rm -rf /Applications/Riptide.app
```

### 用户数据 (可选)

如果想彻底清除所有数据:

```bash
# 用户配置、缓存、日志、helper 等
rm -rf ~/Library/Application\ Support/Riptide/
rm -rf ~/Library/Caches/Riptide/
rm -rf ~/Library/Logs/Riptide/
rm -rf ~/Library/LaunchAgents/com.riptide.client.plist 2>/dev/null
rm -rf ~/Library/Preferences/com.riptide.app.plist 2>/dev/null

# 移除 helper (需要管理员密码)
sudo rm -rf /Library/Application\ Support/Riptide/
sudo rm -rf /Library/LaunchDaemons/com.riptide.helper.plist 2>/dev/null
```

### Homebrew 安装的卸载

```bash
brew uninstall riptide
brew untap G3niusYukki/riptide
```

---

## 故障排除

### 启动问题

**"无法打开应用,因为它来自身份不明的开发者"**

- 正式 release 的 DMG 已经过 Apple 公证,不应该出现此提示。如果你看到了:
  - 确认你下载的是 [GitHub Releases](https://github.com/G3niusYukki/Riptide/releases) 页面上的正式版本,而不是 fork 或镜像
  - 验证 DMG 的 SHA256 校验和
  - 临时解决方案 (仅供本地 dev build): `xattr -cr /Applications/Riptide.app`

**App 启动后立即崩溃**

- 查看日志: `~/Library/Logs/Riptide/`
- 查看 Crash Reports: `~/Library/Logs/DiagnosticReports/`
- 提交 issue 时附上日志和系统信息 (macOS 版本、芯片型号)

### TUN 模式问题

**TUN 模式启动失败,提示 "Operation not permitted"**

- 重新安装 privileged helper: **Settings → Helper → Reinstall**
- 检查 System Settings → Privacy & Security → Full Disk Access 是否授权 Riptide

**TUN 接口创建后无网络**

- 检查 mihomo 是否正常启动: 查看 Logs 标签页
- 尝试切换回 System Proxy 模式验证基础网络

### 网络/DNS 问题

**浏览器无法访问任何网站**

- 检查菜单栏图标状态,确认模式已启用
- 查看 Diagnostics: **Settings → Diagnostics → Run All Checks**
- 尝试 `riptide validate` 验证配置文件

**DNS 解析失败**

- 切换 nameserver: **Settings → DNS → Custom** 测试不同 DNS (如 `1.1.1.1` 或 `8.8.8.8`)
- 检查 System Preferences → Network → Advanced → DNS 是否被代理接管

### 性能问题

**连接速度慢**

- 运行 **Group Selector** 测速: 选中代理组 → **Latency Test**
- 切换到 url-test 模式自动选择最低延迟节点

**内存占用过高**

- 减少并发连接数: **Settings → Advanced → Max Connections**
- 关闭不使用的代理组

---

## 签名与公证

v3.0.0 GA 的代码签名和公证由 CI/CD 自动处理:

- **代码签名:** Apple Developer ID Application 证书
- **公证 (Notarization):** Apple `notarytool`
- **本地签名 / 手动签名:** 参考 [signing-setup.md](signing-setup.md)

如果你 fork 了 Riptide 并希望分发自己的构建:

1. 加入 [Apple Developer Program](https://developer.apple.com/programs/) ($99/年)
2. 创建 Developer ID Application 证书
3. 在 GitHub 仓库配置以下 Secrets:
   - `MACOS_CERTIFICATE` (Base64 编码的 p12)
   - `MACOS_CERTIFICATE_PWD`
   - `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`
4. Release workflow 会自动签名 + 公证

详细步骤见 [signing-setup.md](signing-setup.md)。

---

## 反馈

遇到问题?

- 提交 issue: <https://github.com/G3niusYukki/Riptide/issues>
- 安全相关问题: 私下联系 maintainer,不要公开 issue
- 文档改进: 直接 PR 修改本文件
