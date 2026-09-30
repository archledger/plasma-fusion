#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion pen menu (org.plasmafusion.pen, docs/parts/pen.md, PEN.md 3 and 5): the QML package
# into $STAGE/.local/share/plasma/plasmoids/org.plasmafusion.pen/ with copies of the shared QML
# blocks it uses (packages/common/*.qml, tools/build-lib/shared-qml.sh) in contents/ui, and the two
# Xournal++ templates the "New note" and "Whiteboard" tiles copy into ~/Documents/Notes/, into
# $STAGE/.local/share/plasma-fusion/pen/templates/ (found there, or in /usr/share after an RPM
# install, with StandardPaths.locate). The libwacom description is written by
# tools/pen/pen-defaults.sh (fusion-config.sh --pen), not staged.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

id=org.plasmafusion.pen
src="$ROOT/packages/plasmoids/$id"
dest="$STAGE/.local/share/plasma/plasmoids/$id"
templates="$STAGE/.local/share/plasma-fusion/pen/templates"

python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["KPlugin"]["Id"]==sys.argv[2] and d["KPackageStructure"]=="Plasma/Applet"' "$src/metadata.json" "$id"
python3 - "$src/contents/config/main.xml" <<'PY'
import sys, xml.dom.minidom as m
doc = m.parse(sys.argv[1])
names = {e.getAttribute("name") for e in doc.getElementsByTagName("entry")}
missing = {"showButton", "actions", "garageAction", "openRequest", "forcePen"} - names
assert not missing, "main.xml lacks %s" % sorted(missing)
PY

bash "$ROOT/tools/build-lib/shared-qml.sh" check "$src" pen

rm -rf "$dest"
mkdir -p "$dest"
cp -r "$src/metadata.json" "$src/contents" "$dest/"
bash "$ROOT/tools/build-lib/shared-qml.sh" install "$src" "$dest/contents/ui"
find "$dest" -type d -exec chmod 755 {} +
find "$dest" -type f -exec chmod 644 {} +

# Xournal++ templates: gzip-compressed XML (fileversion 4), written with a fixed time stamp so
# every build gives the same bytes. Note: A4 portrait, ruled; Whiteboard: A4 landscape, plain.
mkdir -p "$templates"
python3 - "$templates" <<'PY'
import gzip, os, sys
out = sys.argv[1]
def page(w, h, style):
    return ('<page width="%s" height="%s">\n<background type="solid" color="#ffffffff" style="%s"/>\n<layer/>\n</page>\n'
            % (w, h, style))
def doc(pages):
    return ('<?xml version="1.0" standalone="no"?>\n<xournal creator="Plasma Fusion" fileversion="4">\n'
            '<title>Xournal++ document - see https://xournalpp.github.io/</title>\n' + pages + '</xournal>\n')
for name, body in (("Note.xopp", doc(page("595.27559100", "841.88976400", "lined"))),
                   ("Whiteboard.xopp", doc(page("841.88976400", "595.27559100", "plain")))):
    with open(os.path.join(out, name), "wb") as f:
        with gzip.GzipFile(filename="", mode="wb", fileobj=f, mtime=0) as z:
            z.write(body.encode())
PY
chmod 755 "$templates"
chmod 644 "$templates"/*.xopp
echo "  $id -> ${dest#"$STAGE"/} ($(find "$dest" -type f | wc -l) files), templates -> ${templates#"$STAGE"/}"
