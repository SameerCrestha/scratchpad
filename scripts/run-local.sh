#!/usr/bin/env bash
# Rebuilds and restarts the app. A normal start opens the scratchpad under the menu bar icon.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
pkill -x Scratchpad 2>/dev/null || true
open build/Scratchpad.app
echo "Started. Logs: /usr/bin/log stream --level info --predicate 'subsystem == \"io.github.sameercrestha.scratchpad\"'"
