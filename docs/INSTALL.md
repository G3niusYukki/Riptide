# Riptide 安装指南

## 系统要求

- macOS 14+ (Sonoma)
- Windows 10/11
- 至少 100MB 可用磁盘空间
- 网络连接 (用于下载 mihomo 内核)

## macOS 安装

### 通过 Homebrew (推荐)

```bash
brew tap G3niusYukki/riptide
brew install riptide
```

### 手动安装

1. 从 [GitHub Releases](https://github.com/G3niusYukki/Riptide/releases) 下载最新版本
2. 解压 `Riptide-macos-universal.zip`
3. 将 `Riptide.app` 拖到 Applications 文件夹
4. 首次启动时右键点击并选择"打开"（绕过未签名应用限制）

### 从源码构建

```bash
# 克隆仓库
git clone https://github.com/G3niusYukki/Riptide.git
cd Riptide

# 下载 mihomo 内核
./Scripts/download-mihomo.sh

# 构建
swift build

# 运行
swift run RiptideApp
```

## Windows 安装

### 通过安装程序

1. 从 [GitHub Releases](https://github.com/G3niusYukki/Riptide/releases) 下载 `.msi` 安装包
2. 运行安装程序
3. 按照向导完成安装
4. 从开始菜单启动 Riptide

### 便携版

1. 下载 `Riptide-windows-portable.zip`
2. 解压到任意目录
3. 运行 `Riptide.exe`

## 首次配置

### 1. 自动下载内核

首次启动时，Riptide 会自动检测并下载 mihomo 内核。

如果自动下载失败，可以手动下载：
```bash
# macOS
curl -L https://github.com/MetaCubeX/mihomo/releases/download/v1.18.0/mihomo-darwin-amd64-v1.18.0.gz | gunzip > ~/.config/riptide/mihomo
chmod +x ~/.config/riptide/mihomo

# Windows
# 下载 https://github.com/MetaCubeX/mihomo/releases/download/v1.18.0/mihomo-windows-amd64-v1.18.0.zip
# 解压到 %APPDATA%\Riptide\mihomo\
```

### 2. 导入配置

支持两种方式：
- **文件导入**: 点击"导入配置"，选择 `.yaml` 或 `.yml` 文件
- **订阅导入**: 点击"添加订阅"，输入订阅 URL

### 3. 选择代理模式

- **系统代理**: 只代理 HTTP/HTTPS 流量 (推荐日常使用)
- **TUN 模式**: 代理所有流量 (需要管理员权限)
- **直连模式**: 不经过代理
- **全局模式**: 所有流量通过代理

## 故障排除

### macOS

**"无法打开应用，因为无法验证开发者"**
```bash
xattr -cr /Applications/Riptide.app
```

**TUN 模式无法启动**
- 需要安装特权助手
- 在设置中点击"安装助手"

### Windows

**启动失败**
- 安装 [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)
- 安装 Visual C++ Redistributable

**系统代理无法设置**
- 以管理员身份运行 Riptide
- 检查防火墙设置

## 更新

### macOS (Homebrew)
```bash
brew update
brew upgrade riptide
```

### 手动更新
下载最新版本并替换旧版本。

## 卸载

### macOS
```bash
brew uninstall riptide
brew untap G3niusYukki/riptide
```

### Windows
使用"添加或删除程序"卸载，或删除便携版目录。
