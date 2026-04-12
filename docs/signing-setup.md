# 代码签名设置指南

本文档介绍如何为 Riptide 配置 macOS 和 Windows 平台的代码签名，用于发布可信任的软件包。

## macOS 代码签名

### Apple Developer 账户

1. **加入 Apple Developer Program** ($99/年)
   - 访问 [Apple Developer](https://developer.apple.com) 注册
   - 需要用于分发的 Developer ID Application 证书

2. **创建 Developer ID Application 证书**
   - 登录 [Apple Developer Portal](https://developer.apple.com/account/resources/certificates/list)
   - 选择 Certificates → Add → Developer ID Application
   - 按照向导生成证书签名请求 (CSR) 并下载证书

3. **导出 p12 证书**
   - 在 Keychain Access 中找到导入的证书
   - 右键证书 → 导出
   - 选择 Personal Information Exchange (.p12) 格式
   - 设置导出密码并保存

### GitHub Secrets 配置

在仓库 Settings → Secrets and variables → Actions 中添加以下 secrets:

| Secret Name | Description |
|-------------|-------------|
| `MACOS_CERTIFICATE` | Base64 编码的 p12 证书 |
| `MACOS_CERTIFICATE_PWD` | p12 证书导出密码 |
| `MACOS_KEYCHAIN_PWD` | 临时钥匙串密码 (任意随机字符串) |
| `APPLE_ID` | 用于公证的 Apple ID 邮箱 |
| `APPLE_TEAM_ID` | Apple Developer Team ID (10字符) |
| `APPLE_APP_PASSWORD` | App 专用密码 (非 Apple ID 密码) |

### 证书转换命令

```bash
# 将 .p12 转为 base64
cat certificate.p12 | base64 | pbcopy
# 粘贴到 GitHub Secrets 中的 MACOS_CERTIFICATE 字段

# 或使用 certutil (Windows)
certutil -encode certificate.p12 certificate-base64.txt
```

### 获取 App 专用密码

1. 访问 [Apple ID 管理页面](https://appleid.apple.com)
2. 登录 → App-Specific Passwords → Generate
3. 记录生成的密码 (格式: xxxx-xxxx-xxxx-xxxx)

### 获取 Team ID

```bash
# 方法1: 查看证书
security find-identity -v -p codesigning

# 方法2: 登录 Apple Developer Portal
# Account → Membership → Team ID
```

## Windows 代码签名

### 证书获取

#### 选项 1: 购买 EV 代码签名证书 (推荐用于发布)

提供商:
- DigiCert (~$400/年)
- Sectigo (~$200/年)
- Certum (较便宜选项)

EV 证书优势:
- 立即获得 SmartScreen 信誉
- 支持硬件密钥存储 (更安全)
- 显示发布者名称

#### 选项 2: 使用自签名证书 (仅用于开发测试)

```powershell
# 以管理员身份运行 PowerShell
# 创建自签名证书
$cert = New-SelfSignedCertificate `
  -Type CodeSigningCert `
  -Subject "CN=Riptide" `
  -KeyUsage DigitalSignature `
  -FriendlyName "Riptide Test Certificate" `
  -CertStoreLocation Cert:\CurrentUser\My

# 导出为 PFX
$password = ConvertTo-SecureString -String "your-password" -Force -AsPlainText
Export-PfxCertificate `
  -Cert $cert `
  -FilePath riptide-test.pfx `
  -Password $password

# 信任证书 (测试用)
Export-Certificate -Cert $cert -FilePath riptide-test.cer
Import-Certificate -FilePath riptide-test.cer -CertStoreLocation Cert:\LocalMachine\Root
```

### GitHub Secrets 配置

| Secret Name | Description |
|-------------|-------------|
| `WINDOWS_CERTIFICATE` | Base64 编码的 pfx 证书 |
| `WINDOWS_CERTIFICATE_PWD` | pfx 证书密码 |

### 签名工具

Windows SDK 包含 `signtool.exe`，通常位于:
```
C:\Program Files (x86)\Windows Kits\10\bin\10.0.xxxxx\x64\signtool.exe
```

GitHub Actions 使用 `windows-latest` 运行器时，signtool 已预装。

## 本地签名测试

### macOS

```bash
# 签名应用
codesign --force --options runtime --sign "Developer ID Application: Your Name" Riptide.app

# 验证签名
codesign --verify --verbose Riptide.app

# 公证 (需要互联网连接)
xcrun notarytool submit Riptide.app \
  --apple-id "your-apple-id@example.com" \
  --password "app-specific-password" \
  --team-id "TEAMID1234" \
  --wait
```

### Windows

```powershell
# 签名可执行文件
signtool sign /f certificate.pfx /p password /fd sha256 /tr http://timestamp.digicert.com /td sha256 Riptide.exe

# 验证签名
signtool verify /pa Riptide.exe
```

## CI/CD 集成

项目已配置 `Scripts/setup-signing.sh` 脚本，用于在 GitHub Actions 中设置 macOS 签名环境。

### 工作流程概览

1. GitHub Actions 触发构建
2. 运行 `setup-signing.sh` 导入证书到临时钥匙串
3. 构建并签名应用
4. 公证 (macOS) / 时间戳 (Windows)
5. 上传到 Release

## 故障排除

### macOS 常见问题

```bash
# 证书未找到
security find-identity -v -p codesigning

# 钥匙串锁定
security unlock-keychain -p "$MACOS_KEYCHAIN_PWD" build.keychain

# 公证失败检查日志
xcrun notarytool log <submission-id> \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --team-id "$APPLE_TEAM_ID"
```

### Windows 常见问题

```powershell
# 证书导入失败检查编码
certutil -dump certificate.pfx

# 签名验证失败
certutil -verify Riptide.exe
```

## 安全注意事项

1. **永远不要提交真实证书到仓库**
   - 使用 GitHub Secrets 存储敏感信息
   - 证书文件添加到 .gitignore

2. **保护证书私钥**
   - 使用强密码保护 p12/pfx 文件
   - 限制证书访问权限
   - 定期轮换证书

3. **CI 环境安全**
   - 密钥串密码每次构建随机生成
   - 构建完成后清理证书
   - 使用 GitHub 环境保护规则限制发布流程

## 参考资源

- [Apple: Notarizing macOS Software](https://developer.apple.com/documentation/xcode/notarizing_macos_software_before_distribution)
- [Microsoft: Code Signing Best Practices](https://docs.microsoft.com/en-us/windows-hardware/drivers/dashboard/code-signing-certificates)
- [GitHub Docs: Encrypted Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
