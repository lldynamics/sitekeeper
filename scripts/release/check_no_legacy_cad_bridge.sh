#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Guard legacy bridge/runtime links and direct App-side LibreDWG execution.
PATTERNS=(
  'LibreDWGBridge'
  'LibreDWGCanvasRenderer'
  'LegacyLibreDWG'
  'dwg_bridge'
  '\bDWGBridge\b'
  'LibreDWGGeometrySource'
  'LibreDWGDXFConversionSource'
  'LibreDWGJSONAdapter'
  'DWGGeometryCommandRunner'
  '\bdwgread\b'
  '\bdwg2dxf\b'
)

TARGETS=(
  "$ROOT_DIR/project.yml"
  "$ROOT_DIR/sitekeeper.xcodeproj/project.pbxproj"
  "$ROOT_DIR/Sources"
  "$ROOT_DIR/SiteKeeperCADKernel"
)

if MATCHES="$(rg -n --color=never "${TARGETS[@]}" \
  --regexp "${PATTERNS[0]}" \
  --regexp "${PATTERNS[1]}" \
  --regexp "${PATTERNS[2]}" \
  --regexp "${PATTERNS[3]}" \
  --regexp "${PATTERNS[4]}" \
  --regexp "${PATTERNS[5]}" \
  --regexp "${PATTERNS[6]}" \
  --regexp "${PATTERNS[7]}" \
  --regexp "${PATTERNS[8]}" \
  --regexp "${PATTERNS[9]}" \
  --regexp "${PATTERNS[10]}" || true)"; then
  if [[ -n "$MATCHES" ]]; then
    echo "[cad-guard] 生产路径检测到遗留 CAD 桥接引用："
    echo "$MATCHES"
    exit 1
  fi
fi

echo "[cad-guard] PASS: 生产路径未发现遗留 CAD 桥接引用。"
