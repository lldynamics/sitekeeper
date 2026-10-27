#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/lib/policy_search.sh"
source "$ROOT_DIR/scripts/lib/localization_search.sh"
TASK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sitekeeper-policy-search.XXXXXX")"
trap 'rm -rf "$TASK_DIR"' EXIT
mkdir -p "$TASK_DIR/fixture/sub folder"
cat > "$TASK_DIR/fixture/sub folder/Probe.swift" <<'SWIFT'
store.dailyLogs.append(value)
store.dailyLogs = []
store.dailyLogs[0] = item
projectStore.replaceProjects(items)
Text("example").font(.system(size: 12))
UserDefaults.standard
@AppStorage("literal") var value = false
ForEach(items, id: \.offset) { item in Text(item) }
struct Model: @unchecked Sendable {}
PhotoStorage.delete(fileName: name)
SWIFT
for backend in auto grep; do
  SITEKEEPER_SEARCH_BACKEND="$backend" policy_search -n --glob '*.swift' \
    --regexp '(^|[^[:alnum:]_])store\.dailyLogs\.append[[:space:]]*\(' \
    --regexp '(^|[^[:alnum:]_])projectStore\.(set|replace)[A-Z]' "$TASK_DIR/fixture" > "$TASK_DIR/$backend.txt"
  [[ "$(wc -l < "$TASK_DIR/$backend.txt" | tr -d ' ')" == 2 ]]
  [[ -z "$(SITEKEEPER_SEARCH_BACKEND="$backend" policy_search -q --fixed-strings 'store.dailyLogs = []' "$TASK_DIR/fixture")" ]]
  if SITEKEEPER_SEARCH_BACKEND="$backend" policy_search -q 'absentMarker' "$TASK_DIR/fixture"; then
    echo 'No-match query returned success' >&2; exit 1
  fi
done
cmp "$TASK_DIR/auto.txt" "$TASK_DIR/grep.txt"

cat > "$TASK_DIR/fixture/Han.swift" <<'SWIFT'
Text("中文")
Text("English")
SWIFT
for backend in auto grep; do
  SITEKEEPER_SEARCH_BACKEND="$backend" localization_search 'Text\("[^"\n]*[\p{Han}][^"\n]*"\)' "$TASK_DIR/fixture" > "$TASK_DIR/han-$backend.txt"
  [[ "$(wc -l < "$TASK_DIR/han-$backend.txt" | tr -d ' ')" == 1 ]]
done
cmp "$TASK_DIR/han-auto.txt" "$TASK_DIR/han-grep.txt"
[[ -n "$(SITEKEEPER_SEARCH_BACKEND=grep localization_search '[' "$TASK_DIR/fixture" 2>/dev/null || true)" ]]

# Exercise the actual guards in a disposable source copy, including negative cases.
mkdir -p "$TASK_DIR/repo"
for path in Sources Widget Tests docs scripts project.yml sitekeeper.xcodeproj; do
  cp -R "$ROOT_DIR/$path" "$TASK_DIR/repo/"
done
GUARDS=(datastore_write_policy dynamic_type_policy file_deletion_policy swiftui_identity_policy unchecked_sendable_policy userdefaults_policy backup_contract_boundary drawing_release_boundary)
for backend in auto grep; do
  for guard in "${GUARDS[@]}"; do
    SITEKEEPER_SEARCH_BACKEND="$backend" bash "$TASK_DIR/repo/scripts/release/check_$guard.sh" > "$TASK_DIR/$guard-$backend.log"
  done
done
cp "$TASK_DIR/fixture/sub folder/Probe.swift" "$TASK_DIR/repo/Sources/PolicyViolation.swift"
for backend in auto grep; do
  for guard in "${GUARDS[@]:0:6}"; do
    if SITEKEEPER_SEARCH_BACKEND="$backend" bash "$TASK_DIR/repo/scripts/release/check_$guard.sh" > "$TASK_DIR/negative-$guard-$backend.log" 2>&1; then
      echo "Guard failed to reject injected violation: $guard ($backend)" >&2; exit 1
    fi
  done
done
rm "$TASK_DIR/repo/Sources/PolicyViolation.swift"
rm "$TASK_DIR/repo/Tests/Fixtures/SampleDataFixture.json"
rm "$TASK_DIR/repo/Sources/Features/Checklists/Drawings/DrawingLibraryToolView.swift"
for backend in auto grep; do
  for guard in backup_contract_boundary drawing_release_boundary; do
    if SITEKEEPER_SEARCH_BACKEND="$backend" bash "$TASK_DIR/repo/scripts/release/check_$guard.sh" > "$TASK_DIR/negative-$guard-$backend.log" 2>&1; then
      echo "Guard failed to reject missing contract input: $guard ($backend)" >&2; exit 1
    fi
  done
done
# A backend read/regex error must produce a diagnostic even when collected with || true.
[[ -n "$(SITEKEEPER_SEARCH_BACKEND=grep policy_search '[' "$TASK_DIR/fixture" 2>/dev/null || true)" ]]
echo 'PASS: search equivalence, quiet/fixed/no-match queries, 16 clean guards, 16 rejected violations, and search-error handling.'
