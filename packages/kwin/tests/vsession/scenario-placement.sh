#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Window placement memory (plasmafusion-placement) in a private session. The script is enabled like
# the Fusion setup leaves it and loaded by a reconfigure; then:
#   0. windows opened BEFORE the script is enabled are adopted: the script neither moves them nor
#      records them on loading (an earlier record stays), a later move is remembered, and closing
#      one without a move records where it was left;
#   1. a window is moved to a distinctive spot and closed - the memory file carries the entry;
#   2. reopening it gives the spot and the size back (the seed's Centered placement would put it at
#      the middle of the screen, so the two outcomes cannot be confused);
#   3. a record moved off every screen is not given back (the window lands on-screen by KWin);
#   4. a second window of the same app is not stacked exactly on the held spot, and when it moves
#      itself while it opens the held record stays;
#   5. IgnoreApps leaves that app alone (nothing recorded, nothing restored);
#   6. a window rule that forces the position wins: the window opens at the rule's spot and the
#      forced spot is not recorded;
#   7. a disable/enable cycle with a window open: the unloaded instance's geometry and maximize
#      handlers go with it (no errors from its context afterwards, also when the window is then
#      maximized and restored) and the new instance remembers the next move;
#   8. a window maximized by a script and closed keeps its floating place (issue #128: the commit
#      that answers a maximize request moves the frame before the maximize mode); the same for a
#      vertical-only maximize;
#   9. the same through KWin's own maximize operation (shortcut, title bar), with a restore in
#      between: the restored window floats where it was and that place is recorded again, a move
#      after it is remembered, a close while maximized keeps it;
#  10. an X11 window maximized and closed keeps its place (in a session with Xwayland; a session
#      asked for Xwayland (PFV_XWAYLAND=1) that has none fails the step, else it is skipped).
# Run: tools/vsession/remote.sh place-1 packages/kwin/tests/vsession/scenario-placement.sh SEED 1440x900 420
#      (PFV_XWAYLAND=1 in the environment runs step 10)
exec 2>&1
export OUT
# -E: the ERR trap below also fires for a command that fails inside a helper function (bash does
# not inherit it there otherwise, and the run would stop without its FAIL line).
set -Eeuo pipefail
set -x
CHK=$OUT/checks.txt
KLOG=$OUT/kwin.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
# A step that fails stops the scenario (strict mode); the reason lands in the checks, so a stopped
# run never reads as a clean one.
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }

# The newest normal window whose class contains CLASS, as "x y w h" (or "none").
geom() {
  K run "var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { var c = l[i]; if (c.normalWindow && String(c.resourceClass).indexOf('$1') >= 0) { w = c; } }
    if (w) { var g = w.frameGeometry; report([g.x, g.y, g.width, g.height]); } else { report(null); }" |
    python3 -c 'import json, sys; d = json.load(sys.stdin); print("none" if d is None else " ".join(str(int(round(v))) for v in d))'
}

place() { # CLASS X Y W H: untile, un-maximize and place the newest window of CLASS
  K run "var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { var c = l[i]; if (c.normalWindow && String(c.resourceClass).indexOf('$1') >= 0) { w = c; } }
    if (w) { if (w.tile) { w.tile.unmanage(w); } w.setMaximize(false, false);
      w.frameGeometry = {x: $2, y: $3, width: $4, height: $5}; workspace.activeWindow = w; }
    report(w ? String(w.resourceClass) : null);" >>"$OUT/place.log"
}

close_class() { # CLASS
  K run "var l = workspace.windowList(), n = 0;
    for (var i = 0; i < l.length; ++i) { if (String(l[i].resourceClass).indexOf('$1') >= 0) { l[i].closeWindow(); ++n; } }
    report(n);" >>"$OUT/close.log"
}

