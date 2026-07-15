#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PROJECT="${PROJECT:-sitekeeper.xcodeproj}"
SCHEME="${SCHEME:-sitekeeper-iOS}"
CONFIGURATION="${CONFIGURATION:-Release}"
DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT_DIR/build/AppStore}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/sitekeeper-appstore-derived-data-${PPID}}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-Config/ExportOptions-AppStore.plist}"
TESTFLIGHT_EXPORT_OPTIONS_PLIST="${TESTFLIGHT_EXPORT_OPTIONS_PLIST:-Config/ExportOptions-TestFlight.plist}"

ALLOW_DIRTY=0
ALLOW_PROVISIONING_UPDATES=0
DRY_RUN=0
SKIP_PREFLIGHT=0
UPLOAD_TESTFLIGHT=0

usage() {
  cat <<'EOF'
Usage: scripts/release/archive_appstore.sh [options]

Creates a signed App Store archive, exports an IPA, verifies signing and writes
a release evidence file. TestFlight upload is opt-in and is never performed by
default.

Options:
  --dry-run                     Validate configuration and print the planned paths.
  --allow-dirty                 Allow a dirty worktree and record that fact in evidence.
  --skip-preflight              Skip the full release preflight before archiving.
  --allow-provisioning-updates  Allow Xcode to update signing assets.
  --upload-testflight           Upload the verified archive to TestFlight after IPA export.
  --output-root PATH            Override the artifact root (default: build/AppStore).
  -h, --help                    Show this help.

Optional App Store Connect API authentication environment:
  ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID

All three values must be provided together. TestFlight upload requires them.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --skip-preflight) SKIP_PREFLIGHT=1 ;;
    --allow-provisioning-updates) ALLOW_PROVISIONING_UPDATES=1 ;;
    --upload-testflight) UPLOAD_TESTFLIGHT=1 ;;
    --output-root)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --output-root requires a path." >&2; exit 2; }
      OUTPUT_ROOT="$1"
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

check_tool() {
  local tool_name="$1"
  command -v "$tool_name" >/dev/null 2>&1 || {
    echo "ERROR: Missing required tool: $tool_name" >&2
    exit 127
  }
}

project_setting() {
  local key="$1"
  sed -n "s/^[[:space:]]*${key}: \"\([^\"]*\)\"/\1/p" project.yml | head -n 1
}

print_command() {
  printf '  '
  printf '%q ' "$@"
  printf '\n'
}

for tool in xcodebuild xcodegen codesign plutil security shasum; do
  check_tool "$tool"
done

scripts/release/check_appstore_archive_config.sh

MARKETING_VERSION="$(project_setting MARKETING_VERSION)"
BUILD_NUMBER="$(project_setting CURRENT_PROJECT_VERSION)"
TEAM_ID="$(project_setting DEVELOPMENT_TEAM)"
if [[ -z "$MARKETING_VERSION" || -z "$BUILD_NUMBER" || -z "$TEAM_ID" ]]; then
  echo "ERROR: Version, build number, or development team is missing from project.yml." >&2
  exit 3
fi

if [[ "$ALLOW_DIRTY" -ne 1 && -n "$(git status --porcelain)" ]]; then
  echo "ERROR: Working tree is dirty. Commit changes or pass --allow-dirty." >&2
  git status --short | sed -n '1,80p' >&2
  exit 4
fi

AUTH_ARGS=()
AUTH_VALUE_COUNT=0
[[ -n "${ASC_KEY_PATH:-}" ]] && AUTH_VALUE_COUNT=$((AUTH_VALUE_COUNT + 1))
[[ -n "${ASC_KEY_ID:-}" ]] && AUTH_VALUE_COUNT=$((AUTH_VALUE_COUNT + 1))
[[ -n "${ASC_ISSUER_ID:-}" ]] && AUTH_VALUE_COUNT=$((AUTH_VALUE_COUNT + 1))
if [[ "$AUTH_VALUE_COUNT" -ne 0 && "$AUTH_VALUE_COUNT" -ne 3 ]]; then
  echo "ERROR: ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID must be supplied together." >&2
  exit 5
fi
if [[ "$AUTH_VALUE_COUNT" -eq 3 ]]; then
  [[ -f "$ASC_KEY_PATH" ]] || { echo "ERROR: ASC_KEY_PATH does not exist." >&2; exit 5; }
  AUTH_ARGS+=(
    -authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
  )
  ALLOW_PROVISIONING_UPDATES=1
fi

if [[ "$UPLOAD_TESTFLIGHT" -eq 1 && "$AUTH_VALUE_COUNT" -ne 3 ]]; then
  echo "ERROR: --upload-testflight requires App Store Connect API authentication." >&2
  exit 5
fi

if ! security find-identity -v -p codesigning 2>/dev/null | grep -Eq 'Apple Distribution|iPhone Distribution'; then
  echo "ERROR: No Apple Distribution signing identity is available in the keychain." >&2
  echo "Install a Team ${TEAM_ID} distribution identity before creating an App Store archive." >&2
  exit 6
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="$OUTPUT_ROOT/${MARKETING_VERSION}-${BUILD_NUMBER}-${TIMESTAMP}"
ARCHIVE_PATH="$ARTIFACT_DIR/sitekeeper.xcarchive"
EXPORT_PATH="$ARTIFACT_DIR/export"
UPLOAD_LOG_PATH="$ARTIFACT_DIR/testflight-upload"
RESULT_BUNDLE_PATH="$ARTIFACT_DIR/Archive.xcresult"
EVIDENCE_PATH="$ARTIFACT_DIR/release-evidence.txt"

