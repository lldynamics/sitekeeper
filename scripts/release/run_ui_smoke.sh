#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DEVICE_FAMILY="${DEVICE_FAMILY:-iphone}"
SIM_ID="${SIM_ID:-}"
SIM_RUNTIME="${SIM_RUNTIME:-}"
SIM_DEVICE_TYPE="${SIM_DEVICE_TYPE:-}"
DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED_DATA_PATH_INPUT="${DERIVED_DATA_PATH:-}"
RESULT_BUNDLE_PATH_INPUT="${RESULT_BUNDLE_PATH:-}"
SIM_BOOT_TIMEOUT_SECONDS="${SIM_BOOT_TIMEOUT_SECONDS:-120}"
UI_TEST_TIMEOUT_SECONDS="${UI_TEST_TIMEOUT_SECONDS:-2400}"
MIN_FREE_SPACE_KB="${MIN_FREE_SPACE_KB:-5242880}"
MIN_SIMULATOR_FREE_SPACE_KB="${MIN_SIMULATOR_FREE_SPACE_KB:-2097152}"
DERIVED_DATA_IS_MANAGED=0
CREATED_SIM_ID=""

usage() {
  cat <<'EOF'
Usage: scripts/release/run_ui_smoke.sh [--device-family iphone|ipad]

Creates an isolated simulator when SIM_ID is not supplied, then runs the
release UI smoke set. RESULT_BUNDLE_PATH can be set for CI artifact upload.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-family)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --device-family requires iphone or ipad." >&2; exit 2; }
      DEVICE_FAMILY="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$DEVICE_FAMILY" in
  iphone | ipad) ;;
  *) echo "ERROR: DEVICE_FAMILY must be iphone or ipad." >&2; exit 2 ;;
esac

if [[ -n "$DERIVED_DATA_PATH_INPUT" ]]; then
  DERIVED_DATA_PATH="$DERIVED_DATA_PATH_INPUT"
else
  RUN_ID="${PPID}-$(date +%s)"
  DERIVED_DATA_PATH="$ROOT_DIR/.DerivedDataUISmoke_${DEVICE_FAMILY}_${RUN_ID}"
  DERIVED_DATA_IS_MANAGED=1
fi
if [[ -n "$RESULT_BUNDLE_PATH_INPUT" ]]; then
  RESULT_BUNDLE_PATH="$RESULT_BUNDLE_PATH_INPUT"
else
  RUN_ID="${RUN_ID:-${PPID}-$(date +%s)}"
  RESULT_BUNDLE_PATH="$ROOT_DIR/build/UI-Smoke/sitekeeper-ui-smoke-${DEVICE_FAMILY}-${RUN_ID}.xcresult"
fi

mkdir -p "$DERIVED_DATA_PATH" "$(dirname "$RESULT_BUNDLE_PATH")"
AVAILABLE_SPACE_KB="$(df -Pk "$DERIVED_DATA_PATH" | awk 'NR == 2 {print $4}')"
if [[ -z "$AVAILABLE_SPACE_KB" || "$AVAILABLE_SPACE_KB" -lt "$MIN_FREE_SPACE_KB" ]]; then
  echo "ERROR: UI smoke build volume needs at least $((MIN_FREE_SPACE_KB / 1024 / 1024)) GiB free." >&2
  echo "Set DERIVED_DATA_PATH to a volume with more free space." >&2
  exit 4
fi
if [[ -e "$RESULT_BUNDLE_PATH" ]]; then
  echo "ERROR: RESULT_BUNDLE_PATH already exists: $RESULT_BUNDLE_PATH" >&2
  exit 4
fi

