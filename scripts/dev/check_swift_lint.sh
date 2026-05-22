#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: scripts/dev/check_swift_lint.sh [--staged] [paths...]

Checks Swift style with SwiftLint.
  --staged   Check staged Swift files only, for pre-commit hooks.
  paths      Optional files or directories. Defaults to app, widget, and tests.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

paths=()
if [[ "${1:-}" == "--staged" ]]; then
  shift
  if [[ $# -gt 0 ]]; then
    echo "[swiftlint] ERROR: --staged cannot be combined with explicit paths." >&2
    usage >&2
    exit 2
  fi
  while IFS= read -r -d '' path; do
    [[ -f "$path" ]] && paths+=("$path")
  done < <(git diff --cached --name-only --diff-filter=ACMR -z -- '*.swift')

  if [[ ${#paths[@]} -eq 0 ]]; then
    echo "[swiftlint] No staged Swift files to check."
    exit 0
  fi
elif [[ $# -gt 0 ]]; then
  paths=("$@")
else
  paths=(Sources Widget Tests UITests)
fi

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "[swiftlint] ERROR: swiftlint is not installed." >&2
  echo "Install it with: brew install swiftlint" >&2
  exit 127
fi

status=0
echo "[swiftlint] Checking ${#paths[@]} path(s)."
for path in "${paths[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "[swiftlint] Skip missing path: $path"
    continue
  fi
  if ! swiftlint lint --config "$ROOT_DIR/.swiftlint.yml" "$path"; then
    status=1
  fi
done

exit $status
