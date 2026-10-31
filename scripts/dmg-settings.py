# dmgbuild settings for Scratchpad.dmg, used by scripts/make-dmg.sh.
# Sizes and icon spots must match scripts/dmg-background.swift.
import os

app = defines["app"]  # noqa: F821 (dmgbuild passes -D values in as `defines`)
app_name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}

# dmgbuild picks up background@2x.png next to it for Retina screens.
background = defines["background"]  # noqa: F821
# The height includes the title bar, so it hides the bottom of the 600x420 picture.
window_rect = ((200, 160), (600, 420))
icon_size = 128
text_size = 14
icon_locations = {
    app_name: (150, 168),
    "Applications": (450, 168),
}
