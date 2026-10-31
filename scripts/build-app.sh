#!/usr/bin/env bash
# Builds build/Scratchpad.app.
#   VERSION=1.2.3          set the app version (default: the one in Resources/Info.plist)
#   ARCHS="arm64 x86_64"   universal build (needs full Xcode; default: this Mac's arch)
#   SIGNING_P12=path       .p12 with the "Scratchpad Signing" identity (default: ~/.config/scratchpad/signing.p12)
#   SIGNING_P12_PASSWORD   its password (default: ~/.config/scratchpad/signing.pass)
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=Scratchpad
APP="build/$APP_NAME.app"

arch_flags=()
for arch in ${ARCHS:-}; do arch_flags+=(--arch "$arch"); done

swift build -c release ${arch_flags[@]+"${arch_flags[@]}"}
bin_dir=$(swift build -c release ${arch_flags[@]+"${arch_flags[@]}"} --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$bin_dir/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi

# The same certificate on every build lets the app update itself: it only installs an update
# signed like itself. Without the certificate the build is ad-hoc signed and cannot update.
config="$HOME/.config/scratchpad"
p12="${SIGNING_P12:-$config/signing.p12}"
if [[ -f "$p12" ]]; then
  password="${SIGNING_P12_PASSWORD:-$(cat "$config/signing.pass")}"
  password=$(printf '%s' "$password" | tr -d '\r\n')
  # A throwaway keychain, so the login keychain is never touched. codesign only finds
  # identities in keychains on the search list, so it joins the list until the script ends.
  keychain="$(mktemp -d)/signing.keychain-db"
  keychain_password=$(uuidgen)
  original_keychains=$(security list-keychains -d user | tr -d '"')
  security create-keychain -p "$keychain_password" "$keychain"
  trap 'security list-keychains -d user -s $original_keychains; security delete-keychain "$keychain" 2>/dev/null || true' EXIT
  security list-keychains -d user -s "$keychain" $original_keychains
  security unlock-keychain -p "$keychain_password" "$keychain"
  security import "$p12" -k "$keychain" -P "$password" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
  security find-identity -p codesigning "$keychain" | grep -c "Scratchpad Signing" >/dev/null || {
    echo "The .p12 has no Scratchpad Signing identity (wrong file or password?)" >&2
    exit 1
  }
  codesign --force --options runtime --keychain "$keychain" --sign "Scratchpad Signing" "$APP"
else
  echo "No signing certificate, signing ad-hoc" >&2
  codesign --force --options runtime --sign - "$APP"
fi
echo "Built $APP"
