#!/bin/bash
set -e

# Riptide Release Build Script
# Builds an arm64 DMG for macOS distribution

APP_NAME="RiptideApp"
BUILD_DIR=".build/arm64-apple-macosx/release"
OUTPUT_DIR=".build/release-dmg"
DMG_NAME="Riptide.dmg"
VOLUME_NAME="Riptide"
VERSION=$(cat .version 2>/dev/null || echo "1.0.0")

echo "Building Riptide v${VERSION} for arm64..."

# Clean previous builds
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Build with release configuration (arm64)
swift build --product "$APP_NAME" -c release --arch arm64

echo "Build complete"

# Check binary
if [ ! -f "$BUILD_DIR/$APP_NAME" ]; then
    echo "Binary not found at $BUILD_DIR/$APP_NAME"
    exit 1
fi
file "$BUILD_DIR/$APP_NAME"

# Create .app bundle
echo "Creating app bundle..."
APP_DIR="$OUTPUT_DIR/${APP_NAME}.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/"

# Compile asset catalog if actool is available
ASSET_CATALOG="Sources/RiptideApp/Assets.xcassets"
if [ -d "$ASSET_CATALOG" ] && command -v actool &>/dev/null; then
    echo "Compiling asset catalog..."
    actool --compile "$APP_DIR/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon AppIcon \
        --output-partial-info-plist /dev/null \
        "$ASSET_CATALOG"
elif [ -f "$ASSET_CATALOG/AppIcon.appiconset/icon_512.png" ]; then
    cp "$ASSET_CATALOG/AppIcon.appiconset/icon_512.png" "$APP_DIR/Contents/Resources/AppIcon.png"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>RiptideApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.riptide.app</string>
    <key>CFBundleName</key>
    <string>Riptide</string>
    <key>CFBundleDisplayName</key>
    <string>Riptide</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

# Ad-hoc sign
echo "Ad-hoc signing..."
codesign --sign - --deep --force "$APP_DIR"

# Create DMG
echo "Creating DMG..."
DMG_CONTENT="$OUTPUT_DIR/dmg-content"
mkdir -p "$DMG_CONTENT"
cp -R "$APP_DIR" "$DMG_CONTENT/"
ln -s /Applications "$DMG_CONTENT/Applications"

hdiutil create -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_CONTENT" \
  -ov -format UDZO \
  "$OUTPUT_DIR/${DMG_NAME}"

DMG_SIZE=$(du -h "$OUTPUT_DIR/${DMG_NAME}" | cut -f1)
rm -rf "$DMG_CONTENT"

echo ""
echo "Release build complete!"
echo "DMG: $OUTPUT_DIR/${DMG_NAME} (${DMG_SIZE})"
echo "App: $APP_DIR"
