#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT_DIR/Vendor/LibreDWG/SOURCE_MANIFEST.md"
OUTPUT_DIR="${1:-"$ROOT_DIR/build/release"}"
WORK_DIR="$ROOT_DIR/build/corresponding-source/work"

if [[ ! -f "$MANIFEST" ]]; then
  echo "[corresponding-source] missing $MANIFEST" >&2
  exit 1
fi

if ! rg -q '^Source status: READY$' "$MANIFEST"; then
  echo "[corresponding-source] LibreDWG source manifest is not READY. Rebuild LibreDWG first." >&2
  exit 1
fi

LIBREDWG_COMMIT="$(awk -F': ' '/^Upstream commit: / {print $2; exit}' "$MANIFEST")"
if [[ ! "$LIBREDWG_COMMIT" =~ ^[0-9a-f]{7,40}$ ]]; then
  echo "[corresponding-source] SOURCE_MANIFEST.md does not contain an exact upstream commit." >&2
  exit 1
fi

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" && "${ALLOW_DIRTY_SOURCE_PACKAGE:-0}" != "1" ]]; then
  echo "[corresponding-source] working tree is dirty; commit release sources first." >&2
  exit 1
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Widget/Info.plist" 2>/dev/null || echo dev)"
APP_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
PACKAGE_BASENAME="sitekeeper-corresponding-source-${APP_VERSION}-${APP_COMMIT}"
PACKAGE_ROOT="$WORK_DIR/$PACKAGE_BASENAME"
LIBREDWG_SOURCE="$PACKAGE_ROOT/third_party/libredwg"

rm -rf "$WORK_DIR"
mkdir -p "$PACKAGE_ROOT/app" "$PACKAGE_ROOT/third_party" "$OUTPUT_DIR"

echo "[corresponding-source] exporting app source"
git -C "$ROOT_DIR" archive --format=tar HEAD | tar -x -C "$PACKAGE_ROOT/app"

echo "[corresponding-source] cloning LibreDWG $LIBREDWG_COMMIT"
git clone https://git.savannah.gnu.org/git/libredwg.git "$LIBREDWG_SOURCE" >/dev/null
git -C "$LIBREDWG_SOURCE" checkout "$LIBREDWG_COMMIT" >/dev/null

cat > "$PACKAGE_ROOT/README.md" <<EOF
# Sitekeeper Corresponding Source

Package: $PACKAGE_BASENAME
App commit: $APP_COMMIT
LibreDWG commit: $LIBREDWG_COMMIT

Contents:

- app/: Sitekeeper source at the release commit.
- third_party/libredwg/: LibreDWG source at the recorded upstream commit.

The LibreDWG iOS artifact can be rebuilt from app/ with:

\`\`\`sh
scripts/cad/build_libredwg_ios_xcframework.sh third_party/libredwg Vendor/LibreDWG/CLibreDWG.xcframework
\`\`\`
EOF

tarball="$OUTPUT_DIR/$PACKAGE_BASENAME.tar.gz"
echo "[corresponding-source] writing $tarball"
tar -C "$WORK_DIR" -czf "$tarball" "$PACKAGE_BASENAME"

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$tarball" > "$tarball.sha256"
  echo "[corresponding-source] wrote $tarball.sha256"
fi

echo "[corresponding-source] done: $tarball"