check_geom() { # CLASS X Y W H LABEL
  local got
  got=$(geom "$1")
  python3 - "$2" "$3" "$4" "$5" "$got" "$6" "$1" >>"$CHK" <<'PY'
import sys
wx, wy, ww, wh = (int(v) for v in sys.argv[1:5])
label, klass = sys.argv[6], sys.argv[7]
parts = sys.argv[5].split()
if parts == ["none"]:
    print(f"FAIL {label}: no {klass} window"); raise SystemExit
gx, gy, gw, gh = (int(v) for v in parts)
ok = abs(gx - wx) <= 1 and abs(gy - wy) <= 1 and abs(gw - ww) <= 1 and abs(gh - wh) <= 1
print(("PASS" if ok else "FAIL") + f" {label}: got {gx},{gy} {gw}x{gh}, wanted {wx},{wy} {ww}x{wh}")
PY
}

not_at() { # CLASS X Y LABEL: the newest window of CLASS is not at (X, Y) within 8 px
  local got
  got=$(geom "$1")
  python3 - "$2" "$3" "$got" "$4" "$1" >>"$CHK" <<'PY'
import sys
wx, wy = int(sys.argv[1]), int(sys.argv[2])
label, klass = sys.argv[4], sys.argv[5]
parts = sys.argv[3].split()
if parts == ["none"]:
    print(f"FAIL {label}: no {klass} window"); raise SystemExit
gx, gy = int(parts[0]), int(parts[1])
ok = abs(gx - wx) > 8 or abs(gy - wy) > 8
print(("PASS" if ok else "FAIL") + f" {label}: got {gx},{gy} (not {wx},{wy} either way)")
PY
}

check_pos() { # CLASS X Y LABEL: the newest window of CLASS is at (X, Y) within 8 px
  local got
  got=$(geom "$1")
  python3 - "$2" "$3" "$got" "$4" "$1" >>"$CHK" <<'PY'
import sys
wx, wy = int(sys.argv[1]), int(sys.argv[2])
label, klass = sys.argv[4], sys.argv[5]
parts = sys.argv[3].split()
if parts == ["none"]:
    print(f"FAIL {label}: no {klass} window"); raise SystemExit
gx, gy = int(parts[0]), int(parts[1])
ok = abs(gx - wx) <= 8 and abs(gy - wy) <= 8
print(("PASS" if ok else "FAIL") + f" {label}: got {gx},{gy}, wanted {wx},{wy}")
PY
}

# win_js CLASS JS: run JS with w = the newest open normal window whose class contains CLASS (null
# when there is none); JS calls report() once.
win_js() {
  K run "var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { var c = l[i]; if (c.normalWindow && !c.deleted && String(c.resourceClass).indexOf('$1') >= 0) { w = c; } }
    $2"
}

# The newest window of CLASS as one line for the checks: maximize mode, tile and frame.
state() { # CLASS
  win_js "$1" "if (!w) { report(null); } else { var g = w.frameGeometry;
    report({ max: w.maximizeMode, tiled: !!w.tile, frame: [g.x, g.y, g.width, g.height] }); }" | tr -d ' \n'
}

check_max() { # CLASS MODE LABEL: the newest window of CLASS has that maximize mode (0 restored, 3 full)
  local st
  st=$(state "$1")
  python3 - "$st" "$2" "$3" >>"$CHK" <<'PY'
import json, sys
s = json.loads(sys.argv[1])
ok = bool(s) and s["max"] == int(sys.argv[2])
print(("PASS" if ok else "FAIL") + f" {sys.argv[3]}: {sys.argv[1]}")
PY
}

app_record() { # APP_ID -> the app's record as "x y w h", or none
  kreadconfig6 --file "$HOME/.config/plasmafusion-placementrc" --group Windows --key windows 2>/dev/null |
    python3 -c 'import json, sys
try: r = json.load(sys.stdin).get("apps", {}).get(sys.argv[1])
except Exception: r = None
print("none" if not r else "%d %d %d %d" % (r["x"], r["y"], r["width"], r["height"]))' "$1"
}

check_record() { # APP_ID "X Y W H" LABEL: the app's record is exactly that rectangle, read once (a
  # write is coalesced for about 2 s: a caller that expects NO change waits 4 s before this)
  local got
  got=$(app_record "$1")
  [ "$got" = "$2" ] && pass "$3 (record $got)" || fail "$3: record $got, wanted $2"
}

