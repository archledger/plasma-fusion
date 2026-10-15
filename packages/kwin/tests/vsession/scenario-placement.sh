#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Window placement memory (plasmafusion-placement) in a private session. The script is enabled like
# the Fusion setup leaves it and loaded by a reconfigure; then:
#   1. a window is moved to a distinctive spot and closed - the memory file carries the entry;
#   2. reopening it gives the spot and the size back (the seed's Centered placement would put it at
#      the middle of the screen, so the two outcomes cannot be confused);
#   3. a record moved off every screen is not given back (the window lands on-screen by KWin);
#   4. a second window of the same app is not stacked exactly on the held spot;
#   5. IgnoreApps leaves that app alone (nothing recorded, nothing restored).
# Run: tools/vsession/remote.sh place-1 packages/kwin/tests/vsession/scenario-placement.sh SEED 1440x900 300
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

# ---- the script, enabled like the Fusion setup leaves it and loaded by the reconfigure
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1
info "fusion-config rc=$?"
# The settings the tests need (read per decision by the running script, so the same reconfigure
# that loads the script makes IgnoreApps live).
kwriteconfig6 --file kwinrc --group Plugins --key plasmafusion-placementEnabled true
kwriteconfig6 --file kwinrc --group Script-plasmafusion-placement --key IgnoreApps kcalc
qdbus org.kde.KWin /KWin reconfigure
sleep 3
loaded=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-placement)
[ "$loaded" = "true" ] && pass "the placement script is loaded" || fail "the placement script is not loaded"
grep -a 'plasmafusion-placement' "$KLOG" | tail -3 >>"$CHK" 2>/dev/null || true

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

# ---- 4. the stack guard: a second instance is not stacked exactly on the held spot
place kwrite 137 93 640 420
sleep 3
kwrite >/dev/null 2>&1 &
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

cp "$HOME/.config/plasmafusion-placementrc" "$OUT/memory-final.rc" 2>/dev/null || true
info "memory file saved to memory-final.rc"
info "placement log lines:"; grep -a 'plasmafusion-placement' "$KLOG" | tail -15 >>"$CHK" 2>/dev/null || true
info "done"
