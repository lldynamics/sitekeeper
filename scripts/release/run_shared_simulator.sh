#!/usr/bin/env bash
set -euo pipefail

# Keep validation under the host's shared simulator lock. This entry point
# never creates, erases, boots, or shuts down a simulator itself.
coordinator="${SITEKEEPER_SIMULATOR_COORDINATOR:-${HOME}/.codex/bin/simulator-session.py}"
if [[ ! -f "$coordinator" ]]; then
  printf '%s\n' 'Set SITEKEEPER_SIMULATOR_COORDINATOR to the shared simulator coordinator on this host.' >&2
  exit 1
fi
exec /usr/bin/python3 "$coordinator" -- "$@"
