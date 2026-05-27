#!/bin/bash
set -e

# Add homebrew bin to path in case it is not inherited
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Go to script directory
cd "$(dirname "$0")"

echo "Building GoCore static libraries..."
GO_TAGS="with_gvisor,with_wireguard,with_quic"
GO_LDFLAGS="-s -w"
echo "Using Go build tags: ${GO_TAGS}"
echo "Using Go linker flags: ${GO_LDFLAGS}"

# Initialize Go module if not exists
if [ ! -f go.mod ]; then
  go mod init riptidego
fi

# Clean previous build artifacts
rm -rf build
mkdir -p build/macos-arm64 build/macos-amd64

# 1. Compile macOS ARM64 static library
echo "Compiling macOS ARM64..."
CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 CGO_CFLAGS="-mmacosx-version-min=14.0" CGO_LDFLAGS="-mmacosx-version-min=14.0" go build -trimpath -tags "${GO_TAGS}" -ldflags "${GO_LDFLAGS}" -buildmode=c-archive -o build/macos-arm64/libgocore.a main.go

# 2. Compile macOS AMD64 (Intel) static library
echo "Compiling macOS AMD64..."
CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 CGO_CFLAGS="-mmacosx-version-min=14.0" CGO_LDFLAGS="-mmacosx-version-min=14.0" go build -trimpath -tags "${GO_TAGS}" -ldflags "${GO_LDFLAGS}" -buildmode=c-archive -o build/macos-amd64/libgocore.a main.go

# 3. Create Lip/Universal static library
echo "Creating universal binary..."
mkdir -p build/macos-universal
lipo -create \
  build/macos-arm64/libgocore.a \
  build/macos-amd64/libgocore.a \
  -output build/macos-universal/libgocore.a

# Create dedicated headers folder and generate module.modulemap
mkdir -p build/headers
cp build/macos-arm64/libgocore.h build/headers/

cat << 'EOF' > build/headers/module.modulemap
module GoCore {
    header "libgocore.h"
    export *
}
EOF

# 4. Package as XCFramework
echo "Creating XCFramework..."
rm -rf ../../Frameworks/GoCore.xcframework
mkdir -p ../../Frameworks

xcodebuild -create-xcframework \
  -library build/macos-universal/libgocore.a \
  -headers build/headers/ \
  -output ../../Frameworks/GoCore.xcframework

echo "GoCore.xcframework created successfully at Frameworks/GoCore.xcframework!"
