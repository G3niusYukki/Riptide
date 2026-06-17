#!/usr/bin/env bash
#
# Builds Binaries/riptide-singbox — a standalone, universal (arm64 + x86_64)
# sing-box runner used for macOS TUN mode (which must run as root). It is built
# from gocore/cmd/riptide-singbox against the SAME sing-box v1.9.0 (+with_utls)
# module that produces the in-process libgocore.a, so the elevated TUN core and
# the in-process system-proxy core accept identical configs.
#
# This intentionally does NOT use Scripts/download-singbox.sh (which fetches an
# upstream v1.13.0 binary): SingBoxConfigGenerator targets the v1.9.0 schema, and
# a newer core would drift (e.g. the tun inbound's inet4_address was replaced by
# `address` after v1.10).
#
# Requires: Go (1.26.x), Xcode command-line tools (clang) able to target both
# arm64 and x86_64.
#
# Usage: ./Scripts/build-singbox-bin.sh
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="gocore"
OUT_DIR="Binaries"
PKG="./cmd/riptide-singbox"
TAGS="with_gvisor,with_wireguard,with_quic,with_utls"
# -checklinkname=0: sing v1.9 reaches internal stdlib symbols via //go:linkname,
# which Go 1.23+ rejects by default. -s -w strip debug info.
LDFLAGS="-s -w -checklinkname=0"

export GOTOOLCHAIN=local CGO_ENABLED=1
mkdir -p "$OUT_DIR"

pushd "$SRC" >/dev/null

echo "==> building arm64 slice"
GOARCH=arm64 CC="clang -arch arm64" \
  go build -tags "$TAGS" -ldflags="$LDFLAGS" -o riptide-singbox-arm64 "$PKG"

echo "==> building x86_64 slice"
GOARCH=amd64 CC="clang -arch x86_64" \
  go build -tags "$TAGS" -ldflags="$LDFLAGS" -o riptide-singbox-amd64 "$PKG"

echo "==> lipo -> universal"
lipo -create riptide-singbox-arm64 riptide-singbox-amd64 -output "../$OUT_DIR/riptide-singbox"
rm -f riptide-singbox-arm64 riptide-singbox-amd64

popd >/dev/null

chmod +x "$OUT_DIR/riptide-singbox"
# Ad-hoc sign so macOS will execute it (the .app's --deep sign also covers it
# once bundled, but signing here keeps the dev/Binaries copy runnable).
if ! codesign --sign - --force "$OUT_DIR/riptide-singbox" 2>/dev/null; then
  echo "Warning: failed to ad-hoc sign $OUT_DIR/riptide-singbox" >&2
fi

echo "==> done:"
lipo -info "$OUT_DIR/riptide-singbox"
"$OUT_DIR/riptide-singbox" -version
