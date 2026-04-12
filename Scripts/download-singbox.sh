#!/bin/bash
# Scripts/download-singbox.sh
# Download sing-box binary for macOS

set -euo pipefail

VERSION="1.13.0"
ARCH=$(uname -m)
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
BIN_DIR="$REPO_ROOT/Binaries"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/singbox-download.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT

mkdir -p "$BIN_DIR"

echo "Downloading sing-box v${VERSION} for ${ARCH}..."

case $ARCH in
    x86_64)
        SUFFIX="amd64"
        URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-darwin-${SUFFIX}.zip"
        echo "Downloading Intel binary..."
        curl -L --fail -o "$TEMP_DIR/sing-box.zip" "$URL"
        unzip -o "$TEMP_DIR/sing-box.zip" -d "$TEMP_DIR"
        cp "$TEMP_DIR/sing-box-${VERSION}-darwin-${SUFFIX}/sing-box" "$BIN_DIR/sing-box"
        ;;
    arm64)
        SUFFIX="arm64"
        URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-darwin-${SUFFIX}.zip"
        echo "Downloading Apple Silicon binary..."
        curl -L --fail -o "$TEMP_DIR/sing-box.zip" "$URL"
        unzip -o "$TEMP_DIR/sing-box.zip" -d "$TEMP_DIR"
        cp "$TEMP_DIR/sing-box-${VERSION}-darwin-${SUFFIX}/sing-box" "$BIN_DIR/sing-box"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        echo "Attempting to create universal binary..."

        ARM_URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-darwin-arm64.zip"
        AMD_URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-darwin-amd64.zip"

        curl -L --fail -o "$TEMP_DIR/sing-box-arm64.zip" "$ARM_URL"
        curl -L --fail -o "$TEMP_DIR/sing-box-amd64.zip" "$AMD_URL"

        unzip -o "$TEMP_DIR/sing-box-arm64.zip" -d "$TEMP_DIR/arm64"
        unzip -o "$TEMP_DIR/sing-box-amd64.zip" -d "$TEMP_DIR/amd64"

        lipo -create \
            "$TEMP_DIR/arm64/sing-box-${VERSION}-darwin-arm64/sing-box" \
            "$TEMP_DIR/amd64/sing-box-${VERSION}-darwin-amd64/sing-box" \
            -output "$BIN_DIR/sing-box"
        ;;
esac

chmod +x "$BIN_DIR/sing-box"

if ! codesign --sign - --force "$BIN_DIR/sing-box" 2>/dev/null; then
    echo "Warning: failed to ad-hoc sign $BIN_DIR/sing-box" >&2
    echo "The binary may fail to launch correctly on macOS." >&2
fi

echo "sing-box binary installed to $BIN_DIR/sing-box"
"$BIN_DIR/sing-box" version
