#!/bin/bash
# Global Themes org.plasmafusion.dark.desktop and org.plasmafusion.light.desktop: defaults,
# desktop layout, splash screen, log-out screen and previews, into
# $STAGE/.local/share/plasma/look-and-feel/.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

SRC=$ROOT/packages/look-and-feel
GEN=$ROOT/generators/look-and-feel
DEST=$STAGE/.local/share/plasma/look-and-feel

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The splash background is the board's blurred wallpaper, rendered once for both packages.
python3 "$GEN/splash_background.py" "$WORK/background.png" 1920x1200

for id in org.plasmafusion.dark.desktop org.plasmafusion.light.desktop; do
  pkg=$DEST/$id
  rm -rf "$pkg"
  mkdir -p "$pkg/contents"
  install -m 0644 "$SRC/$id/metadata.json" "$pkg/metadata.json"
  install -m 0644 "$SRC/$id/contents/defaults" "$pkg/contents/defaults"
  cp -r "$SRC/common/contents/layouts" "$SRC/common/contents/splash" "$SRC/common/contents/logout" "$pkg/contents/"
  mkdir -p "$pkg/contents/splash/images" "$pkg/contents/previews"
  install -m 0644 "$WORK/background.png" "$pkg/contents/splash/images/background.png"
  for f in preview.png fullscreenpreview.jpg splash.png; do
    install -m 0644 "$SRC/$id/contents/previews/$f" "$pkg/contents/previews/$f"
  done
  find "$pkg" -type d -exec chmod 0755 {} + && find "$pkg" -type f -exec chmod 0644 {} +
done
echo "look-and-feel: $(ls "$DEST" | tr '\n' ' ')"
