#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# KWin script plasmafusion-tablet (tablet-mode window policy and panel sizes, TABLET.md 4.2),
# installed like kpackagetool6 -t KWin/Script -i would, at
#   $STAGE/.local/share/kwin/scripts/plasmafusion-tablet/
# with copies of the shared QML blocks it uses (FusionTablet; tools/build-lib/shared-qml.sh) in
# contents/ui. Checks: the metadata id and structure, the config schema and form parse, and the
# config form names only keys of the schema.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

src=$ROOT/packages/kwin/scripts/plasmafusion-tablet
dest=$STAGE/.local/share/kwin/scripts/plasmafusion-tablet

python3 - "$src" <<'PY'
import json, pathlib, re, sys, xml.dom.minidom
src = pathlib.Path(sys.argv[1])
meta = json.loads((src / "metadata.json").read_text())
assert meta["KPlugin"]["Id"] == "plasmafusion-tablet", "KPlugin.Id is not plasmafusion-tablet"
assert meta["KPackageStructure"] == "KWin/Script", "KPackageStructure is not KWin/Script"
assert meta["X-Plasma-MainScript"] == "ui/main.qml"
schema = xml.dom.minidom.parse(str(src / "contents/config/main.xml"))
keys = {e.getAttribute("name") for e in schema.getElementsByTagName("entry")}
form = (src / "contents/ui/config.ui").read_text()
xml.dom.minidom.parseString(form)
for name in re.findall(r'name="kcfg_([A-Za-z]+)"', form):
    assert name in keys, f"config.ui names kcfg_{name}, which main.xml does not define"
PY
test -f "$src/contents/ui/main.qml"
bash "$ROOT/tools/build-lib/shared-qml.sh" check "$src" "kwin-tablet"

rm -rf "$dest"
mkdir -p "$dest"
cp -r "$src/metadata.json" "$src/contents" "$dest/"
bash "$ROOT/tools/build-lib/shared-qml.sh" install "$src" "$dest/contents/ui"
test -f "$dest/contents/ui/FusionTablet.qml" || { echo "kwin-tablet: FusionTablet.qml was not installed" >&2; exit 1; }
find "$dest" -type d -exec chmod 0755 {} +
find "$dest" -type f -exec chmod 0644 {} +
echo "  plasmafusion-tablet -> ${dest#"$STAGE"/}"
