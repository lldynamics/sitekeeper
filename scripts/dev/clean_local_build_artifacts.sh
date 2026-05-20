#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: scripts/dev/clean_local_build_artifacts.sh [--dry-run]

Removes local Xcode derived outputs that are ignored by git:
  - build/DerivedData-*
  - DerivedData
  - .DerivedData*
  - build/*.xcresult

It intentionally avoids deleting build/release because it may contain generated
deliverables.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

targets=()

if [[ -d "$ROOT_DIR/build" ]]; then
  while IFS= read -r -d '' path; do
    targets+=("$path")
  done < <(find "$ROOT_DIR/build" -maxdepth 1 -type d -name 'DerivedData-*' -print0)

  while IFS= read -r -d '' path; do
    targets+=("$path")
  done < <(find "$ROOT_DIR/build" -maxdepth 1 -type d -name '*.xcresult' -print0)
fi

while IFS= read -r -d '' path; do
  targets+=("$path")
done < <(find "$ROOT_DIR" -maxdepth 1 -type d \( -name 'DerivedData' -o -name '.DerivedData*' \) -print0)

ignored_targets=()
if [[ ${#targets[@]} -gt 0 ]]; then
  for path in "${targets[@]}"; do
    case "$path" in
      "$ROOT_DIR"/*) ;;
      *)
        echo "Refusing to clean path outside repo: $path" >&2
        exit 1
        ;;
    esac

    relative_path="${path#"$ROOT_DIR"/}"
    if git -C "$ROOT_DIR" check-ignore -q -- "$relative_path"; then
      ignored_targets+=("$path")
    else
      echo "Skipping non-ignored path: $relative_path" >&2
    fi
  done
fi

if [[ ${#ignored_targets[@]} -eq 0 ]]; then
  echo "No local build artifacts to clean."
  exit 0
fi

echo "Local build artifacts:"
du -sh "${ignored_targets[@]}" 2>/dev/null || true

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run only. No files were removed."
  exit 0
fi

rm -rf "${ignored_targets[@]}"
echo "Removed ${#ignored_targets[@]} local build artifact path(s)."
