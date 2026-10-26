#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Window placement memory and a late tile-sized commit (KDE bug 527821), in a private session. The
# window is tools/tests/lib/heldclient.py, whose answers to configure events the scenario controls
# (xdg-shell lets a client acknowledge a configure and commit later; ordinary apps answer at once):
#   1. the window floats at A and is remembered there;
#   2. it is tiled (Tile.manage), acknowledges the tile's configure without committing, is untiled
#      (Tile.unmanage) and only then commits the tile-sized frame, and closes before answering the
#      untile's configure. On a KWin with Window.requestedGeometry the memory keeps A. On a KWin
#      without it the script cannot tell the frame from a floating one and records the tile size:
#      reported as INFO, the limit the property removes;
#   3. the same tile and untile with a client that answers at once: the window floats at A again,
#      the memory keeps A, and a later move is remembered (settled frames are still recorded);
#   4. a maximize and then a restore requested before the client answers either, and the client
#      answers the restore only (acknowledging a configure supersedes the earlier ones), so KWin
#      never reports a maximize mode change: the window floats at A, the memory keeps A, and a
#      later move is remembered - the requested mode the script mirrors is not left pending;
#   5. the client asks to be maximized itself (xdg_toplevel.set_maximized), answers at once, asks to
#      be restored (unset_maximized: back at A, A recorded again), asks to be maximized once more
#      and closes maximized: the memory keeps A (issue #128 through the client's own requests);
#   6. a restore and then a maximize requested on a maximized window before the client answers
#      either, answered one by one: the restore's commit is taken first (KWin reports the restored
#      mode), then the maximize's commit brings the maximized frame while the mode still reads
#      restored - the mirrored request must still say maximized, so nothing is recorded; a close
#      then keeps A.
# Run: tools/vsession/remote.sh place-pending packages/kwin/tests/vsession/scenario-placement-pending.sh SEED 1440x900 360
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
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }
APP=org.plasmafusion.heldclient
# The held window, found by its app id (its window class on Wayland).
FIND="var l = workspace.windowList(), w = null;
  for (var i = 0; i < l.length; ++i) { var c = l[i]; if (c.normalWindow && !c.deleted && String(c.resourceClass) === '$APP') { w = c; } }"

geom() { # "x y w h" of the held window, or "none"
  K run "$FIND if (w) { var g = w.frameGeometry; report([g.x, g.y, g.width, g.height]); } else { report(null); }" |
    python3 -c 'import json, sys; d = json.load(sys.stdin); print("none" if d is None else " ".join(str(int(round(v))) for v in d))'
}

# The window's state as one line for the checks: tile, frame and (where KWin has it) requested.
state() {
  K run "$FIND if (!w) { report(null); } else { var g = w.frameGeometry, r = w.requestedGeometry;
    report({ tiled: !!w.tile, max: w.maximizeMode, frame: [g.x, g.y, g.width, g.height], requested: r ? [r.x, r.y, r.width, r.height] : null }); }"
}

place() { # X Y W H
  K run "$FIND if (w) { if (w.tile) { w.tile.unmanage(w); } w.setMaximize(false, false);
    w.frameGeometry = {x: $1, y: $2, width: $3, height: $4}; workspace.activeWindow = w; }
    report(w ? true : null);" >>"$OUT/place.log"
}

tile() { # manage the held window in the first leaf of its custom tiling layout
  K run "$FIND if (!w) { report(null); } else { var t = workspace.rootTile(w.output, w.desktops[0]);
    while (t.tiles.length > 0) { t = t.tiles[0]; } report(t.manage(w)); }"
}

untile() {
  K run "$FIND if (!w || !w.tile) { report(null); } else { report(w.tile.unmanage(w)); }"
}

memory() { kreadconfig6 --file "$HOME/.config/plasmafusion-placementrc" --group Windows --key windows 2>/dev/null || true; }

record_is() { # X Y W H -> exit 0 when the held app's record is exactly that rectangle
  memory | python3 -c 'import json, sys
want = dict(zip(("x", "y", "width", "height"), (int(v) for v in sys.argv[2:6])))
try: apps = json.load(sys.stdin).get("apps", {})
except Exception: apps = {}
sys.exit(0 if apps.get(sys.argv[1]) == want else 1)' "$APP" "$1" "$2" "$3" "$4"
}

