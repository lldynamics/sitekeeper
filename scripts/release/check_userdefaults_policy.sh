#!/usr/bin/env bash
set -euo pipefail

export PATH="/Applications/Codex.app/Contents/Resources:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:$PATH"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if ! command -v rg >/dev/null 2>&1; then
  echo "[userdefaults-policy] FAIL: ripgrep (rg) is unavailable in the build script PATH." >&2
  exit 127
fi

MATCHES="$(rg -n --color=never --glob '*.swift' 'UserDefaults\.standard' Sources Widget || true)"
if [[ -n "$MATCHES" ]]; then
  echo "[userdefaults-policy] FAIL: detected direct UserDefaults.standard usage in production targets:" >&2
  echo "$MATCHES" >&2
  echo >&2
  echo "Use UserPreferencesStore or scoped suite defaults helpers instead of direct standard access." >&2
  exit 1
fi

APP_STORAGE_LITERAL_MATCHES="$(rg -n --color=never --glob '*.swift' '@AppStorage\(\s*"[^"]+"' Sources Widget || true)"
if [[ -n "$APP_STORAGE_LITERAL_MATCHES" ]]; then
  echo "[userdefaults-policy] FAIL: detected @AppStorage literal keys in production targets:" >&2
  echo "$APP_STORAGE_LITERAL_MATCHES" >&2
  echo >&2
  echo "Use UserPreferenceKeys.* constants for @AppStorage keys instead of string literals." >&2
  exit 1
fi

echo "[userdefaults-policy] PASS: no direct UserDefaults.standard usage or @AppStorage literal keys in Sources/Widget."
