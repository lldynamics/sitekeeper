#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

ALLOW_DIRTY=0
RUN_PREFLIGHT_TESTS=0

SIM_ID="${SIM_ID:-}"
SIM_DEVICE_TYPE="${SIM_DEVICE_TYPE:-}"
SIM_RUNTIME="${SIM_RUNTIME:-}"
SIMULATOR_NAME="${SIMULATOR_NAME:-sitekeeper-preflight}"
SIM_BOOT_TIMEOUT_SECONDS="${SIM_BOOT_TIMEOUT_SECONDS:-120}"
SIMULATOR_BUILD_TIMEOUT_SECONDS="${SIMULATOR_BUILD_TIMEOUT_SECONDS:-1800}"
UNIT_TEST_TIMEOUT_SECONDS="${UNIT_TEST_TIMEOUT_SECONDS:-2400}"
RESET_SIMULATOR_BEFORE_TESTS="${RESET_SIMULATOR_BEFORE_TESTS:-}"

DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.DerivedDataRelease_one_click_${PPID}_$(date +%s)}"
RESOLVED_SIM_ID=""
TEMP_SIM_ID=""

if [[ -z "$RESET_SIMULATOR_BEFORE_TESTS" ]]; then
  RESET_SIMULATOR_BEFORE_TESTS=1
  [[ -n "$SIM_ID" ]] && RESET_SIMULATOR_BEFORE_TESTS=0
fi

usage() {
  cat <<'EOF'
Usage: scripts/release/one_click_release_check.sh [--allow-dirty] [--run-preflight-tests]

Runs one-click release checks in fixed order:
  1) XcodeGen
  2) SwiftFormat (lint mode)
  3) SwiftLint
  4) Generic iOS build
  5) Simulator build-for-testing
  6) Unit tests (test-without-building)
  7) Release preflight
  8) Untracked Swift file check

Flags:
  --allow-dirty          Allow running with a dirty worktree.
  --run-preflight-tests  Let preflight run its own test phase (default skips tests there).
EOF
}

for arg in "$@"; do
  case "$arg" in
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --run-preflight-tests) RUN_PREFLIGHT_TESTS=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

check_junk_files() {
  local junk_files
  junk_files="$({
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
  } | sort -u)"
  if [[ -n "$junk_files" ]]; then
    echo "ERROR: Found AppleDouble or .DS_Store files. Remove junk files before release." >&2
    printf '%s\n' "$junk_files" | sed 's/^/  /' >&2
    exit 6
  fi
}

remove_generated_project_metadata() {
  # On external volumes, XcodeGen can recreate Finder sidecar metadata inside
  # the generated project bundle. The full repository check above has already
  # rejected pre-existing source metadata; only clean this disposable output.
  find sitekeeper.xcodeproj -type f \( -name '.DS_Store' -o -name '._*' \) -delete
  find . -maxdepth 1 -type f -name '._sitekeeper.xcodeproj' -delete
}

echo "==> Checking junk files"
check_junk_files

simctl() {
  DEVELOPER_DIR="$DEVELOPER_DIR_PATH" xcrun simctl "$@"
}

check_tool() {
  local tool_name="$1"
  if ! command -v "$tool_name" >/dev/null 2>&1; then
    echo "ERROR: Missing required tool: $tool_name" >&2
    exit 127
  fi
}

collect_untracked_swift_files() {
  git -c core.quotePath=false ls-files --others --exclude-standard -- '*.swift'
}

