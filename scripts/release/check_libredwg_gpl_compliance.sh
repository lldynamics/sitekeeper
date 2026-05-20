#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/Vendor/LibreDWG/CLibreDWG.xcframework"
RELEASE_MODE="${REQUIRE_LIBREDWG_RELEASE_COMPLIANCE:-0}"

if [[ ! -d "$ARTIFACT_DIR" ]]; then
  echo "[libredwg-gpl] PASS: LibreDWG artifact is not bundled."
  exit 0
fi

required_files=(
  "$ROOT_DIR/GPL_COMPLIANCE.md"
  "$ROOT_DIR/THIRD_PARTY_NOTICES.md"
  "$ROOT_DIR/Vendor/LibreDWG/README.md"
  "$ROOT_DIR/Vendor/LibreDWG/COPYING.GPL-3.0.txt"
  "$ROOT_DIR/Vendor/LibreDWG/SOURCE_MANIFEST.md"
  "$ROOT_DIR/scripts/cad/build_libredwg_ios_xcframework.sh"
  "$ROOT_DIR/scripts/release/package_corresponding_source.sh"
  "$ROOT_DIR/Sources/Shared/CAD/Import/NativeLibreDWG/SiteKeeperLibreDWGShim.c"
  "$ROOT_DIR/Sources/Shared/CAD/Import/NativeLibreDWG/SiteKeeperLibreDWGShim.h"
)

missing=()
for file in "${required_files[@]}"; do
  if [[ ! -e "$file" ]]; then
    missing+=("${file#$ROOT_DIR/}")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "[libredwg-gpl] ERROR: missing required GPL compliance files:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

require_text() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if ! rg -q --fixed-strings "$pattern" "$file"; then
    echo "[libredwg-gpl] ERROR: $label missing '$pattern' in ${file#$ROOT_DIR/}" >&2
    exit 1
  fi
}

require_text "$ROOT_DIR/GPL_COMPLIANCE.md" "Corresponding Source" "GPL compliance plan"
require_text "$ROOT_DIR/GPL_COMPLIANCE.md" "App Store" "GPL compliance plan"
require_text "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "GNU General Public License version 3 or later" "third-party notices"
require_text "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "LibreDWG" "third-party notices"
require_text "$ROOT_DIR/Vendor/LibreDWG/SOURCE_MANIFEST.md" "Source status:" "source manifest"

if ! rg -q '^Source status: READY$' "$ROOT_DIR/Vendor/LibreDWG/SOURCE_MANIFEST.md"; then
  if [[ "$RELEASE_MODE" == "1" ]]; then
    echo "[libredwg-gpl] ERROR: LibreDWG source manifest is not release-ready." >&2
    echo "[libredwg-gpl] Rebuild with scripts/cad/build_libredwg_ios_xcframework.sh and package Corresponding Source before release." >&2
    exit 1
  fi
  echo "[libredwg-gpl] WARN: LibreDWG artifact is bundled but SOURCE_MANIFEST.md is not release-ready."
  echo "[libredwg-gpl] PASS: required compliance files are present for development builds."
  exit 0
fi

if ! rg -q '^Upstream commit: [0-9a-f]{7,40}$' "$ROOT_DIR/Vendor/LibreDWG/SOURCE_MANIFEST.md"; then
  echo "[libredwg-gpl] ERROR: SOURCE_MANIFEST.md must record an exact LibreDWG upstream commit." >&2
  exit 1
fi

if rg -qi 'TODO|NOT_READY|UNKNOWN|REPLACE_BEFORE_RELEASE' "$ROOT_DIR/Vendor/LibreDWG/SOURCE_MANIFEST.md"; then
  echo "[libredwg-gpl] ERROR: SOURCE_MANIFEST.md still contains release blockers." >&2
  exit 1
fi

echo "[libredwg-gpl] PASS: LibreDWG GPL compliance metadata is present."
