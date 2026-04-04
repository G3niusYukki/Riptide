#!/bin/bash
set -e

MIHOMO_VERSION="v1.18.5"
RESOURCES_DIR="Resources"

mkdir -p "$RESOURCES_DIR"

# Download URLs for both architectures
ARM64_URL="https://github.com/MetaCubeX/mihomo/releases/download/$MIHOMO_VERSION/mihomo-darwin-arm64-$MIHOMO_VERSION.gz"
AMD64_URL="https://github.com/MetaCubeX/mihomo/releases/download/$MIHOMO_VERSION/mihomo-darwin-amd64-$MIHOMO_VERSION.gz"

# Download arm64
curl -L "$ARM64_URL" -o "$RESOURCES_DIR/mihomo-arm64.gz"
gunzip "$RESOURCES_DIR/mihomo-arm64.gz"
mv "$RESOURCES_DIR/mihomo-darwin-arm64-$MIHOMO_VERSION" "$RESOURCES_DIR/mihomo-arm64"
chmod +x "$RESOURCES_DIR/mihomo-arm64"

# Download amd64
curl -L "$AMD64_URL" -o "$RESOURCES_DIR/mihomo-amd64.gz"
gunzip "$RESOURCES_DIR/mihomo-amd64.gz"
mv "$RESOURCES_DIR/mihomo-darwin-amd64-$MIHOMO_VERSION" "$RESOURCES_DIR/mihomo-amd64"
chmod +x "$RESOURCES_DIR/mihomo-amd64"

# Create universal binary
lipo -create "$RESOURCES_DIR/mihomo-arm64" "$RESOURCES_DIR/mihomo-amd64" -output "$RESOURCES_DIR/mihomo"

# Sign
codesign --sign - --force "$RESOURCES_DIR/mihomo"

# Cleanup
rm -f "$RESOURCES_DIR/mihomo-arm64" "$RESOURCES_DIR/mihomo-amd64"

echo "mihomo binary ready at $RESOURCES_DIR/mihomo"
