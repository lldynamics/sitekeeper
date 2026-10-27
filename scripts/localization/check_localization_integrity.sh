#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
source "$repo_root/scripts/lib/localization_search.sh"

localizable_files=(
  "Sources/Resources/zh-Hans.lproj/Localizable.strings"
  "Sources/Resources/en.lproj/Localizable.strings"
  "Widget/zh-Hans.lproj/Localizable.strings"
  "Widget/en.lproj/Localizable.strings"
)

info_plist_files=(
  "Sources/Resources/zh-Hans.lproj/InfoPlist.strings"
  "Sources/Resources/en.lproj/InfoPlist.strings"
  "Widget/zh-Hans.lproj/InfoPlist.strings"
  "Widget/en.lproj/InfoPlist.strings"
)

english_resource_files=(
  "Sources/Resources/en.lproj/Localizable.strings"
  "Sources/Resources/en.lproj/InfoPlist.strings"
  "Widget/en.lproj/Localizable.strings"
  "Widget/en.lproj/InfoPlist.strings"
)

required_app_info_plist_keys=(
  "CFBundleDisplayName"
  "NSCameraUsageDescription"
  "NSContactsUsageDescription"
  "NSLocationWhenInUseUsageDescription"
  "NSMicrophoneUsageDescription"
  "NSPhotoLibraryUsageDescription"
  "NSPhotoLibraryAddUsageDescription"
)

failed=0

string_keys() {
  awk -F'"' '/^"/ { print $2 }' "$1" | sort
}

check_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "[localization-integrity] ERROR: missing $file" >&2
    failed=1
    return
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
}

check_matching_keys() {
  local zh_file="$1"
  local en_file="$2"

  if [[ ! -f "$zh_file" || ! -f "$en_file" ]]; then
    return
  fi

  missing_en="$(comm -23 <(string_keys "$zh_file") <(string_keys "$en_file"))"
  missing_zh="$(comm -13 <(string_keys "$zh_file") <(string_keys "$en_file"))"

  if [[ -n "$missing_en" ]]; then
    echo "[localization-integrity] ERROR: keys missing from $en_file" >&2
    printf '%s\n' "$missing_en" | sed 's/^/  - /' >&2
    failed=1
  fi

  if [[ -n "$missing_zh" ]]; then
    echo "[localization-integrity] ERROR: keys missing from $zh_file" >&2
    printf '%s\n' "$missing_zh" | sed 's/^/  - /' >&2
    failed=1
  fi
}

check_required_app_info_plist_keys() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    return
  fi

  for key in "${required_app_info_plist_keys[@]}"; do
    if ! string_keys "$file" | grep -Fxq "$key"; then
      echo "[localization-integrity] ERROR: missing required InfoPlist key $key in $file" >&2
      failed=1
    fi
  done
}

check_english_resource_values() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    return
  fi

  # Language names may intentionally be shown in their native script.
  untranslated_values="$(
    localization_search '=\s*"[^"]*[\p{Han}][^"]*";' "$file" \
      | grep -Ev ':"中文" = "中文";$' \
      || true
  )"

  if [[ -n "$untranslated_values" ]]; then
    echo "[localization-integrity] ERROR: Chinese text remains in English resources: $file" >&2
    printf '%s\n' "$untranslated_values" | sed 's/^/  - /' >&2
    failed=1
  fi
}

for file in "${localizable_files[@]}" "${info_plist_files[@]}"; do
  check_file "$file"
done

check_matching_keys "Sources/Resources/zh-Hans.lproj/Localizable.strings" "Sources/Resources/en.lproj/Localizable.strings"
check_matching_keys "Widget/zh-Hans.lproj/Localizable.strings" "Widget/en.lproj/Localizable.strings"
check_matching_keys "Sources/Resources/zh-Hans.lproj/InfoPlist.strings" "Sources/Resources/en.lproj/InfoPlist.strings"
check_matching_keys "Widget/zh-Hans.lproj/InfoPlist.strings" "Widget/en.lproj/InfoPlist.strings"

check_required_app_info_plist_keys "Sources/Resources/zh-Hans.lproj/InfoPlist.strings"
check_required_app_info_plist_keys "Sources/Resources/en.lproj/InfoPlist.strings"

for file in "${english_resource_files[@]}"; do
  check_english_resource_values "$file"
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

python3 -B scripts/localization/check_source_coverage.py
python3 -B scripts/localization/test_source_coverage.py

echo "[localization-integrity] PASS: localized resources cover source keys and matching formats."
