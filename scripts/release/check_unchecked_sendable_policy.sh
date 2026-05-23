#!/usr/bin/env bash
set -euo pipefail

export PATH="/Applications/Codex.app/Contents/Resources:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  echo "[unchecked-sendable-policy] FAIL: ripgrep (rg) is unavailable in the build script PATH." >&2
  exit 127
fi

VIOLATIONS="$(
  rg -n --color=never --glob '*.swift' '@unchecked[[:space:]]+Sendable' Sources Widget 2>/dev/null \
    | awk '
      {
        code = $0
        sub(/^[^:]+:[0-9]+:/, "", code)
        gsub(/^[[:space:]]+/, "", code)

        # Skip line comments.
        if (code ~ /^\/\//) {
          next
        }

        # Allow only class declarations to carry @unchecked Sendable.
        if (code ~ /class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/) {
          next
        }

        print $0
      }
    ' || true
)"

if [[ -n "$VIOLATIONS" ]]; then
  echo "[unchecked-sendable-policy] FAIL: detected @unchecked Sendable on non-class declarations:" >&2
  echo "$VIOLATIONS" >&2
  echo >&2
  echo "Use declaration-site Sendable for struct/enum/value models. Reserve @unchecked Sendable for proven-safe class cases only." >&2
  exit 1
fi

echo "[unchecked-sendable-policy] PASS: @unchecked Sendable is restricted to class declarations."
