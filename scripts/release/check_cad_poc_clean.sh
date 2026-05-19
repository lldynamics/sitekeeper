#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Guard the production CAD PoC route against retired preview/import paths.
FORBIDDEN_PATTERNS=(
  "CAD""TileViewer"
  "CAD""ConversionPipeline"
  "Sidecar""GeometrySource"
  "Unsupported""CADViewerEngine"
  "DWG""DiagnosticImportEngine"
  "diagnostic""Only"
  "CAD""FallbackViewer"
  "CAD""Canvas2DRenderer"
  "Unsupported""CADImportEngine"
  "SiteKeeper""CADKernelAppViewerEngine"
)

TARGETS=(
  "$ROOT_DIR/project.yml"
  "$ROOT_DIR/sitekeeper.xcodeproj/project.pbxproj"
  "$ROOT_DIR/Sources"
  "$ROOT_DIR/SiteKeeperCADKernel"
)

RG_ARGS=(-n --color=never)
for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
  RG_ARGS+=(--regexp "$pattern")
done

EXISTING_TARGETS=()
for target in "${TARGETS[@]}"; do
  [[ -e "$target" ]] && EXISTING_TARGETS+=("$target")
done

if [[ ${#EXISTING_TARGETS[@]} -eq 0 ]]; then
  echo "[cad-poc-clean] FAIL: no production targets found to scan."
  exit 1
fi

MATCHES="$(rg "${RG_ARGS[@]}" "${EXISTING_TARGETS[@]}" || true)"
if [[ -n "$MATCHES" ]]; then
  echo "[cad-poc-clean] FAIL: production target contains retired CAD PoC paths:"
  echo "$MATCHES"
  echo
  echo "Allowed locations for these terms are Deprecated/CAD/, docs/, or build reports only."
  exit 1
fi

echo "[cad-poc-clean] PASS: production CAD PoC path is clean."
