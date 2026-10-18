#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# The tablet home screen's free side (board TabletSplit.dc.html, docs/parts/desktop.md "The free
# side beside an app") in a private session in tablet posture, with real touch (pfinput):
#   1. the home screen with nothing open: no free side;
#   2. KWrite open (maximized by the tablet policy): no free side;
#   3. KWrite quick-tiled left with nothing else open: the right part offers the apps, the pages
#      and the cards step aside (screenshot);
#   4. a tap on a home app there opens it on the right (the home screen's split request) and KWrite
#      stays on the left; with two apps side by side the free side goes;
#   5. that app closed: the free side comes back;
#   6. KWrite quick-tiled right: the free side is the left part;
#   7. KWrite maximized: the free side goes;
#   8. Dolphin (the first home app here) alone on the left: its own tile, dimmed, asks for nothing;
#      the next one opens beside it;
# and no QML errors from the home screen, its picker or home.js.
# Run: tools/vsession/remote.sh fs-1 packages/plasmoids/org.plasmafusion.desktop/tests/vsession/scenario-freeside.sh SEED 1440x900 420
exec 2>&1
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
PLOG=$OUT/plasmashell.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
# A step that fails stops the scenario (strict mode); the reason lands in the checks.
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }

# The last answer the home screen logged ("none", or "right, 723 px from x 717 beside ...").
last_free() { grep -a 'home: free side:' "$PLOG" | tail -n 1 | sed 's/.*home: free side: //' || true; }
# LABEL PATTERN: the last answer matches the pattern (a case pattern) within 6 s.
expect_free() {
  local _
  for _ in $(seq 1 30); do
    # shellcheck disable=SC2254 # the pattern is the caller's
    case "$(last_free)" in $2) pass "$1: $(last_free)"; return 0 ;; esac
    sleep 0.2
  done
  fail "$1: the last free side answer is '$(last_free)'"
}
# The newest normal window whose class contains CLASS, active.
act() { # CLASS
  K run "var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('$1') >= 0) { w = l[i]; } }
    if (w) { workspace.activeWindow = w; } report(w ? String(w.resourceClass) : null);" >>"$OUT/act.log"
}
# The app active, then KWin's quick tile to SIDE (Left, Right), as the dock's split does.
tile() { # SIDE [CLASS]
  act "${2:-kwrite}"; sleep 0.6
  qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Window Quick Tile $1"
  sleep 1.5
}
# Split requests the home screen logged so far.
requests() { grep -ac 'home: split request:' "$PLOG" || true; }
# A tap 0.6 s after pfinput's start: the seat gains touch only when pfinput's touch device appears,
# and plasmashell binds wl_touch a moment later; a touch down sent before that never reaches it
# (WAYLAND_DEBUG, 2026-10-18: the up and frame arrived without the down), so the tap is lost.
tap() { pfinput 'sleep 0.6' "tap $1 $2 0.15" "${@:3}"; }
# The normal windows and the work area, as JSON.
state() { # NAME
  K run "var l = workspace.stackingOrder, out = [];
    for (var i = 0; i < l.length; ++i) { var c = l[i]; if (!c || c.deleted || !c.normalWindow) { continue; }
      var g = c.frameGeometry;
      out.push({cls: String(c.resourceClass), x: g.x, y: g.y, w: g.width, h: g.height, min: c.minimized}); }
    var a = workspace.clientArea(KWin.MaximizeArea, workspace.activeScreen, workspace.currentDesktop);
    report({wins: out, area: {x: a.x, y: a.y, w: a.width, h: a.height}});" >"$OUT/state-$1.json"
}

bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || info "fusion-config rc=$?"
kwriteconfig6 --file kwinrc --group Script-plasmafusion-snap --key Gap 6
kwriteconfig6 --file kwinrc --group Script-plasmafusion-tablet --key InternalOutputs "eDP,LVDS,DSI,Virtual"
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardShown true
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardVersion 99
pfv_restart_shell 12
qdbus org.kde.KWin /KWin reconfigure; sleep 3
pfv_tablet on; sleep 8

# ---- 1. the home screen with nothing open
shot fs-1-home
if grep -aq 'home: free side: \(left\|right\)' "$PLOG"; then fail "1: a free side with nothing open: $(last_free)"; else pass "1: no free side with nothing open"; fi

# ---- 2. KWrite open, maximized by the tablet policy
kwrite >/dev/null 2>&1 &
sleep 5
state 2
if grep -aq 'home: free side: \(left\|right\)' "$PLOG"; then fail "2: a free side beside a maximized app: $(last_free)"; else pass "2: no free side beside a maximized app"; fi

# ---- 3. KWrite to the left half, nothing else open: the right part offers the apps
tile Left
state 3
expect_free "3: KWrite on the left" "right, * beside *kwrite*"
sleep 1.5
shot fs-3-picker
K windows >"$OUT/windows-3.json"

# ---- 4. a tap on the first home app there (the second when the first is KWrite itself, dimmed)
read -r FX TOP <<<"$(python3 - "$OUT/state-3.json" "$(last_free)" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
m = re.search(r"from x (\d+)", sys.argv[2])
print(int(m.group(1)) if m else -1, d["area"]["y"])
PY
)"
info "free part from x $FX, work area top $TOP"
picked=""
for n in 0 1 2; do
  # A tile's icon centre: 40 px in, 128 px cells; 30 px top margin, the heading, the Home label.
  tx=$((FX + 40 + 64 + n * 128)); ty=$((TOP + 141))
  before=$(requests)
  tap "$tx" "$ty" 'sleep 0.3'; shot "fs-4-zoom-$n"; sleep 0.7
  after=$(requests)
  if [ "$after" -gt "$before" ]; then
    picked=$(grep -a 'home: split request:' "$PLOG" | tail -n 1 | sed 's/.*split request: //')
    break
  fi
  info "4: the tile at $tx,$ty asked for nothing (KWrite itself, or no tile)"
