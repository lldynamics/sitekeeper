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
SIMULATOR_NAME="${SIMULATOR_NAME:-sitekeeper-preflight}"
RESET_SIMULATOR_BEFORE_TESTS="${RESET_SIMULATOR_BEFORE_TESTS:-}"
SIMULATOR_BUILD_TIMEOUT_SECONDS="${SIMULATOR_BUILD_TIMEOUT_SECONDS:-1800}"
UNIT_TEST_TIMEOUT_SECONDS="${UNIT_TEST_TIMEOUT_SECONDS:-2400}"
UI_TEST_TIMEOUT_SECONDS="${UI_TEST_TIMEOUT_SECONDS:-3000}"
PRE_CLEAN_DERIVED_DATA="${PRE_CLEAN_DERIVED_DATA:-1}"
RESOLVED_SIM_ID=""
TEMP_SIM_ID=""
DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.DerivedDataRelease_preflight_${PPID}_$(date +%s)}"

if [[ -z "$RESET_SIMULATOR_BEFORE_TESTS" ]]; then
  RESET_SIMULATOR_BEFORE_TESTS=1
  [[ -n "$SIM_ID" ]] && RESET_SIMULATOR_BEFORE_TESTS=0
fi

for arg in "$@"; do
  case "$arg" in
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    --keep-derived-data) PRE_CLEAN_DERIVED_DATA=0 ;;
    --no-reset-simulator) RESET_SIMULATOR_BEFORE_TESTS=0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

echo "==> Release preflight started"
echo "Project root: $ROOT_DIR"

remove_generated_project_metadata() {
  # sitekeeper.xcodeproj is regenerated from project.yml. On external volumes,
  # Xcode can add Finder sidecars while reading this disposable bundle; remove
  # only those generated sidecars, never source-tree metadata.
  find sitekeeper.xcodeproj -type f \( -name '.DS_Store' -o -name '._*' \) -delete
  find . -maxdepth 1 -type f -name '._sitekeeper.xcodeproj' -delete
}

remove_generated_project_metadata

echo "==> Checking junk files"
collect_junk_files() {
  {
    # Derived data and build directories can legitimately contain Finder
    # metadata on external volumes; they are not release inputs. Keep checking
    # the repository source and project files themselves.
    find . \
      -path './.git' -prune -o \
      -path './build' -prune -o \
      -path './.DerivedData*' -prune -o \
      -path './._.DerivedData*' -prune -o \
      -type f \( -name '.DS_Store' -o -name '._*' \) -print
    find .git -type f -name '._*' -print
    git -c core.quotePath=false ls-files --cached -- \
      ".DS_Store" \
      ":(glob)**/.DS_Store" \
      "._*" \
      ":(glob)**/._*"
  } | sort -u
}

JUNK_FILES="$(collect_junk_files)"
if [[ -n "$JUNK_FILES" ]]; then
  echo "ERROR: Found AppleDouble or .DS_Store files. Remove junk files before release." >&2
  printf '%s\n' "$JUNK_FILES" | sed 's/^/  /' >&2
  exit 6
fi

echo "==> Checking untracked Swift sources"
collect_untracked_swift_files() {
  git -c core.quotePath=false ls-files --others --exclude-standard -- '*.swift'
}

UNTRACKED_SWIFT_FILES="$(collect_untracked_swift_files)"
if [[ -n "$UNTRACKED_SWIFT_FILES" ]]; then
  sleep 1
  UNTRACKED_SWIFT_FILES="$(collect_untracked_swift_files)"
fi
if [[ -n "$UNTRACKED_SWIFT_FILES" ]]; then
  echo "ERROR: Found untracked Swift source files. Add, remove, or ignore them before release preflight." >&2
  printf '%s\n' "$UNTRACKED_SWIFT_FILES" | sed -n '1,80p' | sed 's/^/  /' >&2
  UNTRACKED_SWIFT_COUNT="$(printf '%s\n' "$UNTRACKED_SWIFT_FILES" | wc -l | tr -d ' ')"
  if [[ "$UNTRACKED_SWIFT_COUNT" -gt 80 ]]; then
    echo "  ... and $((UNTRACKED_SWIFT_COUNT - 80)) more" >&2
  fi
  exit 7
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
# In an explicitly allowed dirty worktree, preserve the caller's existing
# project-file status and only fail if this invocation of XcodeGen changes it.
before_project_status="$(git -c core.quotePath=false status --porcelain -- project.yml sitekeeper.xcodeproj)"
xcodegen generate
remove_generated_project_metadata
after_project_status="$(git -c core.quotePath=false status --porcelain -- project.yml sitekeeper.xcodeproj)"
if [[ "$before_project_status" != "$after_project_status" ]]; then
  echo "ERROR: xcodegen changed project files. Commit regenerated project before release." >&2
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