wait_app_record() { # APP_ID "X Y W H" LABEL: the app's record becomes that rectangle (polls past the
  # coalesced write)
  local _
  for _ in $(seq 1 10); do
    if [ "$(app_record "$1")" = "$2" ]; then pass "$3 (record $2)"; return 0; fi
    sleep 1
  done
  fail "$3: record $(app_record "$1"), wanted $2"
}

on_screen() { # CLASS LABEL: the newest window's centre lies on the 1440x900 screen
  local got
  got=$(geom "$1")
  python3 - "$got" "$2" >>"$CHK" <<'PY'
import sys
parts = sys.argv[1].split()
label = sys.argv[2]
if parts == ["none"]:
    print(f"FAIL {label}: no window"); raise SystemExit
gx, gy, gw, gh = (int(v) for v in parts)
cx, cy = gx + gw / 2, gy + gh / 2
ok = -1 <= cx <= 1441 and -1 <= cy <= 901
print(("PASS" if ok else "FAIL") + f" {label}: centre {cx:.0f},{cy:.0f} on the 1440x900 screen")
PY
}

file_has_rect() { # X Y W H -> exit 0 when some app entry matches
  kreadconfig6 --file "$HOME/.config/plasmafusion-placementrc" --group Windows --key windows 2>/dev/null |
    python3 -c 'import json, sys
want = tuple(int(v) for v in sys.argv[1:5])
try: apps = json.load(sys.stdin).get("apps", {})
except Exception: apps = {}
sys.exit(0 if any((v.get("x"), v.get("y"), v.get("width"), v.get("height")) == want for v in apps.values()) else 1)' "$1" "$2" "$3" "$4"
}

wait_file_rect() { # X Y W H LABEL: a write is coalesced (~2 s), so poll before judging
  for _ in $(seq 1 10); do
    if file_has_rect "$1" "$2" "$3" "$4"; then pass "$5: the memory file carries the entry"; return 0; fi
    sleep 1
  done
  fail "$5: the memory file did not carry the entry"
}

memory_is() { # JSON LABEL: the memory file's apps are exactly JSON (polls past a coalesced write)
  local _
  for _ in $(seq 1 6); do
    if kreadconfig6 --file "$HOME/.config/plasmafusion-placementrc" --group Windows --key windows |
      python3 -c 'import json, sys
want = json.loads(sys.argv[1])
try: apps = json.load(sys.stdin).get("apps", {})
except Exception: apps = {}
sys.exit(0 if apps == want else 1)' "$1"; then
      pass "$2"; return 0
    fi
    sleep 1
  done
  fail "$2: the memory is $(kreadconfig6 --file "$HOME/.config/plasmafusion-placementrc" --group Windows --key windows)"
}

# ---- the memory as an earlier session left it: a Konsole record at a spot of its own
R0='{"org.kde.konsole":{"x":300,"y":200,"width":520,"height":380}}'
kwriteconfig6 --file plasmafusion-placementrc --group Windows --key windows "{\"v\":1,\"apps\":$R0}"

# ---- windows opened before the script is enabled (how a Fusion setup finds a running session):
# they must be adopted - watched, never moved or recorded by the script on loading - and their
# later moves and closes remembered.
konsole >/dev/null 2>&1 &
sleep 4
kwrite >/dev/null 2>&1 &
sleep 4
KG=$(geom konsole)
WG=$(geom kwrite)
info "opened before the script: konsole $KG, kwrite $WG"
[ "$KG" != none ] && [ "$WG" != none ] && pass "both windows opened before the script" ||
  fail "a window did not open before the script (konsole $KG, kwrite $WG)"

# ---- the script, enabled like the Fusion setup leaves it and loaded by the reconfigure
fc_rc=0
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || fc_rc=$?
info "fusion-config rc=$fc_rc"
# The settings the tests need (read per decision by the running script, so the same reconfigure
# that loads the script makes IgnoreApps live).
kwriteconfig6 --file kwinrc --group Plugins --key plasmafusion-placementEnabled true
kwriteconfig6 --file kwinrc --group Script-plasmafusion-placement --key IgnoreApps kcalc
qdbus org.kde.KWin /KWin reconfigure
sleep 3
loaded=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-placement)
[ "$loaded" = "true" ] && pass "the placement script is loaded" || fail "the placement script is not loaded"
grep -a 'plasmafusion-placement' "$KLOG" | tail -3 >>"$CHK" 2>/dev/null || true

