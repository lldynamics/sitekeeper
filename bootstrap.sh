#!/usr/bin/env bash
set -euo pipefail

NO_OPEN=0
if [[ "${1:-}" == "--no-open" ]]; then
  NO_OPEN=1
fi

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

# Check xcode-select
XPATH="$(xcode-select -p 2>/dev/null || true)"
if [[ "$XPATH" == *"CommandLineTools"* ]] || [[ -z "$XPATH" ]]; then
  echo ""
  echo "⚠️  Developer directory points to CommandLineTools."
  echo "   Run this ONCE before building:"
  echo ""
  echo "   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
  echo ""
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Installing via Homebrew..."
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "Homebrew not found. Install Homebrew first: https://brew.sh"
    exit 1
  fi
fi

echo "Generating Xcode project..."
xcodegen generate

if [[ "$NO_OPEN" -eq 1 ]]; then
  echo "Done. Skipping open step (--no-open)."
else
  echo "Done. Opening project..."
  open sitekeeper.xcodeproj
fi
