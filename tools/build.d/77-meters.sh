#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# System meters for the top bar (org.plasmafusion.meters, docs/parts/shell-meters.md), copied into
# the staged HOME as kpackagetool6 -t Plasma/Applet -i would install it:
#   $STAGE/.local/share/plasma/plasmoids/org.plasmafusion.meters/
# with copies of the shared QML blocks it uses (packages/common/*.qml,
# tools/build-lib/shared-qml.sh) in contents/ui. No layout places it; users add it.
# Checks: the metadata id, the config schema parses, the settings page declares every key, and
# (when node is installed) the formatting and limit tests of contents/code/meters.js pass.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

id=org.plasmafusion.meters
src=$ROOT/packages/plasmoids/$id
dest=$STAGE/.local/share/plasma/plasmoids/$id

python3 - "$src/metadata.json" "$id" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
assert meta["KPackageStructure"] == "Plasma/Applet", "not a Plasma/Applet package"
assert meta["KPlugin"]["Id"] == sys.argv[2], "plugin id does not match the directory"
PY
python3 -c 'import sys, xml.dom.minidom as m; m.parse(sys.argv[1])' "$src/contents/config/main.xml"
bash "$ROOT/tools/build-lib/shared-qml.sh" check "$src" "meters"
# One-page settings: every key and default declared, the ones not edited refreshed.
python3 -B "$ROOT/packages/common/tests/config_page_keys_test.py" "$src"
# The meters' numbers (contents/code/meters.js; the tests are not installed), when node is
# installed (the package build has none).
if command -v node >/dev/null 2>&1; then
  node "$src/tests/meters.test.js" >/dev/null
  # The memory figures, and the system card's copy of memory.js is the same file.
  node "$src/tests/memory.test.js" >/dev/null
fi

rm -rf "$dest"
mkdir -p "$dest"
cp -r "$src/metadata.json" "$src/contents" "$dest/"
bash "$ROOT/tools/build-lib/shared-qml.sh" install "$src" "$dest/contents/ui"
find "$dest" -type d -exec chmod 0755 {} +
find "$dest" -type f -exec chmod 0644 {} +
echo "  $id -> ${dest#"$STAGE"/} ($(find "$dest" -type f | wc -l) files)"