# ---- 0. the windows that predated the script: adopted, not moved, nothing recorded on loading
# (the settling pass and a write would have run within 3 s)
sleep 4
# shellcheck disable=SC2086 # KG/WG are "x y w h"
check_geom konsole $KG "an adopted window is not moved by the script"
# shellcheck disable=SC2086
check_geom kwrite $WG "the other adopted window is not moved either"
memory_is "$R0" "loading records nothing from the adopted windows (the earlier Konsole record stays)"

# an adopted window's move is remembered
place konsole 233 171 500 400
sleep 1
check_geom konsole 233 171 500 400 "the pre-existing window sits where it was placed"
wait_file_rect 233 171 500 400 "the pre-existing window was adopted (its move was remembered)"
close_class konsole
sleep 2
# an adopted window closed without a move: its place at close is the record
close_class kwrite
sleep 1
# shellcheck disable=SC2086
wait_file_rect $WG "an adopted window closed unmoved is recorded where it was left"
shot 00-adopted

# ---- 1. the write path: a placed window's rectangle lands in the memory file
kwrite >/dev/null 2>&1 &
sleep 4
info "kwrite opened: $(geom kwrite)"
place kwrite 137 93 640 420
sleep 1
check_geom kwrite 137 93 640 420 "the window sits where it was placed"
wait_file_rect 137 93 640 420 "the placed rectangle was written"
info "memory: $(kreadconfig6 --file "$HOME/.config/plasmafusion-placementrc" --group Windows --key windows)"
shot 10-placed
close_class kwrite
sleep 2
[ "$(geom kwrite)" = "none" ] && pass "the window closed" || fail "the window did not close"

# ---- 2. the restore path: it comes back to the remembered spot and size
kwrite >/dev/null 2>&1 &
sleep 4
check_geom kwrite 137 93 640 420 "the reopened window comes back to the remembered spot"
shot 20-restored
grep -a 'plasmafusion-placement: restored' "$KLOG" | tail -2 >>"$CHK" 2>/dev/null || true

# ---- 3. a record moved off every screen is not given back
place kwrite 5000 300 640 420
sleep 3
close_class kwrite
sleep 2
kwrite >/dev/null 2>&1 &
sleep 4
not_at kwrite 5000 300 "the off-screen spot is not given back"
on_screen kwrite "the reopened window is placed on a screen by KWin"
shot 30-offscreen-skipped
info "memory: $(kreadconfig6 --file "$HOME/.config/plasmafusion-placementrc" --group Windows --key windows)"

# ---- 4. the stack guard: a second instance is not stacked exactly on the held spot, and its own
# geometry changes while it opens (an app positioning itself) do not replace the held record. The
# move is made by a test script after the windowAdded emission - a JS script's handler would run
# before the placement script's, so the change goes through an async D-Bus round trip first.
place kwrite 137 93 640 420
sleep 3
K run "workspace.windowAdded.connect(function (w) {
    if (!w.normalWindow || String(w.resourceClass).indexOf('kwrite') < 0) { return; }
    callDBus('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'GetId', function () {
      // copy the numbers: frameGeometry is a value-type reference that reads through after the move
      var g = w.frameGeometry, x = g.x, y = g.y, width = g.width, height = g.height;
      w.frameGeometry = {x: x + 40, y: y + 30, width: width, height: height};
      report({opened: [x, y], moved: [x + 40, y + 30]});
    });
  });" >"$OUT/selfmove.json" &
selfmove=$!
sleep 1
kwrite >/dev/null 2>&1 &
wait "$selfmove"
info "the second instance moved itself while opening: $(tr -d ' \n' <"$OUT/selfmove.json")"
sleep 4
K run "var l = workspace.windowList(), out = [];
  for (var i = 0; i < l.length; ++i) { var c = l[i]; if (c.normalWindow && String(c.resourceClass).indexOf('kwrite') >= 0) { var g = c.frameGeometry; out.push({x: g.x, y: g.y, w: g.width, h: g.height}); } }
  report(out);" >"$OUT/kwrite-pair.json"
