#!/usr/bin/env bash
set -euo pipefail

export PATH="/Applications/Codex.app/Contents/Resources:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  echo "[datastore-write-policy] FAIL: ripgrep (rg) is unavailable in the build script PATH." >&2
  exit 127
fi

# These arrays are private(set) in DataStore and must be mutated only through
# explicit domain APIs (append/update/replace/merge/remove/restore helpers).
PROTECTED_PROPERTIES=(
  materialItems
  quoteItems
  laborRecords
  projects
  dailyLogs
  historyRecords
  progressTasks
  lightingCircuitPlans
  siteTodos
  projectDrawings
  projectContacts
  projectFinancialRecords
  projectDocuments
  quickNotes
  projectWarehouseMovements
  templates
  materialPriceEntries
  materialSheetDrafts
  supplierProfiles
  constructionMethods
  userMaterials
  deletedUserMaterials
)

RG_ARGS=(-n --color=never --glob '*.swift')
for property in "${PROTECTED_PROPERTIES[@]}"; do
  RG_ARGS+=(--regexp "\\bstore\\.${property}\\s*=")
  RG_ARGS+=(--regexp "\\bstore\\.${property}\\.append\\s*\\(")
  RG_ARGS+=(--regexp "\\bstore\\.${property}\\.insert\\s*\\(")
  RG_ARGS+=(--regexp "\\bstore\\.${property}\\.removeAll\\s*(\\(|\\{)")
  RG_ARGS+=(--regexp "\\bstore\\.${property}\\[[^]]+\\]\\s*=")
done

MATCHES="$(rg "${RG_ARGS[@]}" Sources || true)"
if [[ -n "$MATCHES" ]]; then
  echo "[datastore-write-policy] FAIL: detected direct DataStore array writes:" >&2
  echo "$MATCHES" >&2
  echo >&2
  echo "Use DataStore domain methods instead of mutating store.<array> directly." >&2
  exit 1
fi

echo "[datastore-write-policy] PASS: no direct DataStore array writes detected."
