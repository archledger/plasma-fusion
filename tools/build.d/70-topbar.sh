#!/bin/bash
# Top bar plasmoids org.plasmafusion.appname (logo button + active application name) and
# org.plasmafusion.clockpill (workspace dots + date + time + calendar pop-up), copied into the
# staged HOME as kpackagetool6 -t Plasma/Applet -i would install them:
#   $STAGE/.local/share/plasma/plasmoids/org.plasmafusion.{appname,clockpill}/
# Both get a copy of packages/common/FusionMetrics.qml (text scale and pixel grid) in contents/ui.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

for id in org.plasmafusion.appname org.plasmafusion.clockpill; do
  src="$ROOT/packages/plasmoids/$id"
  dest="$STAGE/.local/share/plasma/plasmoids/$id"

  python3 - "$src/metadata.json" "$id" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
assert meta["KPackageStructure"] == "Plasma/Applet", "not a Plasma/Applet package"
assert meta["KPlugin"]["Id"] == sys.argv[2], "plugin id does not match the directory"
PY
  for xml in "$src"/contents/config/main.xml; do
    [ -f "$xml" ] && python3 -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$xml"
  done

  [ ! -e "$src/contents/ui/FusionMetrics.qml" ] || { echo "topbar: $id has its own FusionMetrics.qml" >&2; exit 1; }

  rm -rf "$dest"
  mkdir -p "$dest"
  cp -r "$src/metadata.json" "$src/contents" "$dest/"
  install -m 0644 "$ROOT/packages/common/FusionMetrics.qml" "$dest/contents/ui/FusionMetrics.qml"
  find "$dest" -type d -exec chmod 0755 {} +
  find "$dest" -type f -exec chmod 0644 {} +
  echo "  $id -> ${dest#"$STAGE"/} ($(find "$dest" -type f | wc -l) files)"
done
