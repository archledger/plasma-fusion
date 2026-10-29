# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Sourced in an isolated vsession with tablet mode on, the navigation plugin installed in the
# seed, and tools/ at ~/pf-tools. ~/navigation-case holds TARGET_INDEX OTHER_WINDOW_COUNT
# and an optional non-owner input: none (default), click or touch.
# Use 1280x800 at scale 1, with one or two outputs. No logged-in desktop is modified.
# shellcheck shell=bash
# Keep strict-mode changes inside this test: the parent session owns process teardown.
(
set -euo pipefail
read -r target others other_input < "$HOME/navigation-case"
other_input=${other_input:-none}
case "$other_input" in none|click|touch) ;; *) echo 'invalid non-owner input' >&2; exit 1 ;; esac
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }
effects() { qdbus org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects; }
qdbus org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect plasmafusion_navigation
kwrite >"$OUT/kwrite.log" 2>&1 &
sleep 3
K run "var w=workspace.activeWindow; var s=workspace.screens[$target];
if (!w || !s) { throw new Error('Navigation test: target window or output missing'); }
workspace.sendClientToScreen(w,s); w.frameGeometry={x:s.geometry.x+100,y:100,width:600,height:400};
report({id:String(w.internalId),output:s.name,x:s.geometry.x+300});" >"$OUT/target.json"
for ((i=0; i<others; i++)); do
    cat >"$HOME/other-$i.qml" <<QML
import QtQuick
Window { visible: true; width: 320; height: 240; title: "Navigation control $i" }
QML
    qml "$HOME/other-$i.qml" >"$OUT/other-$i.log" 2>&1 &
    sleep 1
    K run "var w=workspace.stackingOrder.find(w=>w.caption==='Navigation control $i'); var s=workspace.screens[1-$target];
if (!w || !s) { throw new Error('Navigation test: control window or output missing'); }
workspace.sendClientToScreen(w,s); w.frameGeometry={x:s.geometry.x+100,y:100,width:320,height:240}; report(w.caption);"
done
id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$OUT/target.json")
x=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["x"])' "$OUT/target.json")
K run "workspace.activeWindow=workspace.stackingOrder.find(w=>String(w.internalId)==='$id'); report(true);"
K windows >"$OUT/before.json"
# Stay below the flick threshold: this tests output ownership, not velocity-filter timing.
pfinput "swipe $x 799 $x 599 2"
sleep 0.8
effects >"$OUT/effects-after.txt"
K windows >"$OUT/after.json"
shot switcher
python3 - "$OUT" "$others" <<'PY'
import json
from pathlib import Path
import sys

out = Path(sys.argv[1])
assert 'plasmafusion_navigation' in (out / 'effects-after.txt').read_text(), 'switcher closed on release'
target = json.loads((out / 'target.json').read_text())['output']
before = json.loads((out / 'before.json').read_text())['windows']
after = json.loads((out / 'after.json').read_text())['windows']
controls = [w for w in before if w['caption'].startswith('Navigation control')]
assert len(controls) == int(sys.argv[2]), 'control windows missing'
for control in controls:
    current = next(w for w in after if w['id'] == control['id'])
    assert not current['minimized'], 'navigation minimized a window on another output'
assert all(w['output'] != target for w in controls)
print('PASS: slow swipe stays open and leaves other-output windows untouched')
PY
count=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["outputs"]))' "$OUT/before.json")
if [[ "$other_input" != none ]]; then
    (( count == 2 )) || { echo 'non-owner input needs two outputs' >&2; exit 1; }
    K run "var s=workspace.screens[1-$target];
report({x:s.geometry.x+s.geometry.width/2,y:s.geometry.y+s.geometry.height/2});" >"$OUT/non-owner.json"
    read -r other_x other_y < <(python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); print(p["x"],p["y"])' "$OUT/non-owner.json")
    if [[ "$other_input" == click ]]; then
        pfinput "click $other_x $other_y"
    else
        pfinput "tap $other_x $other_y"
    fi
    sleep 0.2
    effects >"$OUT/effects-after-non-owner.txt"
    grep -q plasmafusion_navigation "$OUT/effects-after-non-owner.txt" || {
        echo 'FAIL: non-owner input dismissed the switcher before Escape' >&2
        exit 1
    }
fi
# Escape must work even after another output is clicked or touched.
pfinput 'key esc'
sleep 0.5
effects >"$OUT/effects-after-escape.txt"
if grep -q plasmafusion_navigation "$OUT/effects-after-escape.txt"; then
    echo 'FAIL: Escape did not close the owning switcher' >&2
    exit 1
fi
echo 'PASS: Escape closes the switcher'
# Removing the owning output must release the effect's input grab, not strand an empty view.
if (( count > 1 )); then
    pfinput "swipe $x 799 $x 599 2"
    sleep 0.8
    effects >"$OUT/effects-before-removal.txt"
    grep -q plasmafusion_navigation "$OUT/effects-before-removal.txt" || {
        echo 'FAIL: switcher did not reopen before output removal' >&2
        exit 1
    }
    name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["output"])' "$OUT/target.json")
    kscreen-doctor "output.$name.disable" >"$OUT/output-removal.log" 2>&1
    sleep 0.5
    K windows >"$OUT/after-removal.json"
    python3 - "$OUT/after-removal.json" "$name" "$count" <<'PY'
import json
import sys

outputs = json.load(open(sys.argv[1]))['outputs']
assert len(outputs) == int(sys.argv[3]) - 1, 'output count did not decrease'
assert all(output['name'] != sys.argv[2] for output in outputs), 'owning output remains enabled'
PY
    effects >"$OUT/effects-after-removal.txt"
    if grep -q plasmafusion_navigation "$OUT/effects-after-removal.txt"; then
        echo 'FAIL: removing the owning output left the effect active' >&2
        exit 1
    fi
    echo 'PASS: output removal closes the effect'
fi
)
