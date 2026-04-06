#!/bin/bash
# Scripts/download-singbox.sh
# Download sing-box binary for macOS

set -e

VERSION="1.13.0"
ARCH=$(uname -m)

echo "Downloading sing-box v${VERSION} for ${ARCH}..."

# Create Binaries directory
mkdir -p "$(pwd)/Binaries"

case $ARCH in
    x86_64)
        SUFFIX="amd64"
        URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-darwin-${SUFFIX}.zip"
        echo "Downloading Intel binary..."
        curl -L -o /tmp/sing-box.zip "$URL"
        unzip -o /tmp/sing-box.zip -d /tmp/
        cp "/tmp/sing-box-${VERSION}-darwin-${SUFFIX}/sing-box" "$(pwd)/Binaries/sing-box"
        ;;
    arm64)
        SUFFIX="arm64"
        URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-darwin-${SUFFIX}.zip"
        echo "Downloading Apple Silicon binary..."
        curl -L -o /tmp/sing-box.zip "$URL"
        unzip -o /tmp/sing-box.zip -d /tmp/
        cp "/tmp/sing-box-${VERSION}-darwin-${SUFFIX}/sing-box" "$(pwd)/Binaries/sing-box"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        echo "Attempting to create universal binary..."
        
        # Download both architectures
        ARM_URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-darwin-arm64.zip"
        AMD_URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-darwin-amd64.zip"
        
        curl -L -o /tmp/sing-box-arm64.zip "$ARM_URL"
        curl -L -o /tmp/sing-box-amd64.zip "$AMD_URL"
        
        unzip -o /tmp/sing-box-arm64.zip -d /tmp/arm64/
        unzip -o /tmp/sing-box-amd64.zip -d /tmp/amd64/
        
        # Create universal binary
        lipo -create \
            "/tmp/arm64/sing-box-${VERSION}-darwin-arm64/sing-box" \
            "/tmp/amd64/sing-box-${VERSION}-darwin-amd64/sing-box" \
            -output "$(pwd)/Binaries/sing-box"
        ;;
esac

# Make executable
chmod +x "$(pwd)/Binaries/sing-box"

# Ad-hoc sign
codesign --sign - --force "$(pwd)/Binaries/sing-box" 2>/dev/null || true

echo "sing-box binary installed to $(pwd)/Binaries/sing-box"
"$(pwd)/Binaries/sing-box" version
