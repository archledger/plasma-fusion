#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Real keys in a private three-output session; never run against the logged-in desktop.
# Seed HOME/pf-stage and HOME/pf-tools from the build and tools/. Use PFV_OUTPUTS=3.
set -euo pipefail
exec 2>&1
export OUT
CHK=$OUT/checks.txt
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
trap 'fail "scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }
press() { pfinput "key $1"; sleep 0.4; }
inspect() {
  K run "var c = workspace.windowList().find(w => String(w.internalId) === '$CLIENT');
    var a = workspace.clientArea(KWin.MaximizeArea, c), g = c.frameGeometry;
    report({frame:[g.x,g.y,g.width,g.height], area:[a.x,a.y,a.width,a.height],
      tile:c.tile ? [c.tile.relativeGeometry.x,c.tile.relativeGeometry.y,c.tile.relativeGeometry.width,c.tile.relativeGeometry.height] : null,
      screen:c.output.name, maximized:c.maximizeMode});"
}
check() { # label, normalized tile x y w h (or floating / maximized), optional screen
  local label=$1 expected=$2 screen=${3:-} state
  state=$(inspect)
  echo "INFO $label: $state" >>"$CHK"
  if python3 - "$state" "$expected" "$screen" <<'PY'
import json, sys
s = json.loads(sys.argv[1])
expected = sys.argv[2]
ok = not sys.argv[3] or s['screen'] == sys.argv[3]
if expected == 'floating':
    ok = ok and s['tile'] is None and s['maximized'] == 0
    ok = ok and all(abs(a-b) <= 2 for a,b in zip(s['frame'], [300,200,700,500]))
elif expected == 'maximized':
    ok = ok and s['maximized'] == 3
else:
    target = [float(v) for v in expected.split(',')]
    ok = ok and s['tile'] is not None and s['maximized'] == 0
    ok = ok and all(abs(a-b) <= .01 for a,b in zip(s['tile'] or [], target))
    ax,ay,aw,ah = s['area']
    tx,ty,tw,th = target
    rect = [ax+tx*aw, ay+ty*ah, tw*aw, th*ah]
    ok = ok and all(abs(a-b) <= 8 for a,b in zip(s['frame'], rect))
sys.exit(0 if ok else 1)
PY
  then pass "$label"; else fail "$label"; fi
}

bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/setup.log" 2>&1
if [ -z "$(kreadconfig6 --file kwinrc --group Script-plasmafusion-snap --key StartupProbe)" ]; then
  pass "temporary startup probe config is cleared"
else fail "temporary startup probe config remains"; fi
shortcut_names=$(busctl --user call org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component shortcutNames)
if ! grep -q 'Plasma Fusion: Startup Probe ' <<<"$shortcut_names"; then
  pass "temporary startup probe action is unregistered"
else fail "temporary startup probe action remains"; fi
mapfile -t screens < <(K run 'report(Array.from(workspace.screens, s=>s.name).sort());' |
  python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)))')
[ "${#screens[@]}" = 3 ]
kscreen-doctor "output.${screens[0]}.position.0,0" "output.${screens[1]}.position.1440,0" \
  "output.${screens[2]}.position.0,900" >"$OUT/outputs.log" 2>&1
sleep 1
kscreen-doctor -o >>"$OUT/outputs.log"
kwriteconfig6 --file kwinrc --group Script-plasmafusion-snap --key Gap 0
qdbus org.kde.KWin /KWin org.kde.KWin.reconfigure
kwrite >/dev/null 2>&1 &
sleep 3
CLIENT=$(K run 'report(String(workspace.activeWindow.internalId));' | python3 -c 'import json,sys; print(json.load(sys.stdin))')
K run "var c=workspace.activeWindow;
  workspace.sendClientToScreen(c,workspace.screens.find(s=>s.name==='${screens[0]}'));
  if(c.tile)c.tile.unmanage(c); c.setMaximize(false,false);
  c.frameGeometry={x:300,y:200,width:700,height:500}; report(true);" >/dev/null
sleep 0.5
HOME_SCREEN=$(inspect | python3 -c 'import json,sys; print(json.load(sys.stdin)["screen"])')
check "initial floating rectangle" floating

# Bootstrap from a custom tile before the script has seen any native quick-tile root.
custom=$(K run "var c=workspace.windowList().find(w=>String(w.internalId)==='$CLIENT');
  var t=workspace.rootTile(c.output,c.desktops[0] || workspace.currentDesktop); while(t.tiles.length)t=t.tiles[0];
  report(t.manage(c) && c.tile===t);")
if [ "$custom" = true ]; then pass "cold custom-tile fixture is managed"; else fail "custom tile fixture failed"; fi
press meta+left
check "first direction from a cold custom tile" 0,0,0.5,1
press meta+backspace
check "custom-to-directional preserves floating restore" floating

for direction in left right up down; do
  case $direction in
    left) expected=0,0,0.5,1 ;;
    right) expected=0.5,0,0.5,1 ;;
    up) expected=0,0,1,0.5 ;;
    down) expected=0,0.5,1,0.5 ;;
  esac
  press "meta+$direction"
  check "$direction half" "$expected"
  press "meta+$direction"
  check "$direction repeated" "$expected" "$HOME_SCREEN"
  press meta+backspace
  check "$direction restores original rectangle" floating
done
press meta+left
press meta+up
check "Left then Up" 0,0,0.5,0.5
press meta+right
check "opposite horizontal retains row" 0.5,0,0.5,0.5
press meta+down
check "opposite vertical retains column" 0.5,0.5,0.5,0.5
press meta+backspace
press meta+up
press meta+left
check "Up then Left" 0,0,0.5,0.5
shot 10-top-left

