#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/lib/policy_search.sh"

# Production code must route destructive project-asset deletes through
# DataStoreDeletionPolicy so audit, undo, and deferred cleanup stay consistent.
ALLOWED_FILES=(
  "Sources/Shared/Helpers/DataStoreDeletionPolicy.swift"
  "Sources/Shared/Services/Persistence/DataStore/Maintenance/DataStoreDeferredFileCleanup.swift"
  "Sources/Shared/Services/Storage/Photos/PhotoStorage.swift"
  "Sources/Shared/Services/Storage/Documents/DocumentStorage.swift"
  "Sources/Shared/Services/Storage/Documents/ProjectDocumentStorage.swift"
  "Sources/Shared/Services/Storage/Drawings/DrawingStorage.swift"
  "Sources/Shared/Services/Storage/QuickNotes/QuickNoteAttachmentStorage.swift"
)

MATCHES="$(
  policy_search -n --color=never --glob '*.swift' \
    --regexp '(^|[^[:alnum:]_])PhotoStorage\.(delete|deleteOrThrow)(^|[^[:alnum:]_])' \
    --regexp '(^|[^[:alnum:]_])DrawingStorage\.(delete|deleteOrThrow)(^|[^[:alnum:]_])' \
    --regexp '(^|[^[:alnum:]_])QuickNoteAttachmentStorage\.(delete|deleteOrThrow)(^|[^[:alnum:]_])' \
    --regexp '(^|[^[:alnum:]_])ProjectDocumentStorage\.(delete|deleteOrThrow)(^|[^[:alnum:]_])' \
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
