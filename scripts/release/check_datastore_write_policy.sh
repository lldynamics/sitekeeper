#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/lib/policy_search.sh"

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
  RG_ARGS+=(--regexp "(^|[^[:alnum:]_])store\\.${property}[[:space:]]*=")
  RG_ARGS+=(--regexp "(^|[^[:alnum:]_])store\\.${property}\\.append[[:space:]]*\\(")
  RG_ARGS+=(--regexp "(^|[^[:alnum:]_])store\\.${property}\\.insert[[:space:]]*\\(")
  RG_ARGS+=(--regexp "(^|[^[:alnum:]_])store\\.${property}\\.removeAll[[:space:]]*(\\(|\\{)")
  RG_ARGS+=(--regexp "(^|[^[:alnum:]_])store\\.${property}\\[[^]]+\\][[:space:]]*=")
done

MATCHES="$(policy_search "${RG_ARGS[@]}" Sources || true)"
if [[ -n "$MATCHES" ]]; then
  echo "[datastore-write-policy] FAIL: detected direct DataStore array writes:" >&2
  echo "$MATCHES" >&2
  echo >&2
  echo "Use DataStore domain methods instead of mutating store.<array> directly." >&2
  exit 1
fi

# Domain stores are implementation details of DataStore. Feature and app code
# may read them for narrow indexed queries, but every mutation must cross an
# explicit DataStore write port so save/audit behavior cannot be bypassed.
DOMAIN_STORE_MUTATIONS="$(
  policy_search -n --color=never --glob '*.swift' \
    --regexp '(^|[^[:alnum:]_])(projectStore|financeStore|materialLibraryStore|materialLibraryPreferencesStore)\.(set|replace|append|insert|remove|restore|toggle)[A-Z]' \
    Sources/Features Sources/App || true
)"
if [[ -n "$DOMAIN_STORE_MUTATIONS" ]]; then
  echo "[datastore-write-policy] FAIL: feature code bypasses DataStore domain write ports:" >&2
  echo "$DOMAIN_STORE_MUTATIONS" >&2
  echo >&2
  echo "Add or use an explicit DataStore write method instead of mutating a domain store." >&2
  exit 1
fi

echo "[datastore-write-policy] PASS: DataStore arrays and domain stores are mutated only through approved write ports."
