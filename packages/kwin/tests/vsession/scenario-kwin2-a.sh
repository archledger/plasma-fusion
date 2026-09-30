# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# KWIN-2 private-session scenario A (test tooling; PLAN "KWIN-2", ADAPTIVE 5.7/5.8, fix 24,
# TABLET 4.10): the Meta+Z flyout under the real maximize button for the compiled decoration
# (RightGlyphs, LeftCircles) and the Aurorae -Left theme; the switcher (live previews, hover to select,
# click to activate); snap + fill picker; portrait row layouts and
# the clamp after a rotation; tablet posture.
exec 2>&1
export OUT
set -x
CHK=$OUT/checks.txt
KLOG=$OUT/kwin.log
PLOG=$OUT/plasmashell.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }
place() { # CLASS X Y W H: untile, place and activate
  K run "var l = workspace.windowList(); for (var i = 0; i < l.length; ++i) { var w = l[i];
    if (w.normalWindow && String(w.resourceClass).indexOf('$1') >= 0) {
      if (w.tile) { w.tile.unmanage(w); } w.setMaximize(false, false);
      w.frameGeometry = {x: $2, y: $3, width: $4, height: $5}; workspace.activeWindow = w; } }
    report('placed $1');" >>"$OUT/place.log"
}
active() { K run "report(workspace.activeWindow ? String(workspace.activeWindow.resourceClass) : 'none')" | tr -d '"'; }
state() { # NAME: every normal window with border, tile and maximize state
  K run "var l = workspace.windowList(), out = [], a = workspace.clientArea(KWin.MaximizeArea, workspace.activeScreen, workspace.currentDesktop);
    for (var i = 0; i < l.length; ++i) { var w = l[i]; if (!w.normalWindow) { continue; }
      out.push({cls: String(w.resourceClass), geo: rect(w.frameGeometry), nb: w.noBorder, tiled: !!w.tile, max: w.maximizeMode, min: w.minimized}); }
    report({area: rect(a), windows: out});" >"$OUT/state-$1.json"
}
inside() { # NAME LABEL: every normal, untiled window of state NAME lies inside the work area
  python3 - "$OUT/state-$1.json" "$2" >>"$CHK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); a = d["area"]; bad = []
for w in d["windows"]:
    g = w["geo"]
    if w["min"]: continue
    if g["x"] < a["x"] - 0.5 or g["y"] < a["y"] - 0.5 or g["x"] + g["w"] > a["x"] + a["w"] + 0.5 or g["y"] + g["h"] > a["y"] + a["h"] + 0.5:
        bad.append((w["cls"], g))
print(("PASS" if not bad else "FAIL") + f" {sys.argv[2]}: windows inside the work area {a}" + (f"; outside: {bad}" if bad else f" ({[(w['cls'], w['geo']) for w in d['windows']]})"))
PY
}
deco() { # LIBRARY THEME BUTTONSTYLE
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library "$1"
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme "$2"
  kwriteconfig6 --file plasmafusionrc --group Decoration --key ButtonStyle "$3"
  qdbus org.kde.KWin /KWin reconfigure; sleep 3
  info "decoration: $(qdbus org.kde.KWin /KWin supportInformation | grep -E '^(Plugin|Theme):' | tr '\n' ' ') ButtonStyle=$3"
}
flyout_test() { # LABEL SIDE
  place kwrite 320 140 800 520; sleep 0.8
  pfinput 'key meta+z'; sleep 1.6
  K windows >"$OUT/win-fly-$1.json"
  shot "fly-$1"
  python3 - "$OUT/win-fly-$1.json" "$2" "$1" >>"$CHK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); side = sys.argv[2]; label = sys.argv[3]
fly = [w for w in d["windows"] if w["caption"] == "Snap layouts"]
kw = [w for w in d["windows"] if "kwrite" in w["cls"] and w["normal"]]
if not fly or not kw:
    print(f"FAIL flyout {label}: flyout windows {len(fly)}, kwrite {len(kw)}; captions {[w['caption'] for w in d['windows']]}"); sys.exit()
f, k = fly[0]["geo"], kw[0]["geo"]
centre = f["x"] + f["w"] / 2
want = k["x"] + 58.5 if side == "left" else k["x"] + k["w"] - 59
print(("PASS" if abs(centre - want) <= 1.0 else "FAIL") + f" flyout {label}: centre {centre} vs the maximize button {want} ({side}); flyout {f}, window {k}")
PY
  pfinput 'key esc'; sleep 0.8
}

bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1
info "fusion-config rc=$?"
kwriteconfig6 --file kwinrc --group Script-plasmafusion-tablet --key InternalOutputs "eDP,LVDS,DSI,Virtual"
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardShown true
pfv_restart_shell 12
qdbus org.kde.KWin /KWin reconfigure; sleep 3
konsole -e bash -c 'while :; do date +%T.%N; sleep 0.2; done' >/dev/null 2>&1 &
sleep 3
dolphin >/dev/null 2>&1 &
sleep 4
kwrite >/dev/null 2>&1 &
sleep 4
place konsole 60 80 700 460; place dolphin 500 300 800 500; place kwrite 320 140 800 520
pfinput 'move 720 870'
grep -a 'plasmafusion-snap' "$KLOG" | tail -3 >>"$CHK"

# ---- 1. the flyout under the maximize button
deco org.plasmafusion.decoration "" RightGlyphs;  flyout_test cpp-right right
deco org.plasmafusion.decoration "" LeftCircles;  flyout_test cpp-left left
deco org.kde.kwin.aurorae __aurorae__svg__PlasmaFusionDark-Left RightGlyphs; flyout_test aurorae-left left
deco org.kde.kwin.aurorae __aurorae__svg__PlasmaFusionDark RightGlyphs; flyout_test aurorae-right right
# the switcher's previews with the Aurorae title bars (another shadow around the frame)
pfinput 'keydown alt' 'key tab' 'sleep 2.6' 'keyup alt' &
p=$!
sleep 1.4; shot sw-aurorae; wait $p; sleep 1
pfinput 'keydown alt' 'key tab' 'sleep 0.6' 'keyup alt'; sleep 1   # back: the order is as before
deco org.plasmafusion.decoration "" RightGlyphs
grep -a 'plasmafusion-snap: maximize' "$KLOG" | tr '\n' ';' >>"$CHK"; echo >>"$CHK"

# ---- 2. the switcher: both windows, live thumbnails, hover, click
pfinput 'keydown alt' 'key tab' 'sleep 5.5' 'keyup alt' &
p=$!
sleep 1.2; K windows >"$OUT/win-sw.json"; shot sw-1; sleep 0.8; shot sw-2; wait $p; sleep 1
info "after Alt+Tab: active $(active) (before: kwrite; MRU was kwrite, dolphin, konsole)"
read -r CX CY CW <<<"$(python3 - "$OUT/win-sw.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
c = [w for w in d["windows"] if w["caption"] == "Window switcher"]
b = [w for w in d["windows"] if w["caption"] == "Window switcher backdrop"]
if c:
    g = c[0]["geo"]; print(int(g["x"] + g["w"] / 2), int(g["y"] + 73 + 80), int(g["w"]))
else:
    print(720, 420, 0)
open(sys.argv[1] + ".txt", "w").write(f"card {c[0]['geo'] if c else None} backdrop {b[0]['geo'] if b else None}\n")
PY
)"
info "switcher windows: $(cat "$OUT/win-sw.json.txt")"
# hover: MRU is now dolphin, kwrite, konsole; Alt+Tab selects kwrite, the pointer moves onto the
# third card (konsole)
pfinput 'move 720 870' 'keydown alt' 'key tab' 'sleep 1.0' "move $((CX + 206)) $CY" 'sleep 0.1' "move $((CX + 212)) $CY" 'sleep 0.8' 'keyup alt'
sleep 1; A=$(active)
case "$A" in *konsole*) pass "switcher: hover selects (released on the hovered third card: $A)" ;; *) fail "switcher hover: active $A, expected konsole" ;; esac
# without moving the pointer the card under it must not take the selection: MRU konsole, dolphin,
# kwrite; the pointer still rests where the third card will be; Alt+Tab must give dolphin
pfinput 'keydown alt' 'key tab' 'sleep 1.2' 'keyup alt'
sleep 1; A=$(active)
case "$A" in *dolphin*) pass "switcher: a resting pointer does not select ($A)" ;; *) fail "switcher resting pointer: active $A, expected dolphin" ;; esac
# click: MRU dolphin, konsole, kwrite; click the third card (kwrite) while Alt is held
pfinput 'move 720 870' 'keydown alt' 'key tab' 'sleep 1.0' "move $((CX + 206)) $CY" "click $((CX + 212)) $CY" 'sleep 0.8' 'keyup alt'
sleep 1; A=$(active)
case "$A" in *kwrite*) pass "switcher: click activates ($A)" ;; *) fail "switcher click: active $A, expected kwrite" ;; esac
pfinput 'move 720 870'

