#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  echo "[swiftui-identity-policy] FAIL: ripgrep (rg) is unavailable in the build script PATH." >&2
  exit 127
fi

MATCHES=""
MATCHES+="$(rg -n --color=never --glob '*.swift' 'ForEach\(\s*Array\(.*\.enumerated\(\)\)\s*,\s*id:\s*\\\.offset' Sources Widget || true)"
MATCHES+=$'\n'
MATCHES+="$(rg -n --color=never --glob '*.swift' 'ForEach\([^)]*id:\s*\\\.offset' Sources Widget || true)"

if [[ -n "${MATCHES//$'\n'/}" ]]; then
  echo "[swiftui-identity-policy] FAIL: detected unstable ForEach identity (id: .offset) in production targets:" >&2
  echo "$MATCHES" | sed '/^[[:space:]]*$/d' >&2
  echo >&2
  echo "Use stable identity keys (model id / semantic key / explicit Identifiable wrapper) instead of offset." >&2
  exit 1
fi

echo "[swiftui-identity-policy] PASS: no ForEach id: .offset usage in Sources/Widget."
