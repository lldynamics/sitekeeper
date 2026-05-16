#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

files=(
  "Sources/Resources/zh-Hans.lproj/Localizable.strings"
  "Sources/Resources/en.lproj/Localizable.strings"
)

failed=0

for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "[localization-integrity] ERROR: missing $file" >&2
    failed=1
    continue
  fi

  duplicates="$(
    awk -F'"' '
      /^"/ {
        count[$2] += 1
        if (count[$2] == 2) {
          print $2
        }
      }
    ' "$file"
  )"

  if [[ -n "$duplicates" ]]; then
    echo "[localization-integrity] ERROR: duplicate keys in $file" >&2
    printf '%s\n' "$duplicates" | sed 's/^/  - /' >&2
    failed=1
  fi
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "[localization-integrity] PASS: Localizable.strings keys are unique."
