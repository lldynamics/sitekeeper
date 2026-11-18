#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

sim_id="${1:?Usage: run_backup_integration_tests.sh SIMULATOR_UDID RESULT_BUNDLE_PATH}"
result_bundle="${2:?Pass a new path for the backup integration .xcresult bundle.}"
if [[ -e "$result_bundle" ]]; then
  echo "ERROR: Result bundle already exists: $result_bundle" >&2
  exit 2
fi
mkdir -p "$(dirname "$result_bundle")"
result_bundle="$(cd "$(dirname "$result_bundle")" && pwd)/$(basename "$result_bundle")"

stage="$(mktemp -d "${TMPDIR:-/tmp}/sitekeeper-backup-integration.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
suffix="backup-$(basename "$stage" | awk -F . '{print tolower($NF)}')"

python3 -B scripts/tests/prepare_phase2_runtime_validation.py \
  --source "$root_dir" --output "$stage/source" --xcodegen "$(command -v xcodegen)" \
  --suffix "$suffix" --backup-integration-only

xcodebuild -quiet \
  -project "$stage/source/sitekeeper.xcodeproj" -scheme sitekeeper-iOS -configuration Debug \
  -destination "platform=iOS Simulator,id=$sim_id" -derivedDataPath "$stage/derived-data" \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  -resultBundlePath "$result_bundle" -only-testing:sitekeeperTests/BackupWorkflowIntegrationTests \
  CODE_SIGNING_ALLOWED=NO test

python3 -B - "$result_bundle" <<'PYTHON'
import sys

sys.path.insert(0, "scripts/release")
from check_ui_test_results import ResultValidationError, load_summary, validate_summary

try:
    summary = load_summary(sys.argv[1])
    validate_summary(summary)
    if summary["passedTests"] < 8:
        raise ResultValidationError("expected all backup integration cases to execute")
except ResultValidationError as error:
    sys.exit(f"Backup integration checks failed: {error}")
print(f"Backup integration checks passed: {summary['passedTests']} tests. Result: {sys.argv[1]}")
PYTHON
