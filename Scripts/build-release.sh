#!/bin/bash
set -e

# Riptide Release Build Script
# Builds an arm64 DMG for macOS distribution

APP_NAME="RiptideApp"
# SwiftPM 6.2 writes to .build/out/Products; older toolchains use the triple path.
BUILD_DIR=".build/out/Products/Release"
if [ ! -d "$BUILD_DIR" ] && [ -d ".build/arm64-apple-macosx/release" ]; then
    BUILD_DIR=".build/arm64-apple-macosx/release"
fi
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

if [ ! -f "$BUILD_DIR/$APP_NAME" ] && [ -f ".build/arm64-apple-macosx/release/$APP_NAME" ]; then
    BUILD_DIR=".build/arm64-apple-macosx/release"
fi

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

# sing-box is no longer on the TUN path (mihomo service mode owns TUN).
# Copy the binary only when it is already present; do not build it here.
if [ -f "Binaries/riptide-singbox" ]; then
    cp "Binaries/riptide-singbox" "$APP_DIR/Contents/Resources/riptide-singbox"
    chmod +x "$APP_DIR/Contents/Resources/riptide-singbox"
else
    echo "riptide-singbox not bundled (experimental; TUN uses riptide-mihomo-service)."
fi

# Bundle the mihomo service-mode daemon (v2.9.0). The GUI installs it as a
# root launchd daemon via MihomoServiceInstaller; MihomoServiceBinaryLocator
# resolves it from Bundle.main Resources first.
swift build --product RiptideMihomoService -c release --arch arm64
cp "$BUILD_DIR/RiptideMihomoService" "$APP_DIR/Contents/Resources/riptide-mihomo-service"
chmod +x "$APP_DIR/Contents/Resources/riptide-mihomo-service"

# Bundle Sparkle.framework. The app links Sparkle dynamically (@rpath), but
# SwiftPM only drops it under .build/, so without this the bundle dies at launch
# with "Library not loaded: @rpath/Sparkle.framework". Copy it into Frameworks/
# and add the matching rpath (the binary ships with @loader_path only).
SPARKLE_SRC="$BUILD_DIR/Sparkle.framework"
if [ ! -d "$SPARKLE_SRC" ] && [ -d ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" ]; then
    SPARKLE_SRC=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi
if [ -d "$SPARKLE_SRC" ]; then
    mkdir -p "$APP_DIR/Contents/Frameworks"
    cp -R "$SPARKLE_SRC" "$APP_DIR/Contents/Frameworks/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
        "$APP_DIR/Contents/MacOS/$APP_NAME" 2>/dev/null || true
else
    echo "WARNING: Sparkle.framework not found at $SPARKLE_SRC — bundle will crash at launch" >&2
fi

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
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.riptide.app.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>riptide</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Sign with a local identity when one is installed.
# Preference: $SIGN_IDENTITY, then Developer ID Application, then any
# codesigning identity whose TeamIdentifier is the public project team
# 39Q4M52XNQ. The certificate CN is never written into the repo.
# Falls back to ad-hoc. This does not notarize; Developer ID + notarytool
# secrets are still required for public distribution.
sign_app() {
    local app="$1"
    local identity=""
    local candidate team tmp
    if [ -n "${SIGN_IDENTITY:-}" ]; then
        identity="$SIGN_IDENTITY"
    else
        identity=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)
        if [ -z "$identity" ]; then
            tmp=$(mktemp)
            printf 'probe' > "$tmp"
            while IFS= read -r candidate; do
                [ -z "$candidate" ] && continue
                if codesign --sign "$candidate" --force "$tmp" >/dev/null 2>&1; then
                    team=$(codesign -dvvv "$tmp" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}')
                    if [ "$team" = "39Q4M52XNQ" ]; then
                        identity="$candidate"
                        break
                    fi
                fi
            done < <(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)"/\1/p')
            rm -f "$tmp"
        fi
    fi
    if [ -n "$identity" ]; then
        echo "Signing with an installed project identity (Developer ID, or team 39Q4M52XNQ)."
        codesign --sign "$identity" --force --deep "$app"
    else
        echo "No project signing identity found; ad-hoc signing."
        codesign --sign - --deep --force "$app"
    fi
}
sign_app "$APP_DIR"

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
