#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

TEAM_ID="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM: "\([^"]*\)"/\1/p' project.yml | head -n 1)"
if [[ -z "$TEAM_ID" ]]; then
  echo "[appstore-archive-config] ERROR: DEVELOPMENT_TEAM is missing from project.yml." >&2
  exit 1
fi

python3 - \
  "$TEAM_ID" \
  Config/ExportOptions-AppStore.plist \
  Config/ExportOptions-TestFlight.plist <<'PY'
import plistlib
import sys
from pathlib import Path

team_id = sys.argv[1]
expectations = {
    Path(sys.argv[2]): "export",
    Path(sys.argv[3]): "upload",
}

for path, destination in expectations.items():
    try:
        with path.open("rb") as handle:
            values = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        raise SystemExit(f"[appstore-archive-config] ERROR: cannot read {path}: {error}")

    expected = {
        "method": "app-store-connect",
        "destination": destination,
        "signingStyle": "automatic",
        "teamID": team_id,
        "manageAppVersionAndBuildNumber": False,
        "stripSwiftSymbols": True,
        "uploadSymbols": True,
    }
    mismatches = [
        f"{key}={values.get(key)!r}, expected {value!r}"
        for key, value in expected.items()
        if values.get(key) != value
    ]
    if mismatches:
        joined = "; ".join(mismatches)
        raise SystemExit(f"[appstore-archive-config] ERROR: {path}: {joined}")
PY

bash -n scripts/release/archive_appstore.sh

echo "[appstore-archive-config] PASS: App Store export and TestFlight upload settings are aligned."
