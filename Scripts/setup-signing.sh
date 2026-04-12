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

# 应用钥匙串设置
security set-keychain-settings "$KEYCHAIN_NAME"
echo "✓ Keychain configured"

echo "Step 3: Importing certificate..."
# 解码 Base64 证书并导入
set +e
IMPORT_OUTPUT=$(echo "$MACOS_CERTIFICATE" | base64 -d > /tmp/certificate.p12 2>&1)
IMPORT_DECODE_STATUS=$?
set -e

if [ $IMPORT_DECODE_STATUS -ne 0 ]; then
    echo "Error: Failed to decode certificate"
    echo "$IMPORT_OUTPUT"
    exit 1
fi

set +e
IMPORT_OUTPUT=$(security import /tmp/certificate.p12 \
    -k "$KEYCHAIN_NAME" \
    -P "$MACOS_CERTIFICATE_PWD" \
    -T /usr/bin/codesign \
    -T /usr/bin/productbuild \
    -T /usr/bin/pkgutil \
    2>&1)
IMPORT_STATUS=$?
set -e

# Filter known benign warning but preserve errors
if [ $IMPORT_STATUS -ne 0 ]; then
    echo "Error: Failed to import certificate"
    printf '%s\n' "$IMPORT_OUTPUT"
    exit $IMPORT_STATUS
fi

# Only filter benign message for successful imports
printf '%s\n' "$IMPORT_OUTPUT" | grep -v "SecKeychainItemImport: User interaction is not allowed" || true

echo "✓ Certificate imported"

echo "Step 4: Allowing keychain access..."
# 允许 codesign 访问钥匙串
set +e
PARTITION_OUTPUT=$(security set-key-partition-list \
    -S apple-tool:,apple:,codesign:,productbuild: \
    -s \
    -k "$MACOS_KEYCHAIN_PWD" \
    "$KEYCHAIN_NAME" \
    2>&1)
PARTITION_STATUS=$?
set -e

if [ $PARTITION_STATUS -ne 0 ]; then
    # Check if it's just the benign "item not found" warning
    if printf '%s\n' "$PARTITION_OUTPUT" | grep -q "SecItemCopyMatching: The specified item could not be found"; then
        printf '%s\n' "$PARTITION_OUTPUT" | grep -v "SecItemCopyMatching: The specified item could not be found" || true
    else
        echo "Error: Failed to grant keychain access"
        printf '%s\n' "$PARTITION_OUTPUT"
        exit $PARTITION_STATUS
    fi
else
    printf '%s\n' "$PARTITION_OUTPUT" | grep -v "SecItemCopyMatching: The specified item could not be found" || true
fi

echo "✓ Keychain access granted"

echo "Step 5: Verifying signing identity..."
# 验证证书已正确安装 - 使用更健壮的方法
IDENTITY_OUTPUT=$(security find-identity -v -p codesigning "$KEYCHAIN_NAME" 2>/dev/null || true)

# 检查是否有 Developer ID Application 证书
if printf '%s\n' "$IDENTITY_OUTPUT" | grep -q "Developer ID Application"; then
    echo "✓ Valid signing identity found:"
    printf '%s\n' "$IDENTITY_OUTPUT" | grep "Developer ID Application" | head -5
else
    echo "⚠ Warning: No valid signing identities found"
    echo "Output was:"
    printf '%s\n' "$IDENTITY_OUTPUT"
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
