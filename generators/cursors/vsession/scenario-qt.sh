# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# vsession scenario (sourced by tools/vsession/vsession.sh): KWin SVG cursors through Qt's
# cursor-shape-v1 requests, the cursor settings tool and a live switch to the light theme.
# The seed HOME holds the staged themes, .config/kcminputrc and pfv-cursor-test/ (this folder).
T=$HOME/pfv-cursor-test
cp "$HOME/.config/kcminputrc" "$OUT/kcminputrc-before.txt"
grep -A3 '^Cursor' "$OUT/kwin-support.txt" >"$OUT/kwin-cursor-before.txt" 2>&1
plasma-apply-cursortheme --list-themes >"$OUT/list-themes.txt" 2>&1

# pointer over the empty desktop (plasmashell's desktop view)
echo '{"cells":[{"name":"desktop","x":720,"y":430}]}' >"$OUT/desk-cells.json"
python3 "$T/eipointer.py" "$OUT/desk-cells.json" "$OUT" kwin >"$OUT/ei-desk.log" 2>&1

# one cell per Qt::CursorShape; the busy shapes are shot three times to catch different frames
python3 "$T/qtcursors.py" "$OUT/qt-cells-raw.json" >"$OUT/qtapp.log" 2>&1 &
QTPID=$!
for _ in $(seq 1 50); do [ -s "$OUT/qt-cells-raw.json" ] && break; sleep 0.2; done
python3 - "$OUT/qt-cells-raw.json" "$OUT/qt-cells.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
extra = []
for c in d['cells']:
    if c['name'] in ('wait', 'progress'):
        extra += [dict(c, name=c['name'] + '-2'), dict(c, name=c['name'] + '-3')]
d['cells'] += extra
json.dump(d, open(sys.argv[2], 'w'))
PY
python3 "$T/eipointer.py" "$OUT/qt-cells.json" "$OUT" qt >"$OUT/ei-qt.log" 2>&1

# switch the session to the light variant the way the settings page does, then shoot again
plasma-apply-cursortheme PlasmaFusion-Light-cursors --size 24 >"$OUT/apply-light.txt" 2>&1
sleep 1
cp "$HOME/.config/kcminputrc" "$OUT/kcminputrc-after.txt"
qdbus-qt6 org.kde.KWin /KWin supportInformation 2>/dev/null | grep -A3 '^Cursor' >"$OUT/kwin-cursor-after.txt"
python3 - "$OUT/qt-cells-raw.json" "$OUT/qt-light-cells.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
keep = ('default', 'pointer', 'text', 'progress', 'nwse-resize', 'copy', 'wait', 'help')
d['cells'] = [c for c in d['cells'] if c['name'] in keep]
json.dump(d, open(sys.argv[2], 'w'))
PY
python3 "$T/eipointer.py" "$OUT/qt-light-cells.json" "$OUT" qtlight >"$OUT/ei-qtlight.log" 2>&1
kill $QTPID 2>/dev/null
