#!/bin/bash

# setup-signing.sh
# macOS 代码签名环境设置脚本
# 用于 GitHub Actions CI 环境

set -e

echo "=========================================="
echo "Setting up macOS code signing environment"
echo "=========================================="

# 检查必需的环境变量
if [ -z "$MACOS_CERTIFICATE" ]; then
    echo "Error: MACOS_CERTIFICATE environment variable not set"
    exit 1
fi

if [ -z "$MACOS_CERTIFICATE_PWD" ]; then
    echo "Error: MACOS_CERTIFICATE_PWD environment variable not set"
    exit 1
fi

if [ -z "$MACOS_KEYCHAIN_PWD" ]; then
    echo "Error: MACOS_KEYCHAIN_PWD environment variable not set"
    exit 1
fi

KEYCHAIN_NAME="build.keychain"
KEYCHAIN_PATH="$HOME/Library/Keychains/$KEYCHAIN_NAME-db"

echo "Step 1: Creating temporary keychain..."
# 删除可能存在的旧钥匙串
if [ -f "$KEYCHAIN_PATH" ]; then
    security delete-keychain "$KEYCHAIN_NAME" 2>/dev/null || true
fi

# 创建新钥匙串
security create-keychain -p "$MACOS_KEYCHAIN_PWD" "$KEYCHAIN_NAME"
echo "✓ Keychain created"

echo "Step 2: Configuring keychain..."
# 设置默认钥匙串
security default-keychain -s "$KEYCHAIN_NAME"

# 解锁钥匙串
security unlock-keychain -p "$MACOS_KEYCHAIN_PWD" "$KEYCHAIN_NAME"

# 禁用钥匙串锁定超时
security set-keychain-settings "$KEYCHAIN_NAME"
echo "✓ Keychain configured"

echo "Step 3: Importing certificate..."
# 解码 Base64 证书并导入
echo "$MACOS_CERTIFICATE" | base64 -d > /tmp/certificate.p12

security import /tmp/certificate.p12 \
    -k "$KEYCHAIN_NAME" \
    -P "$MACOS_CERTIFICATE_PWD" \
    -T /usr/bin/codesign \
    -T /usr/bin/productbuild \
    -T /usr/bin/pkgutil \
    2>&1 | grep -v "SecKeychainItemImport: User interaction is not allowed" || true

echo "✓ Certificate imported"

echo "Step 4: Allowing keychain access..."
# 允许 codesign 访问钥匙串
security set-key-partition-list \
    -S apple-tool:,apple:,codesign:,productbuild: \
    -s \
    -k "$MACOS_KEYCHAIN_PWD" \
    "$KEYCHAIN_NAME" \
    2>&1 | grep -v "security: SecItemCopyMatching: The specified item could not be found in the keychain" || true

echo "✓ Keychain access granted"

echo "Step 5: Verifying signing identity..."
# 验证证书已正确安装
IDENTITIES=$(security find-identity -v -p codesigning "$KEYCHAIN_NAME" 2>/dev/null | grep "valid identities found" | awk '{print $1}')
if [ "$IDENTITIES" -gt 0 ]; then
    echo "✓ Found $IDENTITIES valid signing identity(s):"
    security find-identity -v -p codesigning "$KEYCHAIN_NAME" | grep "Developer ID Application" || true
else
    echo "⚠ Warning: No valid signing identities found"
fi

echo ""
echo "=========================================="
echo "macOS signing environment configured successfully!"
echo "=========================================="

# 清理临时文件
rm -f /tmp/certificate.p12

echo ""
echo "Available environment for signing:"
echo "  KEYCHAIN: $KEYCHAIN_NAME"
echo "  CODESIGN_IDENTITY: Use 'security find-identity -v -p codesigning' to list"
