#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# Production code must route destructive project-asset deletes through
# DataStoreDeletionPolicy so audit, undo, and deferred cleanup stay consistent.
ALLOWED_FILES=(
  "Sources/Shared/Services/DataStoreDeletionPolicy.swift"
  "Sources/Shared/Services/PhotoStorage.swift"
  "Sources/Shared/Services/DocumentStorage.swift"
  "Sources/Shared/Services/ProjectDocumentStorage.swift"
  "Sources/Shared/Services/DrawingStorage.swift"
  "Sources/Shared/Services/QuickNoteAttachmentStorage.swift"
)

MATCHES="$(
  rg -n --color=never --glob '*.swift' \
    --regexp '\bPhotoStorage\.(delete|deleteOrThrow)\b' \
    --regexp '\bDrawingStorage\.(delete|deleteOrThrow)\b' \
    --regexp '\bQuickNoteAttachmentStorage\.(delete|deleteOrThrow)\b' \
    --regexp '\bProjectDocumentStorage\.(delete|deleteOrThrow)\b' \
    Sources || true
)"

VIOLATIONS=()
if [[ -n "$MATCHES" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    file="${line%%:*}"
    allowed=0
    for allowed_file in "${ALLOWED_FILES[@]}"; do
      if [[ "$file" == "$allowed_file" ]]; then
        allowed=1
        break
      fi
    done

    if [[ "$allowed" -ne 1 ]]; then
      VIOLATIONS+=("$line")
    fi
  done <<< "$MATCHES"
fi

if [[ "${#VIOLATIONS[@]}" -gt 0 ]]; then
  echo "[file-deletion-policy] FAIL: production code bypasses DataStoreDeletionPolicy:" >&2
  printf '%s\n' "${VIOLATIONS[@]}" >&2
  echo >&2
  echo "Route project photos, drawings, documents, and quick-note attachments through DataStoreDeletionPolicy." >&2
  exit 1
fi

echo "[file-deletion-policy] PASS: destructive file deletes are routed through the deletion policy."
