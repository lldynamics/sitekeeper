#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "[drawing-release-boundary] FAIL: $1" >&2
  exit 1
}

if ! command -v rg >/dev/null 2>&1; then
  fail "ripgrep (rg) is unavailable in the build script PATH."
fi

require_file() {
  local description="$1"
  local path="$2"

  [[ -f "$path" ]] || fail "$description is missing: $path"
}

require_pattern() {
  local description="$1"
  local path="$2"
  local pattern="$3"

  require_file "$description" "$path"
  if ! rg -q --fixed-strings "$pattern" "$path"; then
    fail "$description is missing expected marker '$pattern' in $path"
  fi
}

require_pattern_in_any() {
  local description="$1"
  local pattern="$2"
  shift 2

  local existing_paths=()
  local path
  for path in "$@"; do
    if [[ -f "$path" ]]; then
      existing_paths+=("$path")
    fi
  done

  [[ "${#existing_paths[@]}" -gt 0 ]] || fail "$description has no files to scan"
  if ! rg -q --fixed-strings "$pattern" "${existing_paths[@]}"; then
    fail "$description is missing expected marker '$pattern' in ${existing_paths[*]}"
  fi
}

FORBIDDEN_PRODUCTION_SYMBOLS=(
  LibreDWG
  CADMetalRenderer
  CADRendererProvider
  SiteKeeperCADKernel
)

PRODUCTION_SCAN_PATHS=()
for path in Sources Widget project.yml sitekeeper.xcodeproj/project.pbxproj; do
  if [[ -e "$path" ]]; then
    PRODUCTION_SCAN_PATHS+=("$path")
  fi
done

if [[ "${#PRODUCTION_SCAN_PATHS[@]}" -eq 0 ]]; then
  fail "no production paths were available to scan"
fi

RG_ARGS=(-n --color=never)
for symbol in "${FORBIDDEN_PRODUCTION_SYMBOLS[@]}"; do
  RG_ARGS+=(--regexp "$symbol")
done

FORBIDDEN_MATCHES="$(rg "${RG_ARGS[@]}" "${PRODUCTION_SCAN_PATHS[@]}" || true)"
if [[ -n "$FORBIDDEN_MATCHES" ]]; then
  echo "[drawing-release-boundary] FAIL: removed CAD kernel symbols still appear in production target inputs:" >&2
  echo "$FORBIDDEN_MATCHES" >&2
  echo >&2
  echo "Keep the production app on drawing ledger/original-file management only; do not reintroduce the removed CAD kernel path." >&2
  exit 1
fi

require_pattern "ProjectDrawing domain model" "Sources/Shared/Services/ProjectDomainDrawingTypes.swift" "struct ProjectDrawing"
require_pattern "ProjectDrawing allowed import contract" "Sources/Shared/Services/ProjectDomainDrawingTypes.swift" "allowedFileExtensions"
require_pattern "drawing file storage" "Sources/Shared/Services/DrawingStorage.swift" "enum DrawingStorage"
require_pattern "DataStore drawing write port" "Sources/Shared/Services/DataStore+ProjectDrawingOps.swift" "appendProjectDrawing"
require_pattern "DataStore drawing write port" "Sources/Shared/Services/DataStore+ProjectDrawingOps.swift" "removeProjectDrawings"
require_pattern "drawing library tool entry" "Sources/Features/清单/ToolboxCatalog.swift" "drawing-library"
require_pattern "drawing library screen" "Sources/Features/清单/DrawingLibraryToolView.swift" "DrawingLibraryToolView"
require_pattern "backup drawing metadata contract" "Sources/Shared/Services/BackupSnapshot.swift" "projectDrawings: [ProjectDrawing]"
require_pattern "backup drawing file contract" "Sources/Shared/Services/BackupSnapshot.swift" "drawingFiles: [DrawingBackupFile]"
require_pattern_in_any \
  "backup archive drawing files" \
  "DrawingStorage.fileURL" \
  "Sources/Shared/Services/BackupArchiveService.swift" \
  "Sources/Shared/Services/BackupArchiveService+Write.swift" \
  "Sources/Shared/Services/BackupArchiveRestoreSupport.swift"
require_pattern "export option preserves drawing index" "Sources/Shared/Services/ReportBuilderTypes.swift" "includeProjectDrawings"
require_pattern "CSV export preserves drawing index" "Sources/Shared/Services/ReportBuilder+CSVSections.swift" "project_drawings"
require_pattern "user export flow exposes drawing index" "Sources/Features/我的/ExportView.swift" "includeProjectDrawings"

echo "[drawing-release-boundary] PASS: removed CAD kernel symbols are absent and drawing ledger/export contracts remain present."