python3 - "$OUT/kwrite-pair.json" >>"$CHK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
if len(d) != 2:
    print(f"FAIL the second instance keeps KWin's placement: expected two windows, got {d}"); raise SystemExit
spot = [w for w in d if abs(w["x"] - 137) <= 8 and abs(w["y"] - 93) <= 8]
stacked = [w for w in d if w not in spot and spot and abs(w["x"] - spot[0]["x"]) <= 8 and abs(w["y"] - spot[0]["y"]) <= 8]
print(("PASS" if len(spot) == 1 and not stacked else "FAIL") + f" the second instance keeps KWin's placement ({d})")
PY
python3 - >>"$CHK" <<'PY'
import json, os, subprocess
text = subprocess.run(["kreadconfig6", "--file", os.path.expanduser("~/.config/plasmafusion-placementrc"), "--group", "Windows", "--key", "windows"], capture_output=True, text=True).stdout
try:
    got = json.loads(text).get("apps", {}).get("org.kde.kwrite")
except Exception:
    got = None
want = {"x": 137, "y": 93, "width": 640, "height": 420}
print(("PASS" if got == want else "FAIL") + f" the held record stays while the second instance moves itself (kwrite {got})")
PY
shot 40-pair
close_class kwrite
sleep 3

# ---- 5. IgnoreApps: kcalc is left alone
kcalc >/dev/null 2>&1 &
sleep 4
info "kcalc opened: $(geom kcalc)"
place kcalc 301 217 480 400
sleep 3
close_class kcalc
sleep 2
kcalc >/dev/null 2>&1 &
sleep 4
not_at kcalc 301 217 "the ignored app is not given the moved spot back"
python3 - >>"$CHK" <<'PY'
import json, os, subprocess
text = subprocess.run(["kreadconfig6", "--file", os.path.expanduser("~/.config/plasmafusion-placementrc"), "--group", "Windows", "--key", "windows"], capture_output=True, text=True).stdout
try:
    apps = json.loads(text).get("apps", {})
except Exception:
    apps = {}
hits = [k for k, v in apps.items() if v.get("x") == 301]
print(("PASS" if not hits else "FAIL") + f" the ignored app was never recorded (entries {sorted(apps)})")
PY
shot 50-ignored-open
close_class kcalc
sleep 1

# ---- 6. a window rule that forces the position wins over the memory
kwrite >/dev/null 2>&1 &
sleep 4
place kwrite 137 93 640 420
sleep 3
close_class kwrite
sleep 2
wait_file_rect 137 93 640 420 "the record before the rule"
# KWin's rule format (src/rulesettings.kcfg): positionrule 2 = Force, wmclassmatch 2 = substring.
printf '%s\n' '[General]' 'count=1' 'rules=pfplace' '' '[pfplace]' 'Description=placement test' \
  'position=50,50' 'positionrule=2' 'wmclass=kwrite' 'wmclassmatch=2' >"$HOME/.config/kwinrulesrc"
qdbus org.kde.KWin /KWin reconfigure
sleep 2
kwrite >/dev/null 2>&1 &
sleep 4
check_pos kwrite 50 50 "the forced position wins over the remembered spot"
shot 60-rule
close_class kwrite
sleep 3
wait_file_rect 137 93 640 420 "the forced spot is not recorded (the record stays)"
rm -f "$HOME/.config/kwinrulesrc"
qdbus org.kde.KWin /KWin reconfigure