check_untracked_swift_files() {
  local phase="$1"
  local untracked_files
  untracked_files="$(collect_untracked_swift_files)"
  if [[ -n "$untracked_files" ]]; then
    echo "ERROR: Found untracked Swift files during ${phase}." >&2
    printf '%s\n' "$untracked_files" | sed -n '1,80p' | sed 's/^/  /' >&2
    local count
    count="$(printf '%s\n' "$untracked_files" | wc -l | tr -d ' ')"
    if [[ "$count" -gt 80 ]]; then
      echo "  ... and $((count - 80)) more" >&2
    fi
    exit 7
  fi
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
  echo "==> Cleaning DerivedData path: $resolved_path"
  rm -rf "$resolved_path"
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
  timeout_marker="$(mktemp "/tmp/sitekeeper-one-click-timeout.XXXXXX")"

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

  local timed_out=0
  if [[ -s "$timeout_marker" ]]; then
    timed_out=1
  fi
  rm -f "$timeout_marker"

  if [[ "$timed_out" -eq 1 ]]; then
    return 124
  fi
  return "$status"
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

create_named_simulator() {
  local runtime
  runtime="$(latest_available_ios_runtime)"
  [[ -n "$runtime" ]] || return 1

  local device_type
  local created_id
  while IFS= read -r device_type; do
    [[ -n "$device_type" ]] || continue
    if ! created_id="$(simctl create "$SIMULATOR_NAME" "$device_type" "$runtime" 2>/dev/null)"; then
      echo "WARN: Failed to create simulator with $device_type on $runtime." >&2
      continue
    fi
    TEMP_SIM_ID="$created_id"
    if validate_simulator_id "$created_id"; then
      RESOLVED_SIM_ID="$created_id"
      echo "==> Created simulator: $SIMULATOR_NAME ($created_id)"
      return 0
    fi
    simctl shutdown "$created_id" >/dev/null 2>&1 || true
    simctl delete "$created_id" >/dev/null 2>&1 || true
    TEMP_SIM_ID=""
  done < <(candidate_iphone_device_types)

  return 1
}

resolve_simulator_id() {
  if [[ -n "$SIM_ID" ]]; then
    validate_simulator_id "$SIM_ID"
    RESOLVED_SIM_ID="$SIM_ID"
    return 0
  fi

  local named_id
  named_id="$(find_existing_named_simulator_id "$SIMULATOR_NAME" || true)"
  if [[ -n "$named_id" ]]; then
    if validate_simulator_id "$named_id"; then
      RESOLVED_SIM_ID="$named_id"
      return 0
    fi
    simctl shutdown "$named_id" >/dev/null 2>&1 || true
    simctl delete "$named_id" >/dev/null 2>&1 || true
  fi

  create_named_simulator
}

cleanup_temp_simulator() {
  if [[ -n "$TEMP_SIM_ID" ]]; then
    simctl shutdown "$TEMP_SIM_ID" >/dev/null 2>&1 || true
    simctl delete "$TEMP_SIM_ID" >/dev/null 2>&1 || true
  fi
}
trap cleanup_temp_simulator EXIT

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

run_preflight() {
  local args=()
  if [[ "$ALLOW_DIRTY" -eq 1 ]]; then
    args+=(--allow-dirty)
  fi
  if [[ "$RUN_PREFLIGHT_TESTS" -eq 0 ]]; then
    args+=(--skip-tests)
  fi

  echo "==> Step 7/8: preflight (${args[*]:-no extra args})"
  remove_generated_project_metadata
  DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
  DERIVED_DATA_PATH="$DERIVED_DATA_PATH" \
  scripts/release/preflight.sh "${args[@]}"
}

echo "==> One-click release check started"

check_tool xcodegen
check_tool swiftformat
check_tool swiftlint
check_tool xcodebuild

if [[ "$ALLOW_DIRTY" -ne 1 ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: Working tree is dirty. Commit or stash changes, or pass --allow-dirty." >&2
    git status --short | sed -n '1,80p' >&2
    exit 2
  fi
fi

echo "==> Step 1/8: xcodegen generate"
before_project_status="$(git -c core.quotePath=false status --porcelain -- project.yml sitekeeper.xcodeproj)"
xcodegen generate
remove_generated_project_metadata
after_project_status="$(git -c core.quotePath=false status --porcelain -- project.yml sitekeeper.xcodeproj)"
if [[ "$before_project_status" != "$after_project_status" ]]; then
  echo "ERROR: xcodegen changed project files. Commit regenerated project before release." >&2
  git -c core.quotePath=false status --short -- project.yml sitekeeper.xcodeproj >&2
  git -c core.quotePath=false --no-pager diff -- sitekeeper.xcodeproj/project.pbxproj >&2
  exit 4
fi

echo "==> Step 2/8: SwiftFormat lint"
scripts/dev/check_swift_format.sh Sources Widget Tests UITests

echo "==> Step 3/8: SwiftLint"
scripts/dev/check_swift_lint.sh Sources Widget Tests UITests

prepare_derived_data

echo "==> Step 4/8: generic iOS build"
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
xcodebuild \
  -quiet \
  -project sitekeeper.xcodeproj \
  -scheme sitekeeper-iOS \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  -configuration Debug \
  build

echo "==> Step 5/8: simulator build-for-testing"
resolve_simulator_id || {
  echo "ERROR: No bootable iPhone simulator found. Set SIM_ID or install iOS simulator runtime." >&2
  exit 5
}
echo "==> Using simulator: $RESOLVED_SIM_ID (name: $SIMULATOR_NAME)"
reset_simulator_state "$RESOLVED_SIM_ID"

SIMULATOR_CMD=(
  xcodebuild
  -quiet
  -project sitekeeper.xcodeproj
  -scheme sitekeeper-iOS
  -destination "platform=iOS Simulator,id=${RESOLVED_SIM_ID}"
  -derivedDataPath "$DERIVED_DATA_PATH"
  CODE_SIGNING_ALLOWED=NO
)

run_xcodebuild_with_timeout \
  "$SIMULATOR_BUILD_TIMEOUT_SECONDS" \
  "simulator build-for-testing (sitekeeper-iOS)" \
  env DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${SIMULATOR_CMD[@]}" build-for-testing
remove_derived_data_metadata

echo "==> Step 6/8: unit test"
run_xcodebuild_with_timeout \
  "$UNIT_TEST_TIMEOUT_SECONDS" \
  "unit test (sitekeeper-iOS)" \
  env DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${SIMULATOR_CMD[@]}" test-without-building

run_preflight

echo "==> Step 8/8: check untracked Swift files"
check_untracked_swift_files "final gate"

echo "==> One-click release check passed"
