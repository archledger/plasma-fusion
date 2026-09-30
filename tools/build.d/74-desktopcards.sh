#!/bin/bash
# Desktop card plasmoids org.plasmafusion.weathercard, org.plasmafusion.calendarcard and
# org.plasmafusion.systemcard (Main board, "Plasma desktop widgets"), copied into the staged HOME
# as kpackagetool6 -t Plasma/Applet -i would install them:
#   $STAGE/.local/share/plasma/plasmoids/org.plasmafusion.{weathercard,calendarcard,systemcard}/
# each with copies of the shared QML blocks it uses (packages/common/*.qml,
# tools/build-lib/shared-qml.sh) in contents/ui.
# Checks: metadata ids, the config schemas parse, the three copies of the shared card files are
# identical, and (when node is installed) the weather helper tests pass.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

IDS="org.plasmafusion.weathercard org.plasmafusion.calendarcard org.plasmafusion.systemcard"
SHARED="CardPalette.qml CardText.qml LineGlyph.qml"
PKG=$ROOT/packages/plasmoids

for f in $SHARED; do
  for id in $IDS; do
    cmp -s "$PKG/org.plasmafusion.weathercard/contents/ui/$f" "$PKG/$id/contents/ui/$f" \
      || { echo "desktopcards: $id/contents/ui/$f differs from the weather card's copy" >&2; exit 1; }
  done
done

if command -v node >/dev/null 2>&1; then
  node "$PKG/org.plasmafusion.weathercard/tests/weather.test.js" >/dev/null
fi

for id in $IDS; do
  src=$PKG/$id
  dest=$STAGE/.local/share/plasma/plasmoids/$id

  python3 - "$src/metadata.json" "$id" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
assert meta["KPackageStructure"] == "Plasma/Applet", "not a Plasma/Applet package"
assert meta["KPlugin"]["Id"] == sys.argv[2], "plugin id does not match the directory"
PY
  python3 -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$src/contents/config/main.xml"

  bash "$ROOT/tools/build-lib/shared-qml.sh" check "$src" "desktopcards: $id"

  rm -rf "$dest"
  mkdir -p "$dest"
  cp -r "$src/metadata.json" "$src/contents" "$dest/"
  bash "$ROOT/tools/build-lib/shared-qml.sh" install "$src" "$dest/contents/ui"
  find "$dest" -type d -exec chmod 0755 {} +
  find "$dest" -type f -exec chmod 0644 {} +
  echo "  $id -> ${dest#"$STAGE"/} ($(find "$dest" -type f | wc -l) files)"
done
