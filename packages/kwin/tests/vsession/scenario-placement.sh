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
#      forced spot is not recorded.
# Run: tools/vsession/remote.sh place-1 packages/kwin/tests/vsession/scenario-placement.sh SEED 1440x900 300
exec 2>&1
export OUT
set -euo pipefail
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
