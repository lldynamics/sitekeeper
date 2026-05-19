#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIBREDWG_SOURCE_DIR="${1:-"$ROOT_DIR/build/libredwg-ios/source"}"
OUTPUT_XCFRAMEWORK="${2:-"$ROOT_DIR/Vendor/LibreDWG/CLibreDWG.xcframework"}"
BUILD_ROOT="$ROOT_DIR/build/libredwg-ios"
WORK_ROOT="$BUILD_ROOT/work"
HEADERS_DIR="$BUILD_ROOT/headers"
COMPAT_HEADER="$BUILD_ROOT/libredwg_ios_compat.h"

usage() {
  cat <<'USAGE'
Usage:
  scripts/cad/build_libredwg_ios_xcframework.sh [libredwg-source-dir] [output-xcframework]

Builds LibreDWG as a static iOS XCFramework for the in-app Native CAD renderer.
The default output is Vendor/LibreDWG/CLibreDWG.xcframework.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[libredwg-ios] missing required tool: $1" >&2
    exit 1
  fi
}

require_tool git
require_tool make
require_tool xcrun
require_tool xcodebuild
require_tool gperf

mkdir -p "$BUILD_ROOT"

if [[ ! -d "$LIBREDWG_SOURCE_DIR/.git" && ! -f "$LIBREDWG_SOURCE_DIR/configure.ac" ]]; then
  echo "[libredwg-ios] cloning LibreDWG source into $LIBREDWG_SOURCE_DIR"
  rm -rf "$LIBREDWG_SOURCE_DIR"
  git clone --depth 1 https://git.savannah.gnu.org/git/libredwg.git "$LIBREDWG_SOURCE_DIR"
fi

if [[ ! -x "$LIBREDWG_SOURCE_DIR/configure" ]]; then
  require_tool autoconf
  require_tool automake
  echo "[libredwg-ios] generating configure script"
  (cd "$LIBREDWG_SOURCE_DIR" && ./autogen.sh)
fi

cat > "$COMPAT_HEADER" <<'EOF'
#ifndef SITEKEEPER_LIBREDWG_IOS_COMPAT_H
#define SITEKEEPER_LIBREDWG_IOS_COMPAT_H
#if defined(__APPLE__)
#include <libkern/OSByteOrder.h>
#ifndef le16toh
#define le16toh OSSwapLittleToHostInt16
#endif
#ifndef le32toh
#define le32toh OSSwapLittleToHostInt32
#endif
#ifndef le64toh
#define le64toh OSSwapLittleToHostInt64
#endif
#ifndef htole32
#define htole32 OSSwapHostToLittleInt32
#endif
#ifndef htole64
#define htole64 OSSwapHostToLittleInt64
#endif
#ifndef htobe16
#define htobe16 OSSwapHostToBigInt16
#endif
#ifndef htobe32
#define htobe32 OSSwapHostToBigInt32
#endif
#ifndef htobe64
#define htobe64 OSSwapHostToBigInt64
#endif
#ifndef be64toh
#define be64toh OSSwapBigToHostInt64
#endif
#endif
#endif
EOF

build_platform() {
  local name="$1"
  local sdk="$2"
  local target="$3"
  local host="$4"
  local build_dir="$WORK_ROOT/$name"
  local install_dir="$BUILD_ROOT/install/$name"
  local sdkroot clang ar ranlib

  sdkroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  clang="$(xcrun --sdk "$sdk" --find clang)"
  ar="$(xcrun --sdk "$sdk" --find ar)"
  ranlib="$(xcrun --sdk "$sdk" --find ranlib)"

  rm -rf "$build_dir" "$install_dir"
  mkdir -p "$build_dir"

  echo "[libredwg-ios] configuring $name"
  (
    cd "$build_dir"
    CC="$clang -target $target -isysroot $sdkroot" \
      AR="$ar" \
      RANLIB="$ranlib" \
      CPPFLAGS="-include $COMPAT_HEADER" \
      CFLAGS="-O2 -fvisibility=hidden" \
      LDFLAGS="-isysroot $sdkroot" \
      PKG_CONFIG=/usr/bin/false \
      "$LIBREDWG_SOURCE_DIR/configure" \
        --host="$host" \
        --disable-shared \
        --enable-static \
        --disable-bindings \
        --disable-docs \
        --disable-write \
        --disable-werror \
        --prefix="$install_dir" \
      > "$BUILD_ROOT/configure-$name.log" 2>&1
  )

  echo "[libredwg-ios] building $name libredwg.a"
  make -C "$build_dir/src" -j"$(sysctl -n hw.ncpu)" libredwg.la \
    > "$BUILD_ROOT/build-$name.log" 2>&1

  local library="$build_dir/src/.libs/libredwg.a"
  if [[ ! -f "$library" ]]; then
    echo "[libredwg-ios] expected library not found: $library" >&2
    exit 1
  fi
}

