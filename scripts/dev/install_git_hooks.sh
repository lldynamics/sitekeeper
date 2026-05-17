#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if ! command -v git >/dev/null 2>&1; then
  echo "[git-hooks] ERROR: git not found" >&2
  exit 1
fi

git config core.hooksPath .githooks
chmod +x "$ROOT_DIR/.githooks/pre-commit"

echo "[git-hooks] Installed core.hooksPath=.githooks"
echo "[git-hooks] Active pre-commit: $ROOT_DIR/.githooks/pre-commit"
