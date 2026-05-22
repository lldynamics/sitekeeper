#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: scripts/dev/format_swift.sh [--staged] [paths...]

Formats Swift code with SwiftFormat.
  --staged   Format staged Swift files only.
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
    echo "[swiftformat] ERROR: --staged cannot be combined with explicit paths." >&2
    usage >&2
    exit 2
  fi
  while IFS= read -r -d '' path; do
    [[ -f "$path" ]] && paths+=("$path")
  done < <(git diff --cached --name-only --diff-filter=ACMR -z -- '*.swift')

  if [[ ${#paths[@]} -eq 0 ]]; then
    echo "[swiftformat] No staged Swift files to format."
    exit 0
  fi
elif [[ $# -gt 0 ]]; then
  paths=("$@")
else
  paths=(Sources Widget Tests UITests)
fi

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "[swiftformat] ERROR: swiftformat is not installed." >&2
  echo "Install it with: brew install swiftformat" >&2
  exit 127
fi

echo "[swiftformat] Formatting ${#paths[@]} path(s)."
swiftformat --config "$ROOT_DIR/.swiftformat" "${paths[@]}"
