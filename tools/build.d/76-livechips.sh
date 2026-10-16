#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion live chips (org.plasmafusion.livechips, docs/parts/shell-livechips.md, LiveChips
# board): the QML package into $STAGE/.local/share/plasma/plasmoids/org.plasmafusion.livechips/
# with copies of the shared QML blocks it uses (packages/common/*.qml,
# tools/build-lib/shared-qml.sh) in contents/ui. The code's own tests (tests/chips.test.js) run in
# CI's build workflow, not here.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

id=org.plasmafusion.livechips
src="$ROOT/packages/plasmoids/$id"
dest="$STAGE/.local/share/plasma/plasmoids/$id"

python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["KPlugin"]["Id"]==sys.argv[2] and d["KPackageStructure"]=="Plasma/Applet"' "$src/metadata.json" "$id"

bash "$ROOT/tools/build-lib/shared-qml.sh" check "$src" livechips

rm -rf "$dest"
mkdir -p "$dest"
cp -r "$src/metadata.json" "$src/contents" "$dest/"
bash "$ROOT/tools/build-lib/shared-qml.sh" install "$src" "$dest/contents/ui"
find "$dest" -type d -exec chmod 755 {} +
find "$dest" -type f -exec chmod 644 {} +
echo "  $id -> ${dest#"$STAGE"/} ($(find "$dest" -type f | wc -l) files)"