echo "==> Checking Dynamic Type font policy"
scripts/release/check_dynamic_type_policy.sh

echo "==> Checking UserDefaults direct access policy"
scripts/release/check_userdefaults_policy.sh

echo "==> Checking SwiftUI ForEach identity policy"
scripts/release/check_swiftui_identity_policy.sh

echo "==> Checking @unchecked Sendable policy"
scripts/release/check_unchecked_sendable_policy.sh

echo "==> Checking App Store archive configuration"
scripts/release/check_appstore_archive_config.sh

echo "==> Checking legal policy generated copies"
python3 scripts/legal/export_privacy_policy.py --check

BUILD_CMD=(
  xcodebuild
  -quiet
  -project sitekeeper.xcodeproj
  -scheme sitekeeper-iOS
  -destination "generic/platform=iOS"
  -derivedDataPath "$DERIVED_DATA_PATH"
  CODE_SIGNING_ALLOWED=NO
)

simctl() {
  DEVELOPER_DIR="$DEVELOPER_DIR_PATH" xcrun simctl "$@"
}

prepare_derived_data() {
  local resolved_path resolved_root
  resolved_path="$(python3 -c 'import os, sys; print(os.path.realpath(os.path.expanduser(sys.argv[1])))' "$DERIVED_DATA_PATH")"
  resolved_root="$(python3 -c 'import os, sys; print(os.path.realpath(os.path.expanduser(sys.argv[1])))' "$ROOT_DIR")"
  case "$resolved_path" in
    /tmp/*|/private/tmp/*|"$resolved_root"/.DerivedData*) ;;
    *)
      echo "ERROR: Refusing unsafe DerivedData path: $DERIVED_DATA_PATH. Use /tmp or $ROOT_DIR/.DerivedData*." >&2
      exit 2
      ;;
  esac
  if [[ "$PRE_CLEAN_DERIVED_DATA" -eq 1 ]]; then
    echo "==> Cleaning DerivedData path: $resolved_path"
    rm -rf "$resolved_path"
  fi
  DERIVED_DATA_PATH="$resolved_path"
  mkdir -p "$DERIVED_DATA_PATH"
}

remove_derived_data_metadata() {
  # External volumes can create AppleDouble sidecars for build products. A
  # simulator treats an .appex sidecar as a real extension and rejects install.
  find "$DERIVED_DATA_PATH" -type f \( -name '.DS_Store' -o -name '._*' \) -delete
}

terminate_process_tree() {
  local pid="$1"
  local signal="${2:-TERM}"
  local child_pid

  while IFS= read -r child_pid; do
    [[ -n "$child_pid" ]] || continue
    terminate_process_tree "$child_pid" "$signal"
  done < <(pgrep -P "$pid" 2>/dev/null || true)

  kill "-$signal" "$pid" >/dev/null 2>&1 || true
}

run_with_timeout() {
  local timeout_seconds="$1"
  local label="$2"
  shift 2

  local timeout_marker
  timeout_marker="$(mktemp "/tmp/sitekeeper-preflight-timeout.XXXXXX")"

  "$@" &
  local command_pid=$!
  (
    sleep "$timeout_seconds"
    if kill -0 "$command_pid" >/dev/null 2>&1; then
      echo "timed_out" >"$timeout_marker"
      echo "ERROR: ${label} timed out after ${timeout_seconds}s." >&2
      terminate_process_tree "$command_pid" TERM
      sleep 5
      terminate_process_tree "$command_pid" KILL
    fi
  ) &
  local timeout_pid=$!

  set +e
  wait "$command_pid"
  local status=$?
  set -e

  kill "$timeout_pid" >/dev/null 2>&1 || true
  wait "$timeout_pid" >/dev/null 2>&1 || true

  local did_timeout=0
  if [[ -s "$timeout_marker" ]]; then
    did_timeout=1
  fi
  rm -f "$timeout_marker"

  if [[ "$did_timeout" -eq 1 ]]; then
    return 124
  fi
  return "$status"
}

cleanup_temp_simulator() {
  if [[ -n "$TEMP_SIM_ID" ]]; then
    simctl shutdown "$TEMP_SIM_ID" >/dev/null 2>&1 || true
    simctl delete "$TEMP_SIM_ID" >/dev/null 2>&1 || true
  fi
}
trap cleanup_temp_simulator EXIT

find_existing_named_simulator_id() {
  local simulator_name="$1"
  simctl list devices available 2>/dev/null | awk -F '[()]' -v wanted_name="$simulator_name" '
    $1 ~ /^[[:space:]]/ {
      name = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      if (name == wanted_name && $2 ~ /^[0-9A-Fa-f-]+$/) {
        print $2
        exit
      }
    }
  '
}

simulator_bootstatus_ok() {
  local simulator_id="$1"
  run_with_timeout \
    "$SIM_BOOT_TIMEOUT_SECONDS" \
    "simulator bootstatus (${simulator_id})" \
    simctl bootstatus "$simulator_id" -b >/dev/null 2>&1
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
    local simulator_name="$SIMULATOR_NAME"
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

  local named_simulator_id=""
  named_simulator_id="$(find_existing_named_simulator_id "$SIMULATOR_NAME" || true)"
  if [[ -n "$named_simulator_id" ]]; then
    if validate_simulator_id "$named_simulator_id"; then
      RESOLVED_SIM_ID="$named_simulator_id"
      return 0
    fi
    echo "WARN: Existing named simulator is unusable, recreating: $SIMULATOR_NAME ($named_simulator_id)" >&2
    simctl shutdown "$named_simulator_id" >/dev/null 2>&1 || true
    simctl delete "$named_simulator_id" >/dev/null 2>&1 || true
  fi

  create_temp_simulator
}

reset_simulator_state() {
  local simulator_id="$1"
  if [[ "$RESET_SIMULATOR_BEFORE_TESTS" -ne 1 ]]; then
    return 0
  fi

  echo "==> Resetting simulator: $simulator_id"
  simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  simctl erase "$simulator_id" >/dev/null 2>&1 || true
  simctl boot "$simulator_id" >/dev/null 2>&1 || true
  simulator_bootstatus_ok "$simulator_id"
}

run_xcodebuild_with_timeout() {
  local timeout_seconds="$1"
  local label="$2"
  shift 2

  set +e
  run_with_timeout "$timeout_seconds" "$label" "$@"
  local status=$?
  set -e

  if [[ "$status" -eq 124 ]]; then
    echo "ERROR: ${label} timed out." >&2
  fi
  return "$status"
}

prepare_derived_data

echo "==> Debug build"
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${BUILD_CMD[@]}" -configuration Debug build

echo "==> Release build"
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${BUILD_CMD[@]}" -configuration Release build

if [[ "$SKIP_TESTS" -ne 1 ]]; then
  resolve_simulator_id || {
    echo "ERROR: No bootable iPhone simulator found. Set SIM_ID manually or install an iOS simulator runtime." >&2
    exit 5
  }
  echo "==> Using simulator: $RESOLVED_SIM_ID (name: $SIMULATOR_NAME)"
  reset_simulator_state "$RESOLVED_SIM_ID" || {
    echo "ERROR: Failed to reset simulator state for $RESOLVED_SIM_ID." >&2
    exit 5
  }

  SIMULATOR_UNIT_CMD=(
    xcodebuild
    -quiet
    -project sitekeeper.xcodeproj
    -scheme sitekeeper-iOS
    -destination "platform=iOS Simulator,id=${RESOLVED_SIM_ID}"
    -derivedDataPath "$DERIVED_DATA_PATH"
    CODE_SIGNING_ALLOWED=NO
  )

  SIMULATOR_UI_CMD=(
    xcodebuild
    -quiet
    -project sitekeeper.xcodeproj
    -scheme sitekeeper-iOS-UITests
    -destination "platform=iOS Simulator,id=${RESOLVED_SIM_ID}"
    -derivedDataPath "$DERIVED_DATA_PATH"
    CODE_SIGNING_ALLOWED=NO
  )

  echo "==> Simulator build-for-testing (unit test scheme gate)"
  run_xcodebuild_with_timeout \
    "$SIMULATOR_BUILD_TIMEOUT_SECONDS" \
    "simulator build-for-testing (sitekeeper-iOS)" \
    env DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${SIMULATOR_UNIT_CMD[@]}" build-for-testing
  remove_derived_data_metadata

  echo "==> Unit tests"
  run_xcodebuild_with_timeout \
    "$UNIT_TEST_TIMEOUT_SECONDS" \
    "unit tests (sitekeeper-iOS)" \
    env DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${SIMULATOR_UNIT_CMD[@]}" test-without-building

  echo "==> Simulator build-for-testing (UI test scheme gate)"
  run_xcodebuild_with_timeout \
    "$SIMULATOR_BUILD_TIMEOUT_SECONDS" \
    "simulator build-for-testing (sitekeeper-iOS-UITests)" \
    env DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${SIMULATOR_UI_CMD[@]}" build-for-testing
  remove_derived_data_metadata

  echo "==> UI tests"
  run_xcodebuild_with_timeout \
    "$UI_TEST_TIMEOUT_SECONDS" \
    "ui tests (sitekeeper-iOS-UITests)" \
    env DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${SIMULATOR_UI_CMD[@]}" test-without-building
fi

remove_generated_project_metadata

echo "==> Release preflight passed"
