#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
expected="$(sed -n 's/.*xcodeVersion: "\([^"]*\)".*/\1/p' "$ROOT_DIR/project.yml")"
actual="$(xcodebuild -version | sed -n 's/^Xcode //p')"
if [[ -z "$expected" || "$actual" != "$expected" ]]; then
  echo "ERROR: expected Xcode $expected, found $actual; select the pinned toolchain with DEVELOPER_DIR." >&2
  exit 1
fi
xcodebuild -version