SIMULATOR_DATA_ROOT="${HOME}/Library/Developer/CoreSimulator"
mkdir -p "$SIMULATOR_DATA_ROOT"
SIMULATOR_SPACE_KB="$(df -Pk "$SIMULATOR_DATA_ROOT" | awk 'NR == 2 {print $4}')"
if [[ -z "$SIMULATOR_SPACE_KB" || "$SIMULATOR_SPACE_KB" -lt "$MIN_SIMULATOR_FREE_SPACE_KB" ]]; then
  echo "ERROR: The system volume needs at least $((MIN_SIMULATOR_FREE_SPACE_KB / 1024 / 1024)) GiB free to install the UI test runner." >&2
  echo "Free system disk space before running simulator UI tests." >&2
  exit 4
fi

for tool in xcodebuild xcodegen xcrun python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: Missing required tool: $tool" >&2; exit 127; }
done

simctl() {
  DEVELOPER_DIR="$DEVELOPER_DIR_PATH" xcrun simctl "$@"
}

cleanup() {
  if [[ -n "$CREATED_SIM_ID" ]]; then
    simctl shutdown "$CREATED_SIM_ID" >/dev/null 2>&1 || true
    simctl delete "$CREATED_SIM_ID" >/dev/null 2>&1 || true
  fi
  if [[ "$DERIVED_DATA_IS_MANAGED" -eq 1 ]]; then
    rm -rf "$DERIVED_DATA_PATH"
  fi
}
trap cleanup EXIT

latest_available_ios_runtime() {
  if [[ -n "$SIM_RUNTIME" ]]; then
    printf '%s\n' "$SIM_RUNTIME"
    return
  fi
  simctl list runtimes available 2>/dev/null | awk '/^iOS / {runtime=$NF} END {if (runtime) print runtime}'
}

candidate_device_types() {
  if [[ -n "$SIM_DEVICE_TYPE" ]]; then
    printf '%s\n' "$SIM_DEVICE_TYPE"
    return
  fi

  local pattern
  local -a preferred
  if [[ "$DEVICE_FAMILY" == "ipad" ]]; then
    pattern='iPad'
    preferred=(
      com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4
      com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M4
      com.apple.CoreSimulator.SimDeviceType.iPad-Air-13-inch-M3
      com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3
    )
  else
    pattern='iPhone'
    preferred=(
      com.apple.CoreSimulator.SimDeviceType.iPhone-17
      com.apple.CoreSimulator.SimDeviceType.iPhone-16
      com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro
      com.apple.CoreSimulator.SimDeviceType.iPhone-15
    )
  fi

  {
    local device_type
    for device_type in "${preferred[@]}"; do
      if simctl list devicetypes 2>/dev/null | grep -Fq "(${device_type})"; then
        printf '%s\n' "$device_type"
      fi
    done
    simctl list devicetypes 2>/dev/null | awk -F '[()]' -v pattern="$pattern" '$0 ~ pattern {print $2}'
  } | awk 'NF && !seen[$0]++'
}

if [[ -z "$SIM_ID" ]]; then
  runtime="$(latest_available_ios_runtime)"
  [[ -n "$runtime" ]] || { echo "ERROR: No available iOS runtime was found." >&2; exit 3; }

  while IFS= read -r device_type; do
    [[ -n "$device_type" ]] || continue
    simulator_name="sitekeeper-ui-smoke-${DEVICE_FAMILY}-${PPID}"
    if CREATED_SIM_ID="$(simctl create "$simulator_name" "$device_type" "$runtime" 2>/dev/null)"; then
      SIM_ID="$CREATED_SIM_ID"
      break
    fi
  done < <(candidate_device_types)
  [[ -n "$SIM_ID" ]] || { echo "ERROR: Unable to create a ${DEVICE_FAMILY} simulator." >&2; exit 3; }
fi

echo "==> Booting ${DEVICE_FAMILY} simulator: $SIM_ID"
simctl boot "$SIM_ID" >/dev/null 2>&1 || true
perl -e 'alarm shift; exec @ARGV' "$SIM_BOOT_TIMEOUT_SECONDS" \
  env DEVELOPER_DIR="$DEVELOPER_DIR_PATH" xcrun simctl bootstatus "$SIM_ID" -b