press meta+shift+right
check "monitor right preserves corner" 0,0,0.5,0.5
OTHER_SCREEN=$(inspect | python3 -c 'import json,sys; print(json.load(sys.stdin)["screen"])')
if [ "$OTHER_SCREEN" != "$HOME_SCREEN" ]; then pass "monitor right changed output"; else fail "monitor right changed output"; fi
press meta+shift+left
check "monitor left returns" 0,0,0.5,0.5 "$HOME_SCREEN"
press meta+shift+down
check "monitor down preserves corner" 0,0,0.5,0.5
OTHER_SCREEN=$(inspect | python3 -c 'import json,sys; print(json.load(sys.stdin)["screen"])')
if [ "$OTHER_SCREEN" != "$HOME_SCREEN" ]; then pass "monitor down changed output"; else fail "monitor down changed output"; fi
press meta+shift+up
check "monitor up returns" 0,0,0.5,0.5 "$HOME_SCREEN"
press meta+shift+up
check "missing upper monitor is a no-op" 0,0,0.5,0.5 "$HOME_SCREEN"

K run "var c=workspace.windowList().find(w=>String(w.internalId)==='$CLIENT'), root=c.tile.parent;
  var left=root.tiles.find(t=>t.relativeGeometry.x===0 && t.relativeGeometry.height===1);
  var top=root.tiles.find(t=>t.relativeGeometry.y===0 && t.relativeGeometry.width===1);
  left.relativeGeometry={x:0,y:0,width:0.6,height:1};
  top.relativeGeometry={x:0,y:0,width:1,height:0.4}; report(true);" >/dev/null
sleep 0.5
check "manually resized corner" 0,0,0.6,0.4
press meta+shift+right
check "monitor move preserves resized proportions" 0,0,0.6,0.4
press meta+shift+left
check "resized corner returns" 0,0,0.6,0.4 "$HOME_SCREEN"
press meta+backspace
check "restore after monitor round trip" floating
press meta+pageup
check "dedicated maximize key" maximized
press meta+backspace
check "restore from maximized" floating
press meta+pageup
pfinput 'key meta+left' 'key meta+up'
sleep 0.5
check "rapid corner from maximized" 0,0,0.5,0.5
press meta+backspace

# Two input chords with no intervening geometry query or wait exercise pending Wayland resizes.
pfinput 'key meta+left' 'key meta+down'
sleep 0.5
check "rapid perpendicular sequence" 0,0.5,0.5,0.5
press meta+backspace

# A second window makes the half picker appear. Keep the original as the shortcut target.
printf '%s\n' 'Second window for snap assistance.' > "$OUT/candidate.txt"
kwrite "$OUT/candidate.txt" >"$OUT/candidate.log" 2>&1 &
sleep 2
count=$(K run 'report(workspace.windowList().filter(w=>w.normalWindow && String(w.resourceClass).indexOf("kwrite")>=0).length);')
if [ "$count" -ge 2 ]; then pass "two real KWrite windows exist"; else fail "second KWrite window did not open"; fi
K run "workspace.activeWindow=workspace.windowList().find(w=>String(w.internalId)==='$CLIENT'); report(true);" >/dev/null
press meta+left
sleep 0.5
picker=$(K run 'report(workspace.windowList().some(w=>w.caption==="Pick a window for this side"));')
if [ "$picker" = true ]; then pass "half picker is actually visible"; else fail "half picker did not appear"; fi
press meta+up
check "corner chaining while another window is offered" 0,0,0.5,0.5
shot 20-picker-chain

# Monitor movement has no resize requirement. Use a real fixed-size Qt window, not a rule mock.
# The Qt runner is present in the test images; this does not require Python Qt bindings.
cat >"$OUT/fixed-window.qml" <<'QML'
import QtQuick
import QtQuick.Window
Window {
    title: "Fixed-size movement test"
    width: 360; height: 240
    minimumWidth: 360; maximumWidth: 360
    minimumHeight: 240; maximumHeight: 240
    visible: true
}
QML
qml "$OUT/fixed-window.qml" >"$OUT/fixed-window.log" 2>&1 &
fixed_pid=$!
sleep 2
fixed_exists=$(K run "report(workspace.windowList().some(w=>w.caption==='Fixed-size movement test'));")
if [ "$fixed_exists" = true ]; then pass "fixed-size native fixture is visible"; else
  fail "fixed-size native fixture did not open"
  exit 1
fi
K run "var c=workspace.windowList().find(w=>w.caption==='Fixed-size movement test');
  workspace.sendClientToScreen(c,workspace.screens.find(s=>s.name==='${screens[0]}'));
  workspace.activeWindow=c; report(true);" >/dev/null
sleep 0.5
fixed_before=$(K run "var c=workspace.windowList().find(w=>w.caption==='Fixed-size movement test');
  report({resizeable:c.resizeable,screen:c.output.name});")
press meta+shift+right
fixed_after=$(K run "var c=workspace.windowList().find(w=>w.caption==='Fixed-size movement test');
  report({resizeable:c.resizeable,screen:c.output.name});")
if python3 - "$fixed_before" "$fixed_after" <<'PY'
import json, sys
before, after = map(json.loads, sys.argv[1:])
assert not before['resizeable'] and not after['resizeable']
assert before['screen'] != after['screen']
PY
then pass "fixed-size window moves to the adjacent monitor"; else fail "fixed-size monitor movement"; fi
kill "$fixed_pid"
wait "$fixed_pid" || true

trap - ERR
# The parent session's EXIT trap sweeps disappearing processes and must continue on read races.
# Return this final assertion's status, as the other native scenarios do, without leaking -e.
set +e
[ "$(grep -c '^FAIL' "$CHK" || true)" = 0 ]
