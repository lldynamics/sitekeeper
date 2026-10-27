#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/lib/policy_search.sh"

MATCHES=""
MATCHES+="$(policy_search -n --color=never --glob '*.swift' 'ForEach\([[:space:]]*Array\(.*\.enumerated\(\)\)[[:space:]]*,[[:space:]]*id:[[:space:]]*\\\.offset' Sources Widget || true)"
MATCHES+=$'\n'
MATCHES+="$(policy_search -n --color=never --glob '*.swift' 'ForEach\([^)]*id:[[:space:]]*\\\.offset' Sources Widget || true)"

if [[ -n "${MATCHES//$'\n'/}" ]]; then
  echo "[swiftui-identity-policy] FAIL: detected unstable ForEach identity (id: .offset) in production targets:" >&2
  echo "$MATCHES" | sed '/^[[:space:]]*$/d' >&2
  echo >&2
  echo "Use stable identity keys (model id / semantic key / explicit Identifiable wrapper) instead of offset." >&2
  exit 1
fi

echo "[swiftui-identity-policy] PASS: no ForEach id: .offset usage in Sources/Widget."
