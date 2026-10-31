# Developing Scratchpad

Notes for building, signing and releasing Scratchpad. To install it, see the [README](README.md).

## Build

Needs the Xcode Command Line Tools (`xcode-select --install`).

```sh
scripts/run-local.sh     # build, restart the app (a normal start opens the scratchpad)
scripts/build-app.sh     # build build/Scratchpad.app
scripts/make-dmg.sh      # pack it into build/Scratchpad.dmg
scripts/screenshot.sh    # take the README pictures into docs/ (flashes windows on screen)
scripts/demo-gif.sh      # draw docs/demo.gif (offscreen, uses the real BoardView)
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
- **Glass**: `NSGlassEffectView` (regular style) on macOS 26 and later, an `NSVisualEffectView` with the menu material before that. The clear style was tried and dropped: over other apps' windows it barely blurs, so their text shows sharp behind the notes.
- **Hiding when you click away** (`ScratchpadController.swift`): a global mouse monitor (it only sees clicks in other apps, so clicks on the icon don't count) and app switches. A click hides it on mouse up. A drag that ends on the scratchpad does not, so things can be dropped in. Both are ignored while pinned.
- **Opening and closing**: it fades in under the icon. On close the panel hides at once, and a copy with a picture of its contents shrinks into the icon. The text does not reflow while it shrinks.
- **Pictures and files** (`TextView.swift`, `Attachment.swift`): paste and drop go through `readSelection(from:type:)`. Files and pictures become a `ScratchAttachment` that keeps the real bytes and name in its file wrapper. Text is always read as plain text, also when it comes as RTFD with attachments.
  - Never set an attachment's `image`: saving then writes a re-encoded PNG named `Attachment.png` and drops anything that is not a picture.
  - The attachment cell macOS adds to file attachments is turned off (`attachmentCell` returns nil). It drew pictures at full size, cropped, and PDFs not at all. The attachment draws itself instead, as an exact-size bitmap: TextKit 2 does not scale attachment images and skips images that draw on demand.
  - A click on an attachment is found with `characterIndexForInsertion(at:)` and `firstRect(forCharacterRange:)`. `mouseDown` then waits: a drag starts a dragging session with a temporary copy of the file (`DragOutSource`, copy only), a click opens a picture in `ImageViewer.swift`, a double click opens a file.
  - ⌘C on a lone selected attachment copies a picture as PNG and TIFF, a file as a file URL.
- **Saving**: `scratchpad.rtfd` in Application Support, half a second after you stop typing, and when it hides or quits. The file is built on the main thread and written on a background queue (waited for on quit). Colors are put back on load, because RTF stores the Dark Mode text color as plain white.
