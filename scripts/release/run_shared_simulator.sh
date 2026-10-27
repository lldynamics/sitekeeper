#!/usr/bin/env bash
set -euo pipefail

# Keep validation under the host's shared simulator lock. This entry point
# never creates, erases, boots, or shuts down a simulator itself.
exec /usr/bin/python3 /Users/developer/.codex/bin/simulator-session.py -- "$@"
