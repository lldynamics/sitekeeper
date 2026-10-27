#!/usr/bin/env bash
# Shared search subset for release guards. All regexes use portable POSIX ERE.
# SITEKEEPER_SEARCH_BACKEND=grep also exercises the stock macOS fallback in CI.
policy_search() {
  local backend="${SITEKEEPER_SEARCH_BACKEND:-auto}"
  if [[ "$backend" != grep ]] && command -v rg >/dev/null 2>&1; then
    local rg_status
    if rg "$@"; then return 0; else rg_status=$?; fi
    if [[ "$rg_status" -gt 1 ]]; then echo '[policy-search] rg failed'; fi
    return "$rg_status"
  fi

  local glob='' explicit_pattern=0 arg path status listing matcher=-E
  local -a options=(-H) patterns=() roots=() files=()
  while [[ $# -gt 0 ]]; do
    arg="$1"
    shift
    case "$arg" in
      -n|-q) options+=("$arg") ;;
      --color=never) ;;
      --fixed-strings) matcher=-F ;;
      --glob) glob="$1"; shift ;;
      --regexp) patterns+=(-e "$1"); explicit_pattern=1; shift ;;
      -*) echo "[policy-search] unsupported option: $arg"; return 2 ;;
      *)
        if [[ "$explicit_pattern" == 0 ]]; then
          patterns+=(-e "$arg")
          explicit_pattern=1
        else
          roots+=("$arg")
        fi ;;
    esac
  done
  for path in "${roots[@]}"; do
    if [[ -f "$path" ]]; then
      files+=("$path")
    elif [[ -d "$path" ]]; then
      listing="$(mktemp "${TMPDIR:-/tmp}/sitekeeper-search.XXXXXX")" || { echo '[policy-search] cannot create file list'; return 2; }
      if ! find "$path" -type f -name "${glob:-*}" -print0 > "$listing"; then
        rm -f "$listing"
        echo "[policy-search] cannot enumerate: $path"
        return 2
      fi
      while IFS= read -r -d '' arg; do
        files+=("$arg")
      done < "$listing"
      rm -f "$listing"
    else
      echo "[policy-search] missing path: $path"
      return 2
    fi
  done
  if [[ ${#files[@]} -eq 0 || ${#patterns[@]} -eq 0 ]]; then
    echo '[policy-search] no files or pattern available'
    return 2
  fi
  if LC_ALL=C grep "$matcher" "${options[@]}" "${patterns[@]}" -- "${files[@]}"; then
    return 0
  else
    status=$?
    # Guards collect matches with `|| true`; emit a diagnostic on stdout so a
    # read/regex error is still a failing guard, never an apparent clean scan.
    if [[ "$status" -gt 1 ]]; then echo '[policy-search] grep failed'; fi
    return "$status"
  fi
}
