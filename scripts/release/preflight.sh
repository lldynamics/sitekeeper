#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

ALLOW_DIRTY=0
SKIP_TESTS=0
SIM_ID="${SIM_ID:-}"
SIM_DEVICE_TYPE="${SIM_DEVICE_TYPE:-}"
SIM_RUNTIME="${SIM_RUNTIME:-}"
SIM_BOOT_TIMEOUT_SECONDS="${SIM_BOOT_TIMEOUT_SECONDS:-120}"
RESOLVED_SIM_ID=""
TEMP_SIM_ID=""
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

echo "==> Checking backup contract boundary"
scripts/release/check_backup_contract_boundary.sh

echo "==> Checking drawing release boundary"
scripts/release/check_drawing_release_boundary.sh

BUILD_CMD=(
  xcodebuild
  -project sitekeeper.xcodeproj
  -scheme sitekeeper-iOS
  -destination "generic/platform=iOS"
  CODE_SIGNING_ALLOWED=NO
)

simctl() {
  DEVELOPER_DIR="$DEVELOPER_DIR_PATH" xcrun simctl "$@"
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  "$@" &
  local command_pid=$!
  (
    sleep "$timeout_seconds"
    kill "$command_pid" >/dev/null 2>&1 || true
  ) &
  local timeout_pid=$!

  set +e
  wait "$command_pid"
  local status=$?
  set -e

  kill "$timeout_pid" >/dev/null 2>&1 || true
  wait "$timeout_pid" >/dev/null 2>&1 || true
  return "$status"
}

cleanup_temp_simulator() {
  if [[ -n "$TEMP_SIM_ID" ]]; then
    simctl shutdown "$TEMP_SIM_ID" >/dev/null 2>&1 || true
    simctl delete "$TEMP_SIM_ID" >/dev/null 2>&1 || true
  fi
}
trap cleanup_temp_simulator EXIT

list_candidate_simulator_ids() {
  {
    simctl list devices booted available 2>/dev/null | awk -F '[()]' '/iPhone/ && $2 ~ /^[0-9A-Fa-f-]+$/ {print $2}'
    simctl list devices available 2>/dev/null | awk -F '[()]' '/iPhone/ && $2 ~ /^[0-9A-Fa-f-]+$/ {print $2}'
  } | awk '!seen[$0]++'
}

simulator_bootstatus_ok() {
  local simulator_id="$1"
  run_with_timeout "$SIM_BOOT_TIMEOUT_SECONDS" simctl bootstatus "$simulator_id" -b >/dev/null 2>&1
}

validate_simulator_id() {
  local simulator_id="$1"

  simctl boot "$simulator_id" >/dev/null 2>&1 || true
  simulator_bootstatus_ok "$simulator_id"
}

latest_available_ios_runtime() {
  if [[ -n "$SIM_RUNTIME" ]]; then
    echo "$SIM_RUNTIME"
    return 0
  fi

  simctl list runtimes available 2>/dev/null | awk '/^iOS / {runtime=$NF} END {if (runtime) print runtime}'
}

candidate_iphone_device_types() {
  if [[ -n "$SIM_DEVICE_TYPE" ]]; then
    echo "$SIM_DEVICE_TYPE"
    return 0
  fi

  local preferred_types=(
    com.apple.CoreSimulator.SimDeviceType.iPhone-17
    com.apple.CoreSimulator.SimDeviceType.iPhone-16
    com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro
    com.apple.CoreSimulator.SimDeviceType.iPhone-15
    com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro
    com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation
  )
  local device_type
  {
    for device_type in "${preferred_types[@]}"; do
      if simctl list devicetypes 2>/dev/null | grep -Fq "(${device_type})"; then
        echo "$device_type"
      fi
    done
    simctl list devicetypes 2>/dev/null | awk -F '[()]' '/iPhone/ {print $2}'
  } | awk '!seen[$0]++'
}

create_temp_simulator() {
  local runtime
  runtime="$(latest_available_ios_runtime)"
  [[ -n "$runtime" ]] || return 1

  local device_type
  local created_id
  while IFS= read -r device_type; do
    [[ -n "$device_type" ]] || continue
    local simulator_name="sitekeeper-preflight-$(date +%Y%m%d%H%M%S)"
    if ! created_id="$(simctl create "$simulator_name" "$device_type" "$runtime" 2>/dev/null)"; then
      echo "WARN: Failed to create temporary simulator with $device_type on $runtime." >&2
      continue
    fi

    TEMP_SIM_ID="$created_id"
    if validate_simulator_id "$TEMP_SIM_ID"; then
      echo "==> Created temporary simulator: $TEMP_SIM_ID ($device_type, $runtime)" >&2
      RESOLVED_SIM_ID="$TEMP_SIM_ID"
      return 0
    fi

    echo "WARN: Temporary simulator failed bootstatus: $TEMP_SIM_ID" >&2
    cleanup_temp_simulator
    TEMP_SIM_ID=""
  done < <(candidate_iphone_device_types)

  return 1
}

resolve_simulator_id() {
  if [[ -n "$SIM_ID" ]]; then
    if validate_simulator_id "$SIM_ID"; then
      RESOLVED_SIM_ID="$SIM_ID"
      return 0
    fi
    echo "ERROR: SIM_ID was set but failed simulator bootstatus validation: $SIM_ID" >&2
    return 1
  fi

  local candidate_id
  while IFS= read -r candidate_id; do
    [[ -n "$candidate_id" ]] || continue
    if validate_simulator_id "$candidate_id"; then
      RESOLVED_SIM_ID="$candidate_id"
      return 0
    fi
    echo "WARN: Skipping unusable simulator: $candidate_id" >&2
  done < <(list_candidate_simulator_ids)

  create_temp_simulator
}

echo "==> Debug build"
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${BUILD_CMD[@]}" -configuration Debug build >/dev/null

echo "==> Release build"
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${BUILD_CMD[@]}" -configuration Release build >/dev/null

if [[ "$SKIP_TESTS" -ne 1 ]]; then
  resolve_simulator_id || {
    echo "ERROR: No bootable iPhone simulator found. Set SIM_ID manually or install an iOS simulator runtime." >&2
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