PROVISIONING_ARGS=()
if [[ "$ALLOW_PROVISIONING_UPDATES" -eq 1 ]]; then
  PROVISIONING_ARGS+=(-allowProvisioningUpdates)
fi

ARCHIVE_CMD=(
  xcodebuild
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=iOS"
  -archivePath "$ARCHIVE_PATH"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -resultBundlePath "$RESULT_BUNDLE_PATH"
  DEVELOPMENT_TEAM="$TEAM_ID"
)

EXPORT_CMD=(
  xcodebuild
  -exportArchive
  -archivePath "$ARCHIVE_PATH"
  -exportPath "$EXPORT_PATH"
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
)

echo "==> App Store archive plan"
echo "Version: ${MARKETING_VERSION} (${BUILD_NUMBER})"
echo "Team: $TEAM_ID"
echo "Artifacts: $ARTIFACT_DIR"
echo "Archive command:"
print_command env DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${ARCHIVE_CMD[@]}" "${PROVISIONING_ARGS[@]}" "${AUTH_ARGS[@]}" archive
echo "Export command:"
print_command env DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "${EXPORT_CMD[@]}" "${PROVISIONING_ARGS[@]}" "${AUTH_ARGS[@]}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "App Store archive dry-run passed."
  exit 0
fi

mkdir -p "$ARTIFACT_DIR" "$EXPORT_PATH"

if [[ "$SKIP_PREFLIGHT" -ne 1 ]]; then
  PREFLIGHT_ARGS=()
  [[ "$ALLOW_DIRTY" -eq 1 ]] && PREFLIGHT_ARGS+=(--allow-dirty)
  echo "==> Running full release preflight"
  DEVELOPER_DIR="$DEVELOPER_DIR_PATH" scripts/release/preflight.sh "${PREFLIGHT_ARGS[@]}"
else
  echo "==> Regenerating Xcode project"
  xcodegen generate
fi

echo "==> Creating signed archive"
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
  "${ARCHIVE_CMD[@]}" \
  "${PROVISIONING_ARGS[@]}" \
  "${AUTH_ARGS[@]}" \
  archive

APP_PATH="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$APP_PATH" ]] || { echo "ERROR: Archived app bundle was not found." >&2; exit 7; }

echo "==> Verifying archived signing and privacy manifest"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
PRIVACY_MANIFEST="$(find "$APP_PATH" -type f -name 'PrivacyInfo.xcprivacy' -print -quit)"
[[ -n "$PRIVACY_MANIFEST" ]] || { echo "ERROR: PrivacyInfo.xcprivacy is missing from the archive." >&2; exit 8; }

ENTITLEMENTS_PATH="$ARTIFACT_DIR/archived-app-entitlements.plist"
codesign -d --entitlements :- "$APP_PATH" >"$ENTITLEMENTS_PATH" 2>/dev/null
plutil -lint "$ENTITLEMENTS_PATH" >/dev/null

echo "==> Exporting IPA"
DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
  "${EXPORT_CMD[@]}" \
  "${PROVISIONING_ARGS[@]}" \
  "${AUTH_ARGS[@]}"

IPA_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
[[ -n "$IPA_PATH" ]] || { echo "ERROR: IPA export did not produce an .ipa file." >&2; exit 9; }
IPA_SHA256="$(shasum -a 256 "$IPA_PATH" | awk '{print $1}')"
GIT_COMMIT="$(git rev-parse HEAD)"
WORKTREE_STATE="clean"
[[ -n "$(git status --porcelain)" ]] && WORKTREE_STATE="dirty-allowed"
APP_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Info.plist")"
APP_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Info.plist")"
APP_BUILD="$(plutil -extract CFBundleVersion raw -o - "$APP_PATH/Info.plist")"

TESTFLIGHT_STATUS="not-requested"
if [[ "$UPLOAD_TESTFLIGHT" -eq 1 ]]; then
  echo "==> Uploading verified archive to TestFlight"
  mkdir -p "$UPLOAD_LOG_PATH"
  DEVELOPER_DIR="$DEVELOPER_DIR_PATH" xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$UPLOAD_LOG_PATH" \
    -exportOptionsPlist "$TESTFLIGHT_EXPORT_OPTIONS_PLIST" \
    "${PROVISIONING_ARGS[@]}" \
    "${AUTH_ARGS[@]}"
  TESTFLIGHT_STATUS="submitted"
fi

{
  printf 'git_commit=%s\n' "$GIT_COMMIT"
  printf 'worktree=%s\n' "$WORKTREE_STATE"
  printf 'team_id=%s\n' "$TEAM_ID"
  printf 'bundle_id=%s\n' "$APP_BUNDLE_ID"
  printf 'version=%s\n' "$APP_VERSION"
  printf 'build=%s\n' "$APP_BUILD"
  printf 'archive=%s\n' "$ARCHIVE_PATH"
  printf 'ipa=%s\n' "$IPA_PATH"
  printf 'ipa_sha256=%s\n' "$IPA_SHA256"
  printf 'privacy_manifest=%s\n' "$PRIVACY_MANIFEST"
  printf 'testflight_upload=%s\n' "$TESTFLIGHT_STATUS"
} >"$EVIDENCE_PATH"

echo "App Store archive passed."
echo "IPA: $IPA_PATH"
echo "SHA-256: $IPA_SHA256"
echo "Evidence: $EVIDENCE_PATH"
