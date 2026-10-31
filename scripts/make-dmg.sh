#!/usr/bin/env bash
# Packs build/Scratchpad.app into build/Scratchpad.dmg: a window with the app, an
# Applications shortcut and an arrow between them (layout in scripts/dmg-settings.py).
# The name has no version, so releases/latest/download/Scratchpad.dmg always gets the newest.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=Scratchpad
APP="build/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }

dmg="build/$APP_NAME.dmg"
bg_dir="build/dmg-background"

# dmgbuild writes the Finder window layout without driving Finder, so it also works in CI.
venv="build/.venv"
if [[ ! -x "$venv/bin/dmgbuild" ]]; then
  python3 -m venv "$venv"
  "$venv/bin/pip" install --quiet "dmgbuild==1.6.7"
fi

rm -rf "$bg_dir" "$dmg"
mkdir -p "$bg_dir"
swift scripts/dmg-background.swift "$bg_dir/background.png" 1
swift scripts/dmg-background.swift "$bg_dir/background@2x.png" 2

"$venv/bin/dmgbuild" -s scripts/dmg-settings.py \
  -D app="$APP" -D background="$bg_dir/background.png" \
  "$APP_NAME" "$dmg"
rm -rf "$bg_dir"
echo "Built $dmg"
