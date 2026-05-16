#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Guard legacy bridge/runtime links and CLI-based LibreDWG conversion in production code.
PATTERNS=(
  'LibreDWGBridge'
  'LibreDWGCanvasRenderer'
  'LegacyLibreDWG'
  'dwg_bridge'
  '\bDWGBridge\b'
  'LibreDWGGeometrySource'
  'LibreDWGDXFConversionSource'
  'LibreDWGJSONAdapter'
  'CADRemoteDWGConversionAdapter'
  'CADRemoteDWGConversionSettings'
  'cad\.dwgConversion\.serviceURL'
  'CAD_DWG_REMOTE_LIBREDWG_JSON_USED'
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

RG_ARGS=(-n --color=never)
for pattern in "${PATTERNS[@]}"; do
  RG_ARGS+=(--regexp "$pattern")
done

if MATCHES="$(rg "${RG_ARGS[@]}" "${TARGETS[@]}" || true)"; then
  if [[ -n "$MATCHES" ]]; then
    echo "[cad-guard] 生产路径检测到遗留 CAD 桥接引用："
    echo "$MATCHES"
    exit 1
  fi
fi

echo "[cad-guard] PASS: 生产路径未发现遗留 CAD 桥接引用。"
