#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Top bar plasmoids org.plasmafusion.appname (logo button + active application name) and
# org.plasmafusion.clockpill (workspace dots + date + time + calendar pop-up), copied into the
# staged HOME as kpackagetool6 -t Plasma/Applet -i would install them:
#   $STAGE/.local/share/plasma/plasmoids/org.plasmafusion.{appname,clockpill}/
# Both get copies of the shared QML blocks they use (packages/common/*.qml: FusionMetrics for the
# text scale and pixel grid, and so on; tools/build-lib/shared-qml.sh) in contents/ui.
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
  xml="$src/contents/config/main.xml"
  if [ -f "$xml" ]; then
    python3 -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$xml"
  fi

  bash "$ROOT/tools/build-lib/shared-qml.sh" check "$src" "topbar: $id"

  rm -rf "$dest"
  mkdir -p "$dest"
  cp -r "$src/metadata.json" "$src/contents" "$dest/"
  bash "$ROOT/tools/build-lib/shared-qml.sh" install "$src" "$dest/contents/ui"
  find "$dest" -type d -exec chmod 0755 {} +
  find "$dest" -type f -exec chmod 0644 {} +
  echo "  $id -> ${dest#"$STAGE"/} ($(find "$dest" -type f | wc -l) files)"
done
