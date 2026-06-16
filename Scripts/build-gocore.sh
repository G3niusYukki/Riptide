#!/usr/bin/env bash
#
# Rebuilds Frameworks/GoCore.xcframework/macos-arm64_x86_64/libgocore.a from
# gocore/main.go, statically linking sing-box v1.9.0 with REALITY/uTLS support.
#
# The key difference from the original build is `-tags with_utls`, which compiles
# in the uTLS-based REALITY client (without it sing-box rejects any config that
# uses REALITY). Produces a universal (arm64 + x86_64) archive.
#
# Requires: Go (1.26.x, matching the original toolchain), Xcode command-line
# tools (clang) able to target both arm64 and x86_64.
#
# Usage: ./Scripts/build-gocore.sh
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="gocore"
OUT="Frameworks/GoCore.xcframework/macos-arm64_x86_64"
TAGS="with_gvisor,with_wireguard,with_quic,with_utls"
# -checklinkname=0: sing v1.9 reaches internal stdlib symbols via //go:linkname,
# which Go 1.23+ rejects by default. -s -w strip debug info to match the original.
LDFLAGS="-s -w -checklinkname=0"

export GOTOOLCHAIN=local CGO_ENABLED=1

pushd "$SRC" >/dev/null

echo "==> building arm64 slice"
GOARCH=arm64 CC="clang -arch arm64" \
  go build -buildmode=c-archive -tags "$TAGS" -ldflags="$LDFLAGS" -o libgocore-arm64.a main.go

echo "==> building x86_64 slice"
GOARCH=amd64 CC="clang -arch x86_64" \
  go build -buildmode=c-archive -tags "$TAGS" -ldflags="$LDFLAGS" -o libgocore-amd64.a main.go

echo "==> lipo -> universal"
lipo -create libgocore-arm64.a libgocore-amd64.a -output libgocore.a

mkdir -p "../$OUT/Headers"
cp libgocore.a "../$OUT/libgocore.a"
# cgo names the header after the -o archive; both slices emit an identical header.
cp libgocore-arm64.h "../$OUT/Headers/libgocore.h"

rm -f libgocore-arm64.a libgocore-amd64.a libgocore.a libgocore-arm64.h libgocore-amd64.h

popd >/dev/null

echo "==> done:"
lipo -info "$OUT/libgocore.a"
