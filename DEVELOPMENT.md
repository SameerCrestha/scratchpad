# Developing Scratchpad

Notes for building, signing and releasing Scratchpad. To install it, see the [README](README.md).

## Build

Needs the Xcode Command Line Tools (`xcode-select --install`).

```sh
scripts/run-local.sh     # build, restart the app (a normal start opens the scratchpad)
scripts/build-app.sh     # build build/Scratchpad.app
scripts/make-dmg.sh      # pack it into build/Scratchpad.dmg
scripts/screenshot.sh    # take the README pictures into docs/ (flashes windows on screen)
swift scripts/app-icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

Logs:

```sh
/usr/bin/log stream --level info --predicate 'subsystem == "io.github.sameercrestha.scratchpad"'
```

## Signing

The updater only installs an update signed like the running app (same bundle ID, same certificate). So every build is signed with the same self-signed "Scratchpad Signing" certificate from `~/.config/scratchpad/signing.p12` (password in `signing.pass`). The build script uses a throwaway keychain, so the login keychain is not touched. Without the file it signs ad-hoc, and that build cannot update itself.

Keep the .p12 private. Anyone with it could sign an "update" that Scratchpad would install.

To create one:

```sh
mkdir -p ~/.config/scratchpad && cd ~/.config/scratchpad
printf '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=Scratchpad Signing\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' > cert.cnf
/usr/bin/openssl rand -hex 24 > signing.pass
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config cert.cnf -keyout key.pem -out cert.pem
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -name "Scratchpad Signing" -out signing.p12 -passout file:signing.pass
rm cert.cnf key.pem cert.pem && chmod 600 signing.*
```

## Release

Push a version tag. The workflow takes the version from the tag, so `Resources/Info.plist` needs no bump. GitHub Actions builds a universal app, signs it with the same certificate, and attaches the `.dmg` to a new release.

The workflow needs two repository secrets (Settings → Secrets and variables → Actions):

- `SIGNING_P12_BASE64`: output of `base64 -i ~/.config/scratchpad/signing.p12`
- `SIGNING_P12_PASSWORD`: contents of `~/.config/scratchpad/signing.pass`

```sh
git tag v0.1.0 && git push origin v0.1.0
```

## Updates

`Updater.swift` reads `releases/latest` from the GitHub API once a day. If the tag is newer than the app's version, it offers the release's `.dmg`. Installing mounts it, checks the new app meets the running app's designated requirement (same bundle ID, same certificate), swaps it in place and relaunches with `--updated`, which starts quietly.

- Release assets must be named `Scratchpad.dmg`. The README's download button links to `releases/latest/download/Scratchpad.dmg`.
- The repo's releases must be public. The API returns nothing for a private repo, so checks fail quietly.

## How it works

- **Menu bar icon**: an `NSStatusItem`. Left click toggles the scratchpad, right click shows a small menu.
- **The panel** (`Panel.swift`): a borderless `NSPanel` with `.nonactivatingPanel`, so it takes typing while the app you were in stays in front. Without an active app there is no Edit menu, so the panel handles ⌘X/C/V/A/Z itself, and Esc before the text view turns it into word completion.
- **Glass**: `NSGlassEffectView` on macOS 26 and later, an `NSVisualEffectView` with the menu material before that.
- **Hiding when you click away** (`ScratchpadController.swift`): a global mouse-down monitor (it only sees clicks in other apps, so clicks on the icon don't count) and app switches. Both are ignored while pinned.
- **Shrinking into the icon**: the panel hides at once, and a copy with a picture of its contents shrinks into the icon. The text does not reflow while it shrinks.
- **Pictures** (`TextView.swift`): paste and drop go through `readSelection(from:type:)`. Images become attachments that fit the width. Text is always read as plain text.
- **Saving**: `scratchpad.rtfd` in Application Support, half a second after you stop typing, and when it hides or quits. Colors are put back on load, because RTF stores the Dark Mode text color as plain white.
