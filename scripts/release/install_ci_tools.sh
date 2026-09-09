#!/usr/bin/env bash
set -euo pipefail

# Keep local acceptance and CI on the same, reviewed tool versions.
# SHA-256 values are the official GitHub release asset digests.
tool_destination="${1:?Usage: install_ci_tools.sh DESTINATION [--ui]}"
tool_scope="${2:-all}"
[[ "$tool_scope" == all || "$tool_scope" == --ui ]] || exit 2
mkdir -p "$tool_destination"
tool_destination="$(cd "$tool_destination" && pwd)"
tool_stage="$(mktemp -d "${TMPDIR:-/tmp}/sitekeeper-ci-tools.XXXXXX")"
trap 'rm -rf "$tool_stage"' EXIT

install_release_tool() {
  local name="$1" repo="$2" version="$3" asset="$4" digest="$5" binary="$6"
  local archive="$tool_stage/$name.zip" unpacked="$tool_stage/$name"
  curl --fail --location --silent --show-error --retry 3 \
    "https://github.com/$repo/releases/download/$version/$asset" --output "$archive"
  printf '%s  %s\n' "$digest" "$archive" | shasum -a 256 --check --status
  mkdir -p "$unpacked"
  unzip -q "$archive" -d "$unpacked"
  install -m 755 "$unpacked/$binary" "$tool_destination/$name"
}

install_release_tool xcodegen yonaskolb/XcodeGen 2.46.0 xcodegen.zip \
  4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806 xcodegen/bin/xcodegen
[[ "$("$tool_destination/xcodegen" --version)" == "Version: 2.46.0" ]]

if [[ "$tool_scope" == all ]]; then
  install_release_tool swiftformat nicklockwood/SwiftFormat 0.61.1 swiftformat.zip \
    b990400779aceb7d7020796eb9ba814d4480543f671d38fc0ff48cb72f04c584 swiftformat
  install_release_tool swiftlint realm/SwiftLint 0.63.2 portable_swiftlint.zip \
    c59a405c85f95b92ced677a500804e081596a4cae4a6a485af76065557d6ed29 swiftlint
  [[ "$("$tool_destination/swiftformat" --version)" == 0.61.1 ]]
  [[ "$("$tool_destination/swiftlint" version)" == 0.63.2 ]]
fi

echo "Verified release tools installed in $tool_destination"
