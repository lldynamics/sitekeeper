#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/lib/policy_search.sh"

# App UI in Sources should use semantic fonts so Dynamic Type can scale text.
# Fixed point sizes in SwiftUI .font(.system(size: ...)) block accessibility.
MATCHES="$(
  policy_search -n --color=never --glob '*.swift' \
    --regexp '\.font\(\.system\(size:' \
    --regexp 'Font\.system\(size:' \
    Sources || true
)"

if [[ -n "$MATCHES" ]]; then
  echo "[dynamic-type-policy] FAIL: detected fixed-size font usage in Sources:" >&2
  echo "$MATCHES" >&2
  echo >&2
  echo "Use semantic text styles (for example .headline/.body/.title3) instead of fixed size fonts." >&2
  exit 1
fi

echo "[dynamic-type-policy] PASS: no fixed-size font usage in Sources."