wait_record() { # X Y W H LABEL: a write is coalesced (~2 s), so poll before judging
  for _ in $(seq 1 10); do
    if record_is "$1" "$2" "$3" "$4"; then pass "$5"; return 0; fi
    sleep 1
  done
  fail "$5: the memory is $(memory)"
}

# ---- the held client: commands go through a FIFO kept open on fd 7, events land in a log
held_start() { # LABEL
  HELD_LOG=$OUT/held-$1.log
  mkfifo "$OUT/held-$1.in"
  python3 "$HOME/pf-tools/tests/lib/heldclient.py" "$APP" 430x310 <"$OUT/held-$1.in" >"$HELD_LOG" 2>"$OUT/held-$1.err" &
  HELD_PID=$!
  exec 7>"$OUT/held-$1.in"
}
send() { echo "$1" >&7; }
held_stop() {
  exec 7>&-
  for _ in $(seq 1 10); do kill -0 "$HELD_PID" 2>/dev/null || break; sleep 0.5; done
  kill "$HELD_PID" 2>/dev/null || true
  wait "$HELD_PID" 2>/dev/null || true
}
configures() { grep -c '"event": "configure"' "$HELD_LOG" || true; }
# The newest configure as "serial width height", once there are more than N.
wait_configure() { # N
  for _ in $(seq 1 20); do
    if [ "$(configures)" -gt "$1" ]; then
      grep '"event": "configure"' "$HELD_LOG" | tail -n 1 |
        python3 -c 'import json, sys; e = json.load(sys.stdin); print(e["serial"], e["width"], e["height"])'
      return 0
    fi
    sleep 0.25
  done
  echo none
}

# ---- the script, enabled like the Fusion setup leaves it; an empty memory
kwriteconfig6 --file plasmafusion-placementrc --group Windows --key windows '{"v":1,"apps":{}}'
fc_rc=0
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || fc_rc=$?
info "fusion-config rc=$fc_rc"
kwriteconfig6 --file kwinrc --group Plugins --key plasmafusion-placementEnabled true
qdbus org.kde.KWin /KWin reconfigure
sleep 3
loaded=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-placement)
[ "$loaded" = "true" ] && pass "the placement script is loaded" || fail "the placement script is not loaded"

# ---- 1. the window floats at A and is remembered there
held_start first
sleep 3
[ "$(geom)" != none ] && pass "the held window opened" || fail "the held window did not open ($(cat "$OUT/held-first.err"))"
has=$(K run "$FIND report(w ? (w.requestedGeometry !== undefined) : null)")
info "KWin has Window.requestedGeometry: $has ($(rpm -q kwin 2>/dev/null || true))"
place 73 91 430 310
wait_record 73 91 430 310 "1. the floating window is remembered at A"

# ---- 2. tiled, the tile's configure acknowledged but not committed, untiled, then the late
# tile-sized commit, and the window closes before answering the untile's configure
send hold
n=$(configures)
info "tile: $(tile)"
read -r sb wb hb < <(wait_configure "$n")
info "the tile's configure: serial $sb, ${wb}x$hb"
[ "$sb" != none ] && [ "$wb" != 430 ] && pass "2. tiling sends a configure with the tile's size" ||
  fail "2. no tile-sized configure (serial $sb, ${wb}x$hb)"
send "ack $sb"
n=$(configures)
info "untile: $(untile)"
read -r sa wa ha < <(wait_configure "$n")
info "the untile's configure: serial $sa, ${wa}x$ha"
[ "$sa" != none ] && [ "$wa" = 430 ] && [ "$ha" = 310 ] && pass "2. untiling sends a configure for A's size" ||
  fail "2. no configure for A's size after the untile (serial $sa, ${wa}x$ha)"
send commit
sleep 1
st=$(state)
info "after the late commit: $st"
python3 -c 'import json, sys; s = json.loads(sys.argv[1]); w, h = int(sys.argv[2]), int(sys.argv[3])
ok = s and not s["tiled"] and round(s["frame"][2]) == w and round(s["frame"][3]) == h
print(("PASS" if ok else "FAIL") + f" 2. the untiled window shows the tile-sized frame: {s}")' "$st" "$wb" "$hb" >>"$CHK"
send quit
held_stop
sleep 4
info "the memory after the close: $(memory)"
if [ "$has" = true ]; then
  if record_is 73 91 430 310; then
    pass "2. with requestedGeometry the late tile-sized frame is not recorded (the memory keeps A)"
  else
    fail "2. with requestedGeometry the memory should keep A: $(memory)"
  fi
