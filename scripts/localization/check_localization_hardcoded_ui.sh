#!/usr/bin/env bash
set -euo pipefail

strict=0
if [[ "${1:-}" == "--strict" ]]; then
  strict=1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

targets=(
  "Sources/Features/首页"
  "Sources/Features/项目"
  "Sources/Features/清单"
  "Sources/Features/我的"
)

exclude_pattern='CAD|cad|CADD|DWG|LibreDWG|SiteKeeperCADKernel'
interpolated_pattern='String\(localized:\s*\"[^\"]*\\\('
hardcoded_ui_pattern='Text\(\"[^\"]*[\p{Han}][^\"]*\"\)|Label\(\"[^\"]*[\p{Han}][^\"]*\"|Button\(\"[^\"]*[\p{Han}][^\"]*\"|TextField\(\"[^\"]*[\p{Han}][^\"]*\"|Section\(\"[^\"]*[\p{Han}][^\"]*\"\)|Toggle\(\"[^\"]*[\p{Han}][^\"]*\"|Picker\(\"[^\"]*[\p{Han}][^\"]*\"'

interpolated_matches="$(rg -n "$interpolated_pattern" "${targets[@]}" | rg -v "$exclude_pattern" || true)"
hardcoded_ui_matches="$(rg -n "$hardcoded_ui_pattern" "${targets[@]}" | rg -v "$exclude_pattern" || true)"

interpolated_count="$(printf '%s\n' "$interpolated_matches" | sed '/^$/d' | wc -l | tr -d ' ')"
hardcoded_ui_count="$(printf '%s\n' "$hardcoded_ui_matches" | sed '/^$/d' | wc -l | tr -d ' ')"

echo "Localization audit scope: ${targets[*]}"
echo "Interpolated localized keys: ${interpolated_count}"
if [[ "$interpolated_count" -gt 0 ]]; then
  printf '%s\n' "$interpolated_matches" | head -n 80
fi

echo
echo "Hardcoded Chinese UI strings: ${hardcoded_ui_count}"
if [[ "$hardcoded_ui_count" -gt 0 ]]; then
  printf '%s\n' "$hardcoded_ui_matches" \
    | cut -d: -f1 \
    | sort \
    | uniq -c \
    | sort -nr \
    | head -n 40
fi

if [[ "$strict" -eq 1 ]] && [[ "$interpolated_count" -gt 0 || "$hardcoded_ui_count" -gt 0 ]]; then
  exit 1
fi
