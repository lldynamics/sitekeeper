#!/usr/bin/env bash
# Unicode Han properties are not POSIX ERE; use macOS's Perl for this narrow fallback.
localization_search() {
  local pattern="$1"
  shift
  if [[ "${SITEKEEPER_SEARCH_BACKEND:-auto}" != grep ]] && command -v rg >/dev/null 2>&1; then
    local status
    if rg -n --with-filename "$pattern" "$@"; then return 0; else status=$?; fi
    if [[ "$status" -gt 1 ]]; then echo '[localization-search] rg failed'; fi
    return "$status"
  fi
  local perl_status
  if perl "$LOCALIZATION_SEARCH_LIB_DIR/search_unicode.pl" "$pattern" "$@"; then return 0; else perl_status=$?; fi
  if [[ "$perl_status" -gt 1 ]]; then echo '[localization-search] Perl failed'; fi
  return "$perl_status"
}
LOCALIZATION_SEARCH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