# ---- 7. a disable/enable cycle with a window open (KWin keeps one QML engine for its scripts; a
# handler the unloaded instance left on the window would call into its destroyed context)
kwrite >/dev/null 2>&1 &
sleep 4
script_errors() { grep -a 'plasmafusion-placement' "$KLOG" | grep -acE 'Error|error:' || true; }
errors_before=$(script_errors)
kwriteconfig6 --file kwinrc --group Plugins --key plasmafusion-placementEnabled false
qdbus org.kde.KWin /KWin reconfigure
sleep 2
loaded=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-placement)
[ "$loaded" = false ] && pass "disabled: the script is unloaded" || fail "disabled: the script is still loaded ($loaded)"
kwriteconfig6 --file kwinrc --group Plugins --key plasmafusion-placementEnabled true
qdbus org.kde.KWin /KWin reconfigure
sleep 3
loaded=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-placement)
[ "$loaded" = true ] && pass "enabled again: the script is loaded" || fail "enabled again: the script is not loaded ($loaded)"
place kwrite 311 151 600 400
sleep 1
place kwrite 329 163 600 400
sleep 1
wait_file_rect 329 163 600 400 "a move after the cycle is remembered by the new instance"
# the window the unloaded instance watched is maximized and restored: a maximize handler it left
# connected would call into its destroyed context now
win_js kwrite "if (w) { workspace.activeWindow = w; workspace.slotWindowMaximize(); } report(!!w);" >>"$OUT/place.log"
sleep 3
check_max kwrite 3 "the window that lived through the cycle is maximized"
win_js kwrite "if (w) { workspace.activeWindow = w; workspace.slotWindowMaximize(); } report(!!w);" >>"$OUT/place.log"
sleep 3
check_max kwrite 0 "and restored"
check_record org.kde.kwrite "329 163 600 400" "the record after the maximize and restore is the floating place"
errors_after=$(script_errors)
[ "$errors_after" = "$errors_before" ] && pass "no errors from the unloaded instance's handlers ($errors_after before and after)" ||
  fail "the unloaded instance's handlers raised errors ($errors_before before, $errors_after after)"
grep -a 'plasmafusion-placement' "$KLOG" | grep -aE 'Error|error:' | tail -4 >>"$CHK" || true
close_class kwrite
sleep 2

# ---- 8. maximized by a script and closed: the floating place stays (issue #128). The commit with
# which a Wayland client answers a maximize request updates the frame before the maximize mode
# (KWin 6.7.5, xdgshellwindow.cpp handleCommit), so the first frame change after the request
# already has the maximized frame while maximizeMode still reads 0; the script mirrors the mode
# KWin asked for from maximizedAboutToChange. The step records what that signal delivers.
kwrite >/dev/null 2>&1 &
sleep 4
place kwrite 205 145 600 400
sleep 1
wait_file_rect 205 145 600 400 "8. the floating place before the maximize"
seen=$(win_js kwrite "var seen = null; if (w) { var f = function (m) { seen = { type: typeof m, mode: m }; w.maximizedAboutToChange.disconnect(f); };
  w.maximizedAboutToChange.connect(f); w.setMaximize(true, true); } report(seen);" | tr -d ' \n')
info "8. maximizedAboutToChange with the request: $seen"
sleep 4
check_max kwrite 3 "8. the window took the maximize"
check_record org.kde.kwrite "205 145 600 400" "8. the maximized frame is not recorded"
close_class kwrite
sleep 4
check_record org.kde.kwrite "205 145 600 400" "8. closed while maximized: the floating place kept"
shot 80-maximized-closed
# the same for a vertical-only maximize (mode 1)
kwrite >/dev/null 2>&1 &
sleep 4
place kwrite 217 151 590 395
sleep 1
wait_file_rect 217 151 590 395 "8. the floating place before the vertical maximize"
win_js kwrite "if (w) { w.setMaximize(true, false); } report(!!w);" >>"$OUT/place.log"
sleep 4
check_max kwrite 1 "8. the window took the vertical maximize"
check_record org.kde.kwrite "217 151 590 395" "8. the vertically maximized frame is not recorded"
close_class kwrite
sleep 4
check_record org.kde.kwrite "217 151 590 395" "8. closed while vertically maximized: the floating place kept"

