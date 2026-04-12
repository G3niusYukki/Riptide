#!/bin/bash
# Scripts/bump-version.sh
# Version bumping script for Riptide

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.2.3"
    exit 1
fi

NEW_VERSION=$1
CURRENT_VERSION=$(cat .version 2>/dev/null || echo "0.1.0")

echo "=========================================="
echo "Bumping version: $CURRENT_VERSION -> $NEW_VERSION"
echo "=========================================="

# Validate version format
if ! [[ $NEW_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "Error: Invalid version format. Expected: X.Y.Z or X.Y.Z-prerelease"
    exit 1
fi

# Update version file
echo "$NEW_VERSION" > .version
echo "✓ Updated .version file"

# Update version in files if they contain the current version
if [ -f "README.md" ] && grep -q "$CURRENT_VERSION" README.md 2>/dev/null; then
    sed -i.bak "s/$CURRENT_VERSION/$NEW_VERSION/g" README.md && rm -f README.md.bak
    echo "✓ Updated README.md"
fi

if [ -f "Package.swift" ] && grep -q "$CURRENT_VERSION" Package.swift 2>/dev/null; then
    sed -i.bak "s/$CURRENT_VERSION/$NEW_VERSION/g" Package.swift && rm -f Package.swift.bak
    echo "✓ Updated Package.swift"
fi

if [ -f "riptide-windows/package.json" ]; then
    sed -i.bak "s/\"version\": \"$CURRENT_VERSION\"/\"version\": \"$NEW_VERSION\"/g" riptide-windows/package.json && rm -f riptide-windows/package.json.bak
    echo "✓ Updated riptide-windows/package.json"
fi

# Update version in Cargo.toml for Windows
if [ -f "riptide-windows/src-tauri/Cargo.toml" ]; then
    sed -i.bak "s/^version = \"$CURRENT_VERSION\"/version = \"$NEW_VERSION\"/" riptide-windows/src-tauri/Cargo.toml && rm -f riptide-windows/src-tauri/Cargo.toml.bak
    echo "✓ Updated riptide-windows/src-tauri/Cargo.toml"
fi

# Update tauri.conf.json
if [ -f "riptide-windows/src-tauri/tauri.conf.json" ]; then
    sed -i.bak "s/\"version\": \"$CURRENT_VERSION\"/\"version\": \"$NEW_VERSION\"/" riptide-windows/src-tauri/tauri.conf.json && rm -f riptide-windows/src-tauri/tauri.conf.json.bak
    echo "✓ Updated riptide-windows/src-tauri/tauri.conf.json"
fi

# Update build-release.sh version in Info.plist template
if [ -f "Scripts/build-release.sh" ] && grep -q "$CURRENT_VERSION" Scripts/build-release.sh 2>/dev/null; then
    sed -i.bak "s/$CURRENT_VERSION/$NEW_VERSION/g" Scripts/build-release.sh && rm -f Scripts/build-release.sh.bak
    echo "✓ Updated Scripts/build-release.sh"
fi

echo ""
echo "=========================================="
echo "Version bumped to $NEW_VERSION"
echo "=========================================="
echo ""
echo "Review changes and commit:"
echo "  git add -A"
echo "  git commit -m 'chore: bump version to $NEW_VERSION'"
echo "  git tag v$NEW_VERSION"
echo "  git push origin main --tags"
echo ""
