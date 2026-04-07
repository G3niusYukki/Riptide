#!/bin/bash
set -e

# Riptide Release Build Script
# Builds a universal binary DMG for macOS distribution

APP_NAME="RiptideApp"
BUILD_DIR=".build/apple/Products/Release"
OUTPUT_DIR=".build/release-dmg"
DMG_NAME="Riptide.dmg"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
VOLUME_NAME="Riptide"

echo "🔨 Building Riptide for release..."

# Clean previous builds
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Build with release configuration (universal binary)
swift build --product "$APP_NAME" -c release --arch arm64 --arch x86_64

echo "✅ Build complete"

# Check binary architecture
echo "📦 Checking binary architecture..."
if [ -f "$BUILD_DIR/$APP_NAME" ]; then
    lipo -info "$BUILD_DIR/$APP_NAME"
else
    echo "⚠️  Binary not found at expected location"
    exit 1
fi

# Create DMG
echo "💿 Creating DMG..."

# Create temporary directory for DMG contents
DMG_CONTENT="$OUTPUT_DIR/dmg-content"
mkdir -p "$DMG_CONTENT"

# Copy app bundle if it exists, otherwise copy binary
if [ -d "$APP_BUNDLE" ]; then
    echo "📱 Found .app bundle, copying..."
    cp -R "$APP_BUNDLE" "$DMG_CONTENT/"
else
    echo "⚠️  No .app bundle found, creating one..."
    # Create a simple app bundle structure
    mkdir -p "$DMG_CONTENT/$APP_NAME.app/Contents/MacOS"
    cp "$BUILD_DIR/$APP_NAME" "$DMG_CONTENT/$APP_NAME.app/Contents/MacOS/"
    
    # Create Info.plist
    cat > "$DMG_CONTENT/$APP_NAME.app/Contents/Info.plist" << 'PLIST'
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
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST
fi

# Create Applications symlink
ln -s /Applications "$DMG_CONTENT/Applications"

# Create DMG image
hdiutil create -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_CONTENT" \
  -ov -format UDZO \
  "$OUTPUT_DIR/$DMG_NAME"

echo "✅ DMG created at: $OUTPUT_DIR/$DMG_NAME"

# Show DMG size
DMG_SIZE=$(du -h "$OUTPUT_DIR/$DMG_NAME" | cut -f1)
echo "📊 DMG size: $DMG_SIZE"

# Cleanup
rm -rf "$DMG_CONTENT"

echo ""
echo "🎉 Release build complete!"
echo "📍 DMG location: $OUTPUT_DIR/$DMG_NAME"
echo ""
echo "To distribute:"
echo "  1. Code sign the app: codesign --sign \"Developer ID Application: Your Name\" --deep --force \"$BUILD_DIR/$APP_NAME.app\""
echo "  2. Notarize: xcrun notarytool submit \"$OUTPUT_DIR/$DMG_NAME\" --keychain-profile \"AC_PASSWORD\" --wait"
echo "  3. Staple: xcrun stapler staple \"$OUTPUT_DIR/$DMG_NAME\""
