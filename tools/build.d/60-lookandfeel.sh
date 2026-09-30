#!/bin/bash
# Global Themes org.plasmafusion.dark.desktop and org.plasmafusion.light.desktop: defaults,
# desktop layout (with ensure-topbars.js), splash screen, log-out screen and previews, into
# $STAGE/.local/share/plasma/look-and-feel/, and the "Add Panel" layout templates for the top bar
# and the dock into $STAGE/.local/share/plasma/layout-templates/. The splash gets copies of the shared QML blocks it
# uses (packages/common/*.qml, tools/build-lib/shared-qml.sh) in contents/splash.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

SRC=$ROOT/packages/look-and-feel
GEN=$ROOT/generators/look-and-feel
DEST=$STAGE/.local/share/plasma/look-and-feel

bash "$ROOT/tools/build-lib/shared-qml.sh" check "$SRC/common/contents/splash" "look-and-feel: splash"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The splash background is the board's blurred wallpaper, rendered once for both packages, with a
# portrait version (the sun kept in view; ADAPTIVE 5.11).
python3 "$GEN/splash_background.py" "$WORK/background.png" 1920x1200
python3 "$GEN/splash_background.py" "$WORK/background-portrait.png" 1200x1920

for id in org.plasmafusion.dark.desktop org.plasmafusion.light.desktop; do
  pkg=$DEST/$id
  rm -rf "$pkg"
  mkdir -p "$pkg/contents"
  install -m 0644 "$SRC/$id/metadata.json" "$pkg/metadata.json"
  install -m 0644 "$SRC/$id/contents/defaults" "$pkg/contents/defaults"
  cp -r "$SRC/common/contents/layouts" "$SRC/common/contents/splash" "$SRC/common/contents/logout" "$pkg/contents/"
  bash "$ROOT/tools/build-lib/shared-qml.sh" install "$SRC/common/contents/splash" "$pkg/contents/splash"
  mkdir -p "$pkg/contents/splash/images" "$pkg/contents/previews"
  install -m 0644 "$WORK/background.png" "$pkg/contents/splash/images/background.png"
  install -m 0644 "$WORK/background-portrait.png" "$pkg/contents/splash/images/background-portrait.png"
  for f in preview.png fullscreenpreview.jpg splash.png; do
    install -m 0644 "$SRC/$id/contents/previews/$f" "$pkg/contents/previews/$f"
  done
  find "$pkg" -type d -exec chmod 0755 {} + && find "$pkg" -type f -exec chmod 0644 {} +
done
echo "look-and-feel: $(ls "$DEST" | tr '\n' ' ')"

# "Add Panel" templates: the Plasma Fusion top bar and dock (owner decision 8, ADAPTIVE 6), at
#   $STAGE/.local/share/plasma/layout-templates/org.plasmafusion.panel.{topbar,dock}/
TEMPLATES=$STAGE/.local/share/plasma/layout-templates
for id in org.plasmafusion.panel.topbar org.plasmafusion.panel.dock; do
  src=$SRC/layout-templates/$id
  python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); assert d["KPlugin"]["Id"] == sys.argv[2] and d["KPackageStructure"] == "Plasma/LayoutTemplate" and "panel" in d["X-Plasma-ContainmentCategories"]' "$src/metadata.json" "$id"
  test -s "$src/contents/layout.js"
  rm -rf "${TEMPLATES:?}/$id"
  mkdir -p "$TEMPLATES/$id/contents"
  install -m 0644 "$src/metadata.json" "$TEMPLATES/$id/metadata.json"
  install -m 0644 "$src/contents/layout.js" "$TEMPLATES/$id/contents/layout.js"
done
echo "layout templates: $(ls "$TEMPLATES" | tr '\n' ' ')"
