#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

ALLOW_DIRTY=0
SKIP_TESTS=0
SIM_ID="${SIM_ID:-}"
DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

for arg in "$@"; do
  case "$arg" in
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

echo "==> Release preflight started"
echo "Project root: $ROOT_DIR"

echo "==> Checking junk files"
if find "$ROOT_DIR" -name ".DS_Store" -print -quit | grep -q .; then
  echo "ERROR: Found .DS_Store in repository. Remove junk files before release." >&2
  find "$ROOT_DIR" -name ".DS_Store" -print >&2
  exit 6
fi

if [[ "$ALLOW_DIRTY" -ne 1 ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: Working tree is dirty. Commit or stash changes before release preflight." >&2
    git status --short | sed -n '1,80p' >&2
    exit 2
  fi
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "ERROR: xcodegen is required but not installed." >&2
  exit 3
fi

echo "==> Running xcodegen generate"
xcodegen generate

if ! git diff --quiet -- sitekeeper.xcodeproj project.yml; then
  echo "ERROR: xcodegen produced uncommitted project changes. Commit regenerated files before release." >&2
  git status --short -- project.yml sitekeeper.xcodeproj >&2
  exit 4
fi

echo "==> Checking file deletion policy"
scripts/release/check_file_deletion_policy.sh

echo "==> Checking DataStore write policy"
scripts/release/check_datastore_write_policy.sh

echo "==> Checking LibreDWG GPL compliance"
REQUIRE_LIBREDWG_RELEASE_COMPLIANCE=1 scripts/release/check_libredwg_gpl_compliance.sh

BUILD_CMD=(
  xcodebuild
  -project sitekeeper.xcodeproj
  -scheme sitekeeper-iOS
  -destination "generic/platform=iOS"
  CODE_SIGNING_ALLOWED=NO
)

resolve_simulator_id() {
  if [[ -n "$SIM_ID" ]]; then
    echo "$SIM_ID"
    return 0
  fi

  local booted_id
  booted_id="$(xcrun simctl list devices booted available 2>/dev/null | awk -F '[()]' '/iPhone/ {print $2; exit}')"
  if [[ -n "$booted_id" ]]; then
    echo "$booted_id"
    return 0
  fi

  local available_id
  available_id="$(xcrun simctl list devices available 2>/dev/null | awk -F '[()]' '/iPhone/ {print $2; exit}')"
  if [[ -n "$available_id" ]]; then
    echo "$available_id"
    return 0
  fi

  return 1
}

echo "==> Debug build"
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${BUILD_CMD[@]}" -configuration Debug build >/dev/null

echo "==> Release build"
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${BUILD_CMD[@]}" -configuration Release build >/dev/null

if [[ "$SKIP_TESTS" -ne 1 ]]; then
  RESOLVED_SIM_ID="$(resolve_simulator_id)" || {
    echo "ERROR: No available iPhone simulator found. Set SIM_ID manually." >&2
    exit 5
  }
  echo "==> Using simulator: $RESOLVED_SIM_ID"

  echo "==> Unit tests"
  DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
  xcodebuild \
    -project sitekeeper.xcodeproj \
    -scheme sitekeeper-iOS \
    -destination "platform=iOS Simulator,id=${RESOLVED_SIM_ID}" \
    CODE_SIGNING_ALLOWED=NO \
    test >/dev/null

  echo "==> UI tests"
  DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
  xcodebuild \
    -project sitekeeper.xcodeproj \
    -scheme sitekeeper-iOS-UITests \
    -destination "platform=iOS Simulator,id=${RESOLVED_SIM_ID}" \
    CODE_SIGNING_ALLOWED=NO \
    test >/dev/null
fi

echo "==> Release preflight passed"
