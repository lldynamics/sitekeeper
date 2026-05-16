#!/usr/bin/env bash
set -euo pipefail

strict=0
if [[ "${1:-}" == "--strict" ]]; then
  strict=1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

scripts/localization/check_localization_integrity.sh

targets=(
  "Sources/Features"
  "Sources/Shared/Services"
  "Sources/Shared/Views"
  "Sources/Shared/Helpers"
)

exclude_pattern='CAD|cad|CADD|DWG|LibreDWG|SiteKeeperCADKernel'
interpolated_pattern='String\(localized:\s*\"[^\"]*\\\('
hardcoded_ui_pattern='Text\(\"[^\"]*[\p{Han}][^\"]*\"\)|Label\(\"[^\"]*[\p{Han}][^\"]*\"|Button\(\"[^\"]*[\p{Han}][^\"]*\"|TextField\(\"[^\"]*[\p{Han}][^\"]*\"|Section\(\"[^\"]*[\p{Han}][^\"]*\"\)|Toggle\(\"[^\"]*[\p{Han}][^\"]*\"|Picker\(\"[^\"]*[\p{Han}][^\"]*\"|LabeledContent\(\"[^\"]*[\p{Han}][^\"]*\"|Menu\(\"[^\"]*[\p{Han}][^\"]*\"|navigationTitle\(\"[^\"]*[\p{Han}][^\"]*\"|ContentUnavailableView\(\"[^\"]*[\p{Han}][^\"]*\"|alert\(\"[^\"]*[\p{Han}][^\"]*\"'
supporting_copy_pattern='hint:\s*\"[^\"]*[\p{Han}][^\"]*\"|presentError\(\"[^\"]*[\p{Han}][^\"]*\"|headline:\s*\"[^\"]*[\p{Han}][^\"]*\"|formula:\s*\"[^\"]*[\p{Han}][^\"]*\"|CalculationResult\.item\(\"[^\"]*[\p{Han}][^\"]*\"|tool:\s*\"[^\"]*[\p{Han}][^\"]*\"|input:\s*\"[^\"]*[\p{Han}][^\"]*\"|title:\s*\"[^\"]*[\p{Han}][^\"]*\"'

interpolated_matches="$(rg -n "$interpolated_pattern" "${targets[@]}" | rg -v "$exclude_pattern" || true)"
hardcoded_ui_matches="$(rg -n "$hardcoded_ui_pattern" "${targets[@]}" | rg -v "$exclude_pattern" || true)"
supporting_copy_matches="$(rg -n "$supporting_copy_pattern" "${targets[@]}" | rg -v "$exclude_pattern" || true)"

interpolated_count="$(printf '%s\n' "$interpolated_matches" | sed '/^$/d' | wc -l | tr -d ' ')"
hardcoded_ui_count="$(printf '%s\n' "$hardcoded_ui_matches" | sed '/^$/d' | wc -l | tr -d ' ')"
supporting_copy_count="$(printf '%s\n' "$supporting_copy_matches" | sed '/^$/d' | wc -l | tr -d ' ')"

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

echo
echo "Supporting hardcoded Chinese strings: ${supporting_copy_count}"
if [[ "$supporting_copy_count" -gt 0 ]]; then
  printf '%s\n' "$supporting_copy_matches" \
    | cut -d: -f1 \
    | sort \
    | uniq -c \
    | sort -nr \
    | head -n 40
fi

if [[ "$strict" -eq 1 ]] && [[ "$interpolated_count" -gt 0 || "$hardcoded_ui_count" -gt 0 || "$supporting_copy_count" -gt 0 ]]; then
  exit 1
fi
