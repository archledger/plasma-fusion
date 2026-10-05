#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion dock plasmoid (org.plasmafusion.dock): copies the QML package into the HOME tree.
# Installed like kpackagetool6 -t Plasma/Applet -i would, at
#   $STAGE/.local/share/plasma/plasmoids/org.plasmafusion.dock/
# with copies of the shared QML blocks it uses (packages/common/*.qml, tools/build-lib/shared-qml.sh)
# in contents/ui.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

id=org.plasmafusion.dock
src="$ROOT/packages/plasmoids/$id"
dest="$STAGE/.local/share/plasma/plasmoids/$id"

python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["KPlugin"]["Id"]==sys.argv[2]' "$src/metadata.json" "$id"
python3 -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$src/contents/config/main.xml"

bash "$ROOT/tools/build-lib/shared-qml.sh" check "$src" dock

if command -v node >/dev/null 2>&1; then
  node "$src/tests/pins.test.js" >/dev/null
fi

rm -rf "$dest"
mkdir -p "$dest"
cp -r "$src/metadata.json" "$src/contents" "$dest/"
bash "$ROOT/tools/build-lib/shared-qml.sh" install "$src" "$dest/contents/ui"
find "$dest" -type d -exec chmod 755 {} +
find "$dest" -type f -exec chmod 644 {} +
echo "  $id -> ${dest#"$STAGE"/}"
