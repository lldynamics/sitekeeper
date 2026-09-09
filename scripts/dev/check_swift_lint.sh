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
  # The configuration already includes Sources, Widget, Tests, and UITests.
  # Passing those directories separately repeats the configured scan for each root.
  paths=(.)
fi

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "[swiftlint] ERROR: swiftlint is not installed." >&2
  echo "Install it with: brew install swiftlint" >&2
  exit 127
fi

echo "[swiftlint] Checking ${#paths[@]} path(s)."
existing_paths=()
for path in "${paths[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "[swiftlint] Skip missing path: $path"
    continue
  fi
  existing_paths+=("$path")
done

if [[ ${#existing_paths[@]} -gt 0 ]]; then
  # --config accepts multiple values; terminate options so paths are not consumed as config files.
  swiftlint lint --no-cache --config "$ROOT_DIR/.swiftlint.yml" -- "${existing_paths[@]}"
fi
