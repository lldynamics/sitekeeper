#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK_PATH="${1:-"$ROOT_DIR/app/build/outputs/apk/debug/app-debug.apk"}"
PACKAGE_NAME="com.chengjinfang.sitekeeper"

sdk_dir_from_local_properties() {
  local local_properties="$ROOT_DIR/local.properties"
  if [[ -f "$local_properties" ]]; then
    awk -F= '/^sdk.dir=/ { print $2; exit }' "$local_properties"
  fi
}

find_adb() {
  local sdk_dir
  sdk_dir="$(sdk_dir_from_local_properties || true)"

  local candidates=(
    "${ANDROID_HOME:-}/platform-tools/adb"
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb"
    "${sdk_dir:-}/platform-tools/adb"
    "/opt/homebrew/share/android-commandlinetools/platform-tools/adb"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return 0
  fi

  return 1
}

if [[ ! -f "$APK_PATH" ]]; then
  echo "APK not found: $APK_PATH" >&2
  echo "Build it first: JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleDebug --no-daemon" >&2
  exit 1
fi

ADB="$(find_adb || true)"
if [[ -z "$ADB" ]]; then
  echo "adb not found. Install Android platform-tools or set ANDROID_HOME/ANDROID_SDK_ROOT." >&2
  exit 1
fi

echo "Using adb: $ADB"
"$ADB" start-server >/dev/null

ONLINE_DEVICE_TEXT="$("$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1 }')"
ONLINE_DEVICE_COUNT=0
DEVICE=""
if [[ -n "$ONLINE_DEVICE_TEXT" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    ONLINE_DEVICE_COUNT=$((ONLINE_DEVICE_COUNT + 1))
    if [[ -z "$DEVICE" ]]; then
      DEVICE="$line"
    fi
  done <<< "$ONLINE_DEVICE_TEXT"
fi

if [[ $ONLINE_DEVICE_COUNT -eq 0 ]]; then
  "$ADB" devices -l
  echo "No online Android device found. Connect a device with USB debugging enabled, then rerun this script." >&2
  exit 2
fi

if [[ -n "${ANDROID_SERIAL:-}" ]]; then
  DEVICE="$ANDROID_SERIAL"
elif [[ $ONLINE_DEVICE_COUNT -gt 1 ]]; then
  "$ADB" devices -l
  echo "Multiple devices found. Set ANDROID_SERIAL to choose one." >&2
  exit 2
fi

echo "Installing $APK_PATH on $DEVICE"
"$ADB" -s "$DEVICE" install -r "$APK_PATH"

echo "Launching $PACKAGE_NAME"
"$ADB" -s "$DEVICE" shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1 >/dev/null

echo "Installed and launched $PACKAGE_NAME on $DEVICE"
