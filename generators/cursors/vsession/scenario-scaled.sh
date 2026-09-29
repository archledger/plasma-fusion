# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# vsession scenario: the test device runs its panel at scale 4/3 (docs/PLAN.md). Set the virtual
# output to 4/3, then shoot every Qt::CursorShape (KWin renders the SVG cursors at device pixel
# ratio 4/3) and the GTK 3 names (GTK 3 loads the Xcursor files at size 24 x 2 with buffer scale 2).
# The seed holds .config/kcminputrc [Mouse] cursorTheme=PlasmaFusion-cursors, cursorSize=24.
T=$HOME/pfv-cursor-test
kscreen-doctor -j >"$OUT/outputs-before.json" 2>"$OUT/kscreen.log"
name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["outputs"][0]["name"])' "$OUT/outputs-before.json")
kscreen-doctor "output.$name.scale.1.333333" >>"$OUT/kscreen.log" 2>&1
sleep 3
kscreen-doctor -o >"$OUT/outputs-after.txt" 2>&1
qdbus-qt6 org.kde.KWin /KWin supportInformation 2>/dev/null | grep -A2 '^Cursor$' >"$OUT/kwin-cursor.txt"

python3 "$T/qtcursors.py" "$OUT/qt-cells.json" >"$OUT/qtapp.log" 2>&1 &
QTPID=$!
for _ in $(seq 1 50); do [ -s "$OUT/qt-cells.json" ] && break; sleep 0.2; done
python3 "$T/eipointer.py" "$OUT/qt-cells.json" "$OUT" qt >"$OUT/ei-qt.log" 2>&1
kill $QTPID 2>/dev/null
sleep 1

gsettings set org.gnome.desktop.interface cursor-theme PlasmaFusion-cursors >"$OUT/gsettings.txt" 2>&1
gsettings set org.gnome.desktop.interface cursor-size 24 >>"$OUT/gsettings.txt" 2>&1
python3 "$T/gtkcursors.py" "$OUT/gtk-cells.json" >"$OUT/gtkapp.log" 2>&1 &
GPID=$!
for _ in $(seq 1 50); do [ -s "$OUT/gtk-cells.json" ] && break; sleep 0.2; done
python3 "$T/eipointer.py" "$OUT/gtk-cells.json" "$OUT" gtk >"$OUT/ei-gtk.log" 2>&1
kill $GPID 2>/dev/null

grep -n -i -E 'cursor|svg|xcursor|metadata' "$OUT/kwin.log" >"$OUT/kwin-cursor-lines.txt" 2>&1
true