# ---- 3. snap left + the other half (landscape)
place kwrite 320 140 800 520; sleep 0.6
pfinput 'key meta+z' 'sleep 1.2' 'key return'
sleep 1.8
K windows >"$OUT/win-pick.json"; shot pick-1; state pick1
grep -q '"caption": "Pick a window for this side"' "$OUT/win-pick.json" && pass "fill picker offered after the left half" || fail "no fill picker: $(python3 -c "import json,sys;print([w['caption'] for w in json.load(open(sys.argv[1]))['windows']])" "$OUT/win-pick.json")"
pfinput 'key return'; sleep 1.5
shot pick-2; state pick2
python3 - "$OUT/state-pick2.json" >>"$CHK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); a = d["area"]
t = sorted([w for w in d["windows"] if w["tiled"]], key=lambda w: w["geo"]["x"])
if len(t) != 2:
    print(f"FAIL halves: {len(t)} tiled windows: {d['windows']}"); sys.exit()
l, r = t[0]["geo"], t[1]["geo"]
ok = abs(l["x"] - (a["x"] + 6)) <= 1 and abs(r["x"] - (l["x"] + l["w"] + 6)) <= 1 and abs(r["x"] + r["w"] - (a["x"] + a["w"] - 6)) <= 1
print(("PASS" if ok else "FAIL") + f" halves with the 6 px gap: {t[0]['cls']} {l}, {t[1]['cls']} {r}, area {a}")
PY

# ---- 4. portrait (M09/M14): clamp, row layouts, the switcher's wrapped hints
place kwrite 320 140 800 520; place dolphin 560 330 820 520; place konsole 900 420 520 400
state land0
pfv_rotate left; sleep 6
state port0; shot port-0
inside port0 "M14 after rotating to portrait"
grep -a 'plasmafusion-snap: screens changed' "$KLOG" | tail -1 >>"$CHK"
grep -a 'plasmafusion-snap: top bars' "$KLOG" | tail -1 >>"$CHK"
K run "workspace.activeWindow = workspace.windowList().filter(function (w) { return w.normalWindow && String(w.resourceClass).indexOf('kwrite') >= 0; })[0]; report('kwrite active');" >>"$OUT/place.log"
sleep 0.6
pfinput 'key meta+z'; sleep 1.6
K windows >"$OUT/win-port-fly.json"; shot port-fly
pfinput 'key return'; sleep 1.8
shot port-pick; state port1
python3 - "$OUT/state-port1.json" >>"$CHK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); a = d["area"]
k = [w for w in d["windows"] if "kwrite" in w["cls"]][0]; g = k["geo"]
ok = k["tiled"] and abs(g["x"] - (a["x"] + 6)) <= 1 and abs(g["w"] - (a["w"] - 12)) <= 1 and abs(g["y"] - (a["y"] + 6)) <= 1 and abs(g["h"] - (a["h"] / 2 - 9)) <= 1.5
print(("PASS" if ok else "FAIL") + f" M09 row layout: top half {g} in {a}, tiled {k['tiled']}")
PY
pfinput 'key return'; sleep 1.5
shot port-tiles; state port2
python3 - "$OUT/state-port2.json" >>"$CHK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); a = d["area"]
t = sorted([w for w in d["windows"] if w["tiled"]], key=lambda w: w["geo"]["y"])
if len(t) != 2:
    print(f"FAIL M09 top/bottom: {len(t)} tiled windows: {d['windows']}"); sys.exit()
