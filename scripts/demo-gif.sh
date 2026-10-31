#!/usr/bin/env bash
# Draws docs/demo.gif for the README (see scripts/demo-gif/main.swift). Nothing shows on screen.
#   scripts/demo-gif.sh [scale]   (default 1.5)
set -euo pipefail
cd "$(dirname "$0")/.."

sources=$(ls Sources/Scratchpad/*.swift | grep -v '/main.swift$')
mkdir -p build docs
swiftc -O -swift-version 5 $sources scripts/demo-gif/main.swift -o build/demo-gif \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Resources/Info.plist
build/demo-gif docs/demo.gif "${1:-1.5}"