done
if [ -z "$picked" ]; then
  fail "4: no tap in the free part asked for an app"
else
  info "4: $picked"
  sleep 5
  state 4
  shot fs-4-pair
  python3 - "$OUT/state-4.json" "$picked" >>"$CHK" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1])); req = sys.argv[2]
app = re.sub(r"\.desktop$", "", req.split(" to the ")[0]).split(".")[-1].lower()
side = req.split(" to the ")[-1]
a = d["area"]; mid = a["x"] + a["w"] / 2
kw = [w for w in d["wins"] if "kwrite" in w["cls"] and not w["min"]]
new = [w for w in d["wins"] if app in w["cls"].lower() and "kwrite" not in w["cls"] and not w["min"]]
ok_side = side == "right"
ok_kw = len(kw) == 1 and kw[0]["x"] < mid and kw[0]["x"] + kw[0]["w"] <= mid + 8
ok_new = len(new) >= 1 and new[-1]["x"] >= mid - 8 and new[-1]["w"] < a["w"] * 0.6 and new[-1]["h"] > a["h"] * 0.9
print(("PASS" if ok_side and ok_kw and ok_new else "FAIL")
      + f" 4: {app} opened on the {side}, KWrite still on the left: kwrite {[(w['x'], w['w']) for w in kw]}, {app} {[(w['cls'], w['x'], w['y'], w['w'], w['h']) for w in new]}, area {a}")
PY
  expect_free "4: two apps side by side" "none"
  echo "$picked" >"$OUT/picked.txt"
fi

# ---- 5. that app closed: the free side comes back
if [ -n "$picked" ]; then
  cls=$(python3 -c 'import re,sys; print(re.sub(r"\.desktop$", "", sys.argv[1].split(" to the ")[0]).split(".")[-1].lower())' "$picked")
  K run "var l = workspace.windowList();
    for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).toLowerCase().indexOf('$cls') >= 0
        && String(l[i].resourceClass).indexOf('kwrite') < 0) { l[i].closeWindow(); } } report('closed');" >>"$OUT/act.log"
  sleep 3
  expect_free "5: the other app closed" "right, * beside *kwrite*"
fi

# ---- 6. KWrite to the right half: the left part is free
tile Right
state 6
expect_free "6: KWrite on the right" "left, * beside *kwrite*"
sleep 1
shot fs-6-left

# ---- 7. KWrite maximized: no free side
K maximize org.kde.kwrite >>"$OUT/act.log"
sleep 2
expect_free "7: KWrite maximized" "none"

# ---- 8. Dolphin alone on the left: its own tile is dimmed and asks for nothing; the next one works
K close org.kde.kwrite >>"$OUT/act.log"
dolphin >/dev/null 2>&1 &
sleep 5
tile Left dolphin
state 8
expect_free "8: Dolphin on the left" "right, * beside *dolphin*"
sleep 1.5
shot fs-8-dimmed
read -r FX TOP <<<"$(python3 - "$OUT/state-8.json" "$(last_free)" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
m = re.search(r"from x (\d+)", sys.argv[2])
print(int(m.group(1)) if m else -1, d["area"]["y"])
PY
)"
before=$(requests)
tap $((FX + 104)) $((TOP + 141)); sleep 1.5
if [ "$(requests)" = "$before" ]; then pass "8: Dolphin's own tile beside it asks for nothing"; else fail "8: Dolphin's own tile asked: $(grep -a 'home: split request:' "$PLOG" | tail -n 1)"; fi
tap $((FX + 232)) $((TOP + 141)); sleep 5
if [ "$(requests)" != "$before" ]; then
  state 8b
  python3 - "$OUT/state-8b.json" "$(grep -a 'home: split request:' "$PLOG" | tail -n 1 | sed 's/.*split request: //')" >>"$CHK" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1])); req = sys.argv[2]
app = re.sub(r"\.desktop$", "", req.split(" to the ")[0]).split(".")[-1].lower()
a = d["area"]; mid = a["x"] + a["w"] / 2
dol = [w for w in d["wins"] if "dolphin" in w["cls"] and not w["min"]]
new = [w for w in d["wins"] if app in w["cls"].lower() and "dolphin" not in w["cls"] and not w["min"]]
ok = len(dol) == 1 and dol[0]["x"] + dol[0]["w"] <= mid + 8 and len(new) >= 1 and new[-1]["x"] >= mid - 8
print(("PASS" if ok else "FAIL") + f" 8: the next tile ({app}) opened on the right beside Dolphin: dolphin {[(w['x'], w['w']) for w in dol]}, {app} {[(w['cls'], w['x'], w['w']) for w in new]}")
PY
else
  fail "8: the next tile asked for nothing"
fi

# No QML message names the home screen's files (errors, warnings, binding loops: the home screen's
# own log lines name no file).
errs=$(grep -a -E '(HomeLayer|FreeSidePicker)\.qml|home\.js' "$PLOG" || true)
if [ -z "$errs" ]; then pass "no QML messages about HomeLayer.qml, FreeSidePicker.qml or home.js"; else fail "QML messages: $(echo "$errs" | head -5 | tr '\n' ' ')"; fi
grep -a 'home: \(free side\|split request\)' "$PLOG" >"$OUT/freeside.log" || true
info "done"