echo "==> Regenerating Xcode project"
xcodegen generate

TESTS=(
  "sitekeeperUITests/SitekeeperUITests/testColdLaunchShowsPrimaryTabs"
  "sitekeeperUITests/SitekeeperUITests/testBackupScreenShowsImportAndExportActions"
  "sitekeeperUITests/SitekeeperUITests/testLocalBackupRoundTripRestoresClearedProjectAfterRestart"
  "sitekeeperUITests/SitekeeperUITests/testSwitchingFromSettingsToToolboxRefreshesDetail"
  "sitekeeperUITests/SitekeeperUITests/testCreatedProjectSurvivesRestart"
  "sitekeeperUITests/SitekeeperUITests/testCreatedDailyLogSurvivesRestart"
  "sitekeeperUITests/SitekeeperUITests/testCustomLaborTypesRemainEditableAfterHistoryAndRestart"
  "sitekeeperUITests/SitekeeperUITests/testAccessibilityAXXXLCoreFlowsRemainOperable"
  "sitekeeperUITests/SitekeeperUITests/testEnglishLaborEntryUsesTranslatedLabels"
  "sitekeeperUITests/SitekeeperUITests/testProjectKeyboardToolbarNavigatesFieldsAndSurvivesRotation"
  "sitekeeperUITests/SitekeeperUITests/testCalculatorKeyboardDoneDismissesAndAllowsFurtherInput"
  "sitekeeperUITests/SitekeeperUITests/testQuickNoteKeyboardDonePreservesDraft"
  "sitekeeperUITests/SitekeeperUITests/testLaborSheetKeyboardToolbarStaysWithinTheForm"
  "sitekeeperUITests/SitekeeperUITests/testFileSearchOpensFileOnlyMatchAndKeepsIPadSelectionAfterRotation"
  "sitekeeperUITests/SitekeeperUITests/testQuickNotePDFPreviewSupportsSearchCloseAndReopen"
  "sitekeeperUITests/SitekeeperUITests/testCorruptPDFShowsFailureAndAnotherAttachmentStillOpens"
  "sitekeeperUITests/SitekeeperUITests/testQuotationKeyboardNavigationUsesVisibleFieldsForBothPriceModes"
  "sitekeeperUITests/SitekeeperUITests/testMaterialLibraryRejectsZeroQuantityForSingleAndBatchAppend"
)
if [[ "$DEVICE_FAMILY" == "ipad" ]]; then
  TESTS+=("sitekeeperUITests/SitekeeperUITests/testIPadOnboardingProjectComposerDoesNotReopenAfterModuleSwitch")
fi
ONLY_TESTING_ARGS=()
for test_name in "${TESTS[@]}"; do
  ONLY_TESTING_ARGS+=("-only-testing:${test_name}")
done

echo "==> Running ${DEVICE_FAMILY} release UI smoke tests"
perl -e 'alarm shift; exec @ARGV' "$UI_TEST_TIMEOUT_SECONDS" \
  env DEVELOPER_DIR="$DEVELOPER_DIR_PATH" xcodebuild \
    -quiet \
    -project sitekeeper.xcodeproj \
    -scheme sitekeeper-iOS-UITests \
    -destination "platform=iOS Simulator,id=${SIM_ID}" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -resultBundlePath "$RESULT_BUNDLE_PATH" \
    -parallel-testing-enabled NO \
    CODE_SIGNING_ALLOWED=NO \
    "${ONLY_TESTING_ARGS[@]}" \
    test

echo "==> Checking UI test results and runtime warnings"
env DEVELOPER_DIR="$DEVELOPER_DIR_PATH" python3 scripts/release/check_ui_test_results.py \
  --result-bundle "$RESULT_BUNDLE_PATH"

echo "UI smoke tests passed for ${DEVICE_FAMILY}."
echo "Result bundle: $RESULT_BUNDLE_PATH"