# ---- 9. KWin's own maximize operation - the Meta+PgUp shortcut, the title bar's button and its
# double click all run Workspace::performWindowOperation(MaximizeOp) - then a restore: the window
# floats where it was and the state that settles the restore records that place again (a second
# window of the app set the record to its own place in between); a move after the restore is
# remembered; a close while maximized keeps the place.
kwrite >/dev/null 2>&1 &
sleep 4
place kwrite 229 157 580 390
sleep 1
wait_file_rect 229 157 580 390 "9. the floating place before the operation"
win_js kwrite "if (w) { workspace.activeWindow = w; workspace.slotWindowMaximize(); } report(!!w);" >>"$OUT/place.log"
sleep 4
check_max kwrite 3 "9. the operation maximized the window"
check_record org.kde.kwrite "229 157 580 390" "9. the operation's maximized frame is not recorded"
# the second window takes the record to its own place and goes
kwrite >/dev/null 2>&1 &
sleep 4
place kwrite 253 181 580 390
sleep 1
wait_file_rect 253 181 580 390 "9. a second window's place is the record meanwhile"
win_js kwrite "if (w) { w.closeWindow(); } report(!!w);" >>"$OUT/close.log"
sleep 4
check_record org.kde.kwrite "253 181 580 390" "9. the second window's place stays after its close"
win_js kwrite "if (w) { workspace.activeWindow = w; workspace.slotWindowMaximize(); } report(!!w);" >>"$OUT/place.log"
sleep 3
check_max kwrite 0 "9. the operation restored the window"
check_geom kwrite 229 157 580 390 "9. the restored window floats where it was"
wait_app_record org.kde.kwrite "229 157 580 390" "9. the restore records the floating place again"
place kwrite 241 169 580 390
sleep 1
wait_file_rect 241 169 580 390 "9. a move after the restore is remembered"
win_js kwrite "if (w) { workspace.activeWindow = w; workspace.slotWindowMaximize(); } report(!!w);" >>"$OUT/place.log"
sleep 3
check_max kwrite 3 "9. maximized again by the operation"
close_class kwrite
sleep 4
check_record org.kde.kwrite "241 169 580 390" "9. closed while maximized by the operation: the floating place kept"
shot 90-operation

# ---- 10. an X11 window (Xwayland; only in a session started with PFV_XWAYLAND=1): KWin sets the
# mode before it moves the frame, so the place was always kept there; the check guards that order.
if [ -n "${DISPLAY:-}" ]; then
  QT_QPA_PLATFORM=xcb kwrite >/dev/null 2>&1 &
  sleep 4
  info "10. X11 window: $(state kwrite)"
  place kwrite 265 193 560 380
  sleep 1
  wait_file_rect 265 193 560 380 "10. the X11 window's floating place"
  win_js kwrite "if (w) { w.setMaximize(true, true); } report(!!w);" >>"$OUT/place.log"
  sleep 4
  check_max kwrite 3 "10. the X11 window took the maximize"
  check_record org.kde.kwrite "265 193 560 380" "10. the X11 maximized frame is not recorded"
  close_class kwrite
  sleep 4
  check_record org.kde.kwrite "265 193 560 380" "10. the X11 window closed while maximized: the floating place kept"
elif [ "${PFV_XWAYLAND:-0}" = 1 ]; then
  fail "10. the session was asked for Xwayland (PFV_XWAYLAND=1) but has no DISPLAY: the X11 step could not run"
else
  info "10. X11 step skipped: no Xwayland in this session (PFV_XWAYLAND=1 runs it)"
fi

cp "$HOME/.config/plasmafusion-placementrc" "$OUT/memory-final.rc" 2>/dev/null || true
info "memory file saved to memory-final.rc"
info "placement log lines:"; grep -a 'plasmafusion-placement' "$KLOG" | tail -15 >>"$CHK" 2>/dev/null || true
# The verdict: every check runs (a red run lists each failing behaviour), and the scenario's own
# status says whether any failed - the session log keeps it as "scenario rc". remote.sh's status
# stays what its header says (the session ran and the results were fetched).
failed=$(grep -c '^FAIL' "$CHK" || true)
info "verdict: $(grep -c '^PASS' "$CHK" || true) passed, $failed failed"
info "done"
trap - ERR
set +e
[ "$failed" = 0 ]