u, b = t[0]["geo"], t[1]["geo"]
ok = abs(b["y"] - (u["y"] + u["h"] + 6)) <= 1 and abs(b["y"] + b["h"] - (a["y"] + a["h"] - 6)) <= 1
print(("PASS" if ok else "FAIL") + f" M09 the other half is the bottom: {t[0]['cls']} {u}, {t[1]['cls']} {b}")
PY
# three rows: the last zone of the last layout (Left from the first zone wraps backwards)
K run "workspace.activeWindow = workspace.windowList().filter(function (w) { return w.normalWindow && String(w.resourceClass).indexOf('konsole') >= 0; })[0]; report('konsole active');" >>"$OUT/place.log"
sleep 0.6
pfinput 'key meta+z' 'sleep 1.2' 'key left' 'sleep 0.6'
shot port-thirds-preview
pfinput 'key return'; sleep 1.5
state port3; shot port-thirds
python3 - "$OUT/state-port3.json" >>"$CHK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); a = d["area"]
k = [w for w in d["windows"] if "konsole" in w["cls"]][0]; g = k["geo"]
h = (a["h"] - 24) / 3
ok = abs(g["h"] - h) <= 1.5 and abs(g["y"] + g["h"] - (a["y"] + a["h"] - 6)) <= 1.5 and abs(g["w"] - (a["w"] - 12)) <= 1
print(("PASS" if ok else "FAIL") + f" M09 three rows: bottom third {g} in {a} (row height {h:.1f})")
PY
pfinput 'move 450 1300' 'keydown alt' 'key tab' 'sleep 2.6' 'keyup alt' &
p=$!
sleep 1.3; shot port-sw; wait $p; sleep 1
place kwrite 40 700 800 600; place dolphin 60 800 820 560; place konsole 300 900 560 480
state port4
pfv_rotate normal; sleep 6
state land1; shot land-1
inside land1 "M14 back in landscape (fix 24)"
grep -a 'plasmafusion-snap: screens changed' "$KLOG" | tail -1 >>"$CHK"

# ---- 5. tablet posture: the picker's touch sizes, the switcher's close button
pfv_tablet on; sleep 6
state tab0
K run "workspace.activeWindow = workspace.windowList().filter(function (w) { return w.normalWindow && String(w.resourceClass).indexOf('kwrite') >= 0; })[0]; report('kwrite active');" >>"$OUT/place.log"
sleep 0.8
qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Window Quick Tile Left"
sleep 2
K windows >"$OUT/win-tab-pick.json"; shot tab-pick; state tab1
read -r TX TY <<<"$(python3 - "$OUT/win-tab-pick.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
p = [w for w in d["windows"] if w["caption"] == "Pick a window for this side"]
if p:
    g = p[0]["geo"]; print(int(g["x"] + 140), int(g["y"] + 150))
else:
    print(0, 0)
PY
)"
if [ "$TX" != 0 ]; then
  pass "T18: the picker is offered after Split left in tablet posture"
  pfinput 'sleep 0.6' "tap $TX $TY 0.2"; sleep 2
  shot tab-tiles; state tab2
  python3 - "$OUT/state-tab2.json" >>"$CHK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
t = [w for w in d["windows"] if w["tiled"]]
ok = len(t) == 2 and all(w["nb"] for w in t)
print(("PASS" if ok else "FAIL") + f" T18: two tiled windows without title bars: {[(w['cls'], w['geo'], w['nb']) for w in t]}")
PY
else
  fail "T18: no picker in tablet posture"
fi
pfinput 'keydown alt' 'key tab' 'sleep 2.6' 'keyup alt' &
p=$!
sleep 1.3; shot tab-sw; wait $p; sleep 1
pfv_tablet off; sleep 5
state tab3; shot tab-off
python3 - "$OUT/state-tab3.json" >>"$CHK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
nb = [w["cls"] for w in d["windows"] if w["nb"]]
print(("PASS" if not nb else "FAIL") + f" T18: after leaving tablet posture every window has its title bar again (without: {nb})")
PY

# ---- 6. health
grep -aE 'plasmafusion-snap|org\.plasmafusion\.switcher|plasmafusion-tablet' "$KLOG" | grep -aiE 'error|TypeError|ReferenceError|Unable to assign|Binding loop|is not defined|Cannot' | sort | uniq -c | head -30 >"$OUT/warnings.txt"
info "KWin QML warnings from the Fusion scripts: $(wc -l <"$OUT/warnings.txt")"
grep -a 'ShaderEffect\|shader' "$KLOG" | head -5 >>"$OUT/warnings.txt"
[ "$(grep -ac 'KCrash: Application' "$KLOG")" = 0 ] && pass "KWin did not crash" || fail "KWin crashed"
[ "$(grep -c 'KCrash: Application' "$PLOG")" = 0 ] && pass "plasmashell did not crash" || fail "plasmashell crashed"
echo "scenario done" >>"$CHK"
