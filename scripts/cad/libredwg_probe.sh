#!/usr/bin/env bash
set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <drawing.dwg> [output-dir]" >&2
  exit 2
fi

DWG_PATH="$1"
OUT_DIR="${2:-build/cad-probe}"

mkdir -p "$OUT_DIR"
rm -f \
  "$OUT_DIR/out.json" \
  "$OUT_DIR/out.dxf" \
  "$OUT_DIR/out2.dxf" \
  "$OUT_DIR/dwgread_json.log" \
  "$OUT_DIR/dwgread_dxf.log" \
  "$OUT_DIR/dwg2dxf.log" \
  "$OUT_DIR/dwgread_version.log" \
  "$OUT_DIR/dwg2dxf_version.log"

if [[ ! -f "$DWG_PATH" ]]; then
  echo "DWG file not found: $DWG_PATH" >&2
  exit 2
fi

DWGREAD_AVAILABLE=0
DWG2DXF_AVAILABLE=0
DWGREAD_JSON_EXIT=127
DWGREAD_DXF_EXIT=127
DWG2DXF_EXIT=127

if command -v dwgread >/dev/null 2>&1; then
  DWGREAD_AVAILABLE=1
  dwgread --version >"$OUT_DIR/dwgread_version.log" 2>&1
else
  echo "dwgread not found" >"$OUT_DIR/dwgread_version.log"
fi

if command -v dwg2dxf >/dev/null 2>&1; then
  DWG2DXF_AVAILABLE=1
  dwg2dxf --version >"$OUT_DIR/dwg2dxf_version.log" 2>&1
else
  echo "dwg2dxf not found" >"$OUT_DIR/dwg2dxf_version.log"
fi

if [[ "$DWGREAD_AVAILABLE" -eq 1 ]]; then
  dwgread -v5 -O JSON -o "$OUT_DIR/out.json" "$DWG_PATH" 2>"$OUT_DIR/dwgread_json.log"
  DWGREAD_JSON_EXIT=$?

  dwgread -v5 -O DXF -o "$OUT_DIR/out.dxf" "$DWG_PATH" 2>"$OUT_DIR/dwgread_dxf.log"
  DWGREAD_DXF_EXIT=$?
else
  echo "dwgread not found" >"$OUT_DIR/dwgread_json.log"
  echo "dwgread not found" >"$OUT_DIR/dwgread_dxf.log"
fi

if [[ "$DWG2DXF_AVAILABLE" -eq 1 ]]; then
  dwg2dxf -v5 -y -o "$OUT_DIR/out2.dxf" "$DWG_PATH" 2>"$OUT_DIR/dwg2dxf.log"
  DWG2DXF_EXIT=$?
else
  echo "dwg2dxf not found" >"$OUT_DIR/dwg2dxf.log"
fi

ARGS=(
  --dwg "$DWG_PATH"
  --out-dir "$OUT_DIR"
  --dwgread-json-exit-code "$DWGREAD_JSON_EXIT"
  --dwgread-dxf-exit-code "$DWGREAD_DXF_EXIT"
  --dwg2dxf-exit-code "$DWG2DXF_EXIT"
)

if [[ "$DWGREAD_AVAILABLE" -eq 1 ]]; then
  ARGS+=(--dwgread-available)
fi
if [[ "$DWG2DXF_AVAILABLE" -eq 1 ]]; then
  ARGS+=(--dwg2dxf-available)
fi

python3 "$(dirname "$0")/inspect_libredwg_output.py" "${ARGS[@]}"