elif record_is 73 91 430 310; then
  info "2. without requestedGeometry the memory kept A"
else
  info "2. without requestedGeometry the tile-sized frame was recorded (the limit the property removes)"
fi

# ---- 3. tile and untile with a client that answers at once: back at A, A kept, a move remembered
held_start second
sleep 3
place 73 91 430 310
wait_record 73 91 430 310 "3. the second window is remembered at A"
info "tile: $(tile)"
sleep 2
info "tiled: $(state)"
info "untile: $(untile)"
sleep 2
st=$(state)
info "untiled: $st"
python3 -c 'import json, sys; s = json.loads(sys.argv[1])
ok = s and not s["tiled"] and [round(v) for v in s["frame"]] == [73, 91, 430, 310]
print(("PASS" if ok else "FAIL") + f" 3. the untiled window floats at A again: {s}")' "$st" >>"$CHK"
wait_record 73 91 430 310 "3. after the tile and untile the memory keeps A"
place 97 113 430 310
wait_record 97 113 430 310 "3. a later move is remembered"
send quit
held_stop
sleep 3
record_is 97 113 430 310 && pass "3. the close keeps the settled record" || fail "3. the close changed the record: $(memory)"

# ---- 4. a maximize and a restore requested while the client holds its answers, then the restore
# answered alone: the window never shows the maximize and KWin's maximize mode never changes
held_start third
sleep 3
place 73 91 430 310
wait_record 73 91 430 310 "4. the third window is remembered at A"
send hold
n=$(configures)
K run "$FIND if (w) { w.setMaximize(true, true); } report(!!w);" >>"$OUT/place.log"
read -r sm wm hm < <(wait_configure "$n")
info "4. the maximize's configure: serial $sm, ${wm}x$hm"
[ "$sm" != none ] && [ "$wm" != 430 ] && pass "4. the maximize sends a configure with the maximized size" ||
  fail "4. no maximized configure (serial $sm, ${wm}x$hm)"
n=$(configures)
K run "$FIND if (w) { w.setMaximize(false, false); } report(!!w);" >>"$OUT/place.log"
read -r sr wr hr < <(wait_configure "$n")
info "4. the restore's configure: serial $sr, ${wr}x$hr"
[ "$sr" != none ] && [ "$wr" = 430 ] && [ "$hr" = 310 ] && pass "4. the restore sends a configure for A's size" ||
  fail "4. no configure for A's size after the restore (serial $sr, ${wr}x$hr)"
send "ack $sr"
send commit
sleep 2
st=$(state)
info "4. after answering the restore only: $st"
python3 -c 'import json, sys; s = json.loads(sys.argv[1])
ok = s and not s["tiled"] and s["max"] == 0 and [round(v) for v in s["frame"]] == [73, 91, 430, 310]
print(("PASS" if ok else "FAIL") + f" 4. the window floats at A and was never maximized: {s}")' "$st" >>"$CHK"
wait_record 73 91 430 310 "4. the memory keeps A"
place 97 113 430 310
wait_record 97 113 430 310 "4. a later move is remembered (the requested mode is not left pending)"
send quit
held_stop
sleep 3

# ---- 5. the client's own request: maximized at once, closed maximized, the memory keeps A
held_start fourth
sleep 3
place 73 91 430 310
wait_record 73 91 430 310 "5. the fourth window is remembered at A"
n=$(configures)
send maximize
read -r sx wx hx < <(wait_configure "$n")
info "5. the configure answering the client's request: serial $sx, ${wx}x$hx"
[ "$sx" != none ] && [ "$wx" != 430 ] && pass "5. the client's request brings a maximized configure" ||
  fail "5. no maximized configure for the client's request (serial $sx, ${wx}x$hx)"
