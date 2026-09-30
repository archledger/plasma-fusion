#!/bin/bash
# Plasma Fusion dock plasmoid (org.plasmafusion.dock): copies the QML package into the HOME tree.
# Installed like kpackagetool6 -t Plasma/Applet -i would, at
#   $STAGE/.local/share/plasma/plasmoids/org.plasmafusion.dock/
# with a copy of packages/common/FusionMetrics.qml in contents/ui.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

id=org.plasmafusion.dock
src="$ROOT/packages/plasmoids/$id"
dest="$STAGE/.local/share/plasma/plasmoids/$id"

python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["KPlugin"]["Id"]==sys.argv[2]' "$src/metadata.json" "$id"
python3 -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$src/contents/config/main.xml"

[ ! -e "$src/contents/ui/FusionMetrics.qml" ] || { echo "dock: the package has its own FusionMetrics.qml" >&2; exit 1; }

rm -rf "$dest"
mkdir -p "$dest"
cp -r "$src/metadata.json" "$src/contents" "$dest/"
install -m 0644 "$ROOT/packages/common/FusionMetrics.qml" "$dest/contents/ui/FusionMetrics.qml"
find "$dest" -type d -exec chmod 755 {} +
find "$dest" -type f -exec chmod 644 {} +
echo "  $id -> ${dest#"$STAGE"/}"