build_platform "ios-arm64" "iphoneos" "arm64-apple-ios17.0" "arm-apple-darwin"
build_platform "ios-arm64-simulator" "iphonesimulator" "arm64-apple-ios17.0-simulator" "arm-apple-darwin"
build_platform "ios-x86_64-simulator" "iphonesimulator" "x86_64-apple-ios17.0-simulator" "x86_64-apple-darwin"

SIMULATOR_UNIVERSAL_DIR="$WORK_ROOT/ios-simulator-universal"
rm -rf "$SIMULATOR_UNIVERSAL_DIR"
mkdir -p "$SIMULATOR_UNIVERSAL_DIR"
xcrun lipo -create \
  "$WORK_ROOT/ios-arm64-simulator/src/.libs/libredwg.a" \
  "$WORK_ROOT/ios-x86_64-simulator/src/.libs/libredwg.a" \
  -output "$SIMULATOR_UNIVERSAL_DIR/libredwg.a"

rm -rf "$HEADERS_DIR"
mkdir -p "$HEADERS_DIR"
cp "$LIBREDWG_SOURCE_DIR/include/dwg.h" "$HEADERS_DIR/"
cp "$LIBREDWG_SOURCE_DIR/include/dwg_api.h" "$HEADERS_DIR/"
cat > "$HEADERS_DIR/module.modulemap" <<'EOF'
module CLibreDWG [system] {
  header "dwg_api.h"
  export *
}
EOF

rm -rf "$OUTPUT_XCFRAMEWORK"
mkdir -p "$(dirname "$OUTPUT_XCFRAMEWORK")"
xcodebuild -create-xcframework \
  -library "$WORK_ROOT/ios-arm64/src/.libs/libredwg.a" -headers "$HEADERS_DIR" \
  -library "$SIMULATOR_UNIVERSAL_DIR/libredwg.a" -headers "$HEADERS_DIR" \
  -output "$OUTPUT_XCFRAMEWORK" \
  > "$BUILD_ROOT/create-xcframework.log" 2>&1

MANIFEST_PATH="$ROOT_DIR/Vendor/LibreDWG/SOURCE_MANIFEST.md"
SOURCE_REMOTE="$(git -C "$LIBREDWG_SOURCE_DIR" config --get remote.origin.url 2>/dev/null || true)"
SOURCE_COMMIT="$(git -C "$LIBREDWG_SOURCE_DIR" rev-parse HEAD 2>/dev/null || true)"
SOURCE_DESCRIBE="$(git -C "$LIBREDWG_SOURCE_DIR" describe --tags --always --dirty 2>/dev/null || true)"
BUILD_RECORDED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$(dirname "$MANIFEST_PATH")"
if [[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{7,40}$ ]]; then
  cat > "$MANIFEST_PATH" <<EOF
# LibreDWG Source Manifest

Source status: READY
Recorded at: $BUILD_RECORDED_AT
Upstream repository: ${SOURCE_REMOTE:-unknown}
Upstream commit: $SOURCE_COMMIT
Upstream describe: ${SOURCE_DESCRIBE:-unknown}
Build script: scripts/cad/build_libredwg_ios_xcframework.sh
Build command: scripts/cad/build_libredwg_ios_xcframework.sh "$LIBREDWG_SOURCE_DIR" "$OUTPUT_XCFRAMEWORK"
Local patches: none recorded
Generated compatibility header: build/libredwg-ios/libredwg_ios_compat.h
Generated artifact: ${OUTPUT_XCFRAMEWORK#$ROOT_DIR/}

The corresponding source package for an app release is generated by:

\`\`\`sh
scripts/release/package_corresponding_source.sh
\`\`\`
EOF
else
  cat > "$MANIFEST_PATH" <<EOF
# LibreDWG Source Manifest

Source status: NOT_READY
Recorded at: $BUILD_RECORDED_AT

The LibreDWG source directory used for this build was not a git checkout with an exact commit.
Rebuild from a pinned upstream checkout before release.
EOF
fi

echo "[libredwg-ios] wrote $OUTPUT_XCFRAMEWORK"
echo "[libredwg-ios] wrote $MANIFEST_PATH"
echo "[libredwg-ios] logs are in $BUILD_ROOT"