sleep 3
st=$(state)
info "5. maximized at its own request: $st"
python3 -c 'import json, sys; s = json.loads(sys.argv[1])
ok = s and s["max"] == 3 and round(s["frame"][2]) != 430
print(("PASS" if ok else "FAIL") + f" 5. the window took the maximize: {s}")' "$st" >>"$CHK"
record_is 73 91 430 310 && pass "5. the maximized frame is not recorded" || fail "5. the maximized frame was recorded: $(memory)"
# the client asks to be restored: back at A, and the restore taken records A again (the record is
# moved away first so that the check means something)
place 97 113 430 310
wait_record 97 113 430 310 "5. a move between the maximizes is remembered"
K run "$FIND if (w) { w.setMaximize(true, true); } report(!!w);" >>"$OUT/place.log"
sleep 3
send unmaximize
sleep 3
st=$(state)
info "5. restored at its own request: $st"
python3 -c 'import json, sys; s = json.loads(sys.argv[1])
ok = s and s["max"] == 0 and [round(v) for v in s["frame"]] == [97, 113, 430, 310]
print(("PASS" if ok else "FAIL") + f" 5. the window floats where it was: {s}")' "$st" >>"$CHK"
wait_record 97 113 430 310 "5. the restore taken keeps the floating record"
send maximize
sleep 3
send quit
held_stop
sleep 3
record_is 97 113 430 310 && pass "5. closed maximized at its own request: the memory keeps the floating place" || fail "5. the close changed the record: $(memory)"

# ---- 6. two requests in flight on a maximized window, answered one by one: a restore (configure
# A, A's size, no maximized state), then a maximize (configure B, the maximized size). KWin's
# requested mode is the last request's (maximized); the script's mirror must not fall back to the
# mode taken when the restore's commit lands, or the maximize's commit (frame maximized, mode
# still restored) would be recorded as a floating frame.
held_start fifth
sleep 3
place 73 91 430 310
wait_record 73 91 430 310 "6. the fifth window is remembered at A"
K run "$FIND if (w) { w.setMaximize(true, true); } report(!!w);" >>"$OUT/place.log"
sleep 3
st=$(state)
python3 -c 'import json, sys; s = json.loads(sys.argv[1])
print(("PASS" if s and s["max"] == 3 else "FAIL") + f" 6. the window is maximized to begin with: {s}")' "$st" >>"$CHK"
send hold
n=$(configures)
K run "$FIND if (w) { w.setMaximize(false, false); } report(!!w);" >>"$OUT/place.log"
read -r sa wa ha < <(wait_configure "$n")
info "6. the restore's configure: serial $sa, ${wa}x$ha"
[ "$sa" != none ] && [ "$wa" = 430 ] && [ "$ha" = 310 ] && pass "6. the restore sends a configure for A's size" ||
  fail "6. no configure for A's size (serial $sa, ${wa}x$ha)"
n=$(configures)
K run "$FIND if (w) { w.setMaximize(true, true); } report(!!w);" >>"$OUT/place.log"
read -r sb wb hb < <(wait_configure "$n")
info "6. the maximize's configure: serial $sb, ${wb}x$hb"
[ "$sb" != none ] && [ "$wb" != 430 ] && pass "6. the maximize sends a configure with the maximized size" ||
  fail "6. no maximized configure (serial $sb, ${wb}x$hb)"
send "ack $sa"
send commit
sleep 2
st=$(state)
info "6. after the restore's commit: $st"
python3 -c 'import json, sys; s = json.loads(sys.argv[1])
ok = s and s["max"] == 0 and [round(v) for v in s["frame"]] == [73, 91, 430, 310]
print(("PASS" if ok else "FAIL") + f" 6. the restore is taken first (mode 0, frame A): {s}")' "$st" >>"$CHK"
send "ack $sb"
send commit
sleep 4
st=$(state)
info "6. after the maximize's commit: $st"
python3 -c 'import json, sys; s = json.loads(sys.argv[1])
print(("PASS" if s and s["max"] == 3 and round(s["frame"][2]) != 430 else "FAIL") + f" 6. then the maximize is taken: {s}")' "$st" >>"$CHK"
record_is 73 91 430 310 && pass "6. the maximized frame that followed the restore is not recorded" || fail "6. the memory changed: $(memory)"
send quit
held_stop
sleep 3
record_is 73 91 430 310 && pass "6. closed maximized: the memory keeps A" || fail "6. the close changed the record: $(memory)"


cp "$HOME/.config/plasmafusion-placementrc" "$OUT/memory-final.rc" 2>/dev/null || true
info "placement log lines:"; grep -a 'plasmafusion-placement' "$KLOG" | tail -15 >>"$CHK" 2>/dev/null || true
failed=$(grep -c '^FAIL' "$CHK" || true)
info "verdict: $(grep -c '^PASS' "$CHK" || true) passed, $failed failed"
info "done"
trap - ERR
set +e
[ "$failed" = 0 ]
