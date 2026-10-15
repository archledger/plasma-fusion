#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Snap groups (plasmafusion-snap) in a private session, driven with real keys (pfinput):
#   1. Meta+Z -> quarters -> Enter puts the first window top-left; the picker then offers the other
#      three quarters in turn (Enter x3): four windows in four quarters;
#   2. the four are one group: minimising one minimises all, restoring one restores all;
#   3. activating a member brings the whole group above a window that covered it;
#   4. a member moved out of its quarter leaves: the group minimises without it;
#   5. Meta+Z -> thirds fills all three thirds (plain geometry), and that group minimises together;
#      a window placed anew through the flyout leaves that group;
#   6. the halves flow from an edge snap (Meta+Left) still pairs its two windows;
#   7. a window that already holds a zone can be picked for another one: the zone it leaves is
#      offered in its turn, and all four quarters end up filled;
#   8. a pick that cannot be placed (the window closed while the picker was open) ends the
#      sequence: the halves picker still works for that window afterwards;
#   9. the first window leaving its zone before the next offer ends the sequence (no picker);
#  10. a window the switcher skips still holds its third (nothing is placed over it);
#  11. a thirds member sent to another desktop leaves its group;
#  12. a minimised window still holds its third (nothing placed there, it comes back alone);
#  13. the first window sent to another desktop while the picker is open ends the sequence;
#  14. a thirds member moved to another activity leaves its group;
#  15. a window the sequence placed that closes before the layout is full leaves its zone to be
#      offered again (all four quarters end up filled);
#  16. a minimised member of another group picked for a new layout is restored alone;
#  17. a thirds member moved by a script (not by the user) leaves its group, also when the move
#      comes within its placement's settle (asked at the group's next use);
#  18. the first window moved by a script while the picker is open ends the sequence (no placement);
#  20. a window of another activity sitting in a third does not hold it;
#  21. a placed window moved out of its third by a script while a later picker is open leaves the
#      third to be offered again.
# Run: tools/vsession/remote.sh sg-1 packages/kwin/tests/vsession/scenario-snapgroups.sh SEED 1440x900 420
exec 2>&1
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
# A step that fails stops the scenario (strict mode); the reason lands in the checks.
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }

# The session's normal windows (stacking order: z grows to the top) and the work area, as JSON.
state() { # FILE
  K run "var l = workspace.stackingOrder, out = [];
    for (var i = 0; i < l.length; ++i) { var c = l[i]; if (!c || c.deleted || !c.normalWindow) { continue; }
      var g = c.frameGeometry;
      var ds = []; for (var d = 0; d < c.desktops.length; ++d) { ds.push(String(c.desktops[d].id)); }
      out.push({cls: String(c.resourceClass), x: g.x, y: g.y, w: g.width, h: g.height, tiled: !!c.tile,
                min: c.minimized, z: i, desktops: c.onAllDesktops ? ['*'] : ds}); }
    var a = workspace.clientArea(KWin.MaximizeArea, workspace.activeScreen, workspace.currentDesktop);
    report({wins: out, area: {x: a.x, y: a.y, w: a.width, h: a.height}});" >"$1"
}
# The newest normal window whose class contains CLASS: raised and made active (the picker lists
# windows top of the stack first, so the order of these calls decides its cards), minimised or
# restored.
act() { # CLASS
  K run "var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('$1') >= 0) { w = l[i]; } }
    if (w) { workspace.raiseWindow(w); workspace.activeWindow = w; } report(w ? String(w.resourceClass) : null);" >>"$OUT/act.log"
}
minimize() { # CLASS true|false
  K run "var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('$1') >= 0) { w = l[i]; } }
    if (w) { w.minimized = $2; } report(w ? String(w.resourceClass) : null);" >>"$OUT/act.log"
}
place() { # CLASS X Y W H: out of its tile and to a spot of its own
  K run "var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('$1') >= 0) { w = l[i]; } }
    if (w) { if (w.tile) { w.tile.unmanage(w); } w.frameGeometry = {x: $2, y: $3, width: $4, height: $5}; }
    report(w ? String(w.resourceClass) : null);" >>"$OUT/act.log"
}

# The checks read a state file (python, below): CHECK STATE ARGS... -> one PASS/FAIL line.
cat >"$OUT/judge.py" <<'PY'
import json, sys
kind, path, args = sys.argv[1], sys.argv[2], sys.argv[3:]
d = json.load(open(path))
wins, area = d["wins"], d["area"]
def find(name):
    hits = [w for w in wins if name in w["cls"]]
    return hits[-1] if hits else None
def out(ok, label, detail=""):
    print(("PASS " if ok else "FAIL ") + label + (": " + detail if detail else ""))
if kind == "quarters":            # NAMES...: each tiled, the centres in four different quarters
    label = "the picker filled all four quarters"
    seen, missing = set(), []
    for n in args:
        w = find(n)
        if not w or not w["tiled"] or w["min"]:
            missing.append(n); continue
        cx, cy = w["x"] + w["w"] / 2, w["y"] + w["h"] / 2
        seen.add((cx >= area["x"] + area["w"] / 2, cy >= area["y"] + area["h"] / 2))
    out(not missing and len(seen) == 4, label, "missing %s, quarters %d" % (missing, len(seen)))
elif kind == "minimized":         # LABEL WANT NAMES...: minimised state of each window
    label, want = args[0], args[1] == "true"
    bad = [n for n in args[2:] if not find(n) or find(n)["min"] != want]
    if not args[2:]:
        out(False, label, "no windows to check")
    else:
        out(not bad, label, "not %s: %s" % ("minimised" if want else "restored", bad) if bad else "")
elif kind == "above":             # LABEL COVER NAMES...: every NAME stacks above COVER
    label, cover = args[0], find(args[1])
    bad = [n for n in args[2:] if not find(n) or not cover or find(n)["z"] < cover["z"]]
    out(cover is not None and not bad, label, "below %s: %s" % (args[1], bad) if bad else "")
elif kind == "quartersfilled":     # LABEL: four tiled quarter-sized windows, one in each quarter
    label = args[0]
    seen = set()
    for w in wins:
        if w["tiled"] and not w["min"] and w["w"] < area["w"] * 0.6 and w["h"] < area["h"] * 0.6:
            seen.add((w["x"] + w["w"] / 2 >= area["x"] + area["w"] / 2, w["y"] + w["h"] / 2 >= area["y"] + area["h"] / 2))
    out(len(seen) == 4, label, "quarters %d" % len(seen))
elif kind == "halves":            # LABEL NAME: two tiled half-sized windows, NAME one of them
    label, name = args[0], args[1]
    halves = [w["cls"] for w in wins if w["tiled"] and not w["min"] and w["w"] > area["w"] * 0.4 and w["h"] > area["h"] * 0.9]
    out(len(halves) == 2 and any(name in c for c in halves), label, "halves %s" % halves)
elif kind == "untiled":           # LABEL: no window is tiled
    tiled = [w["cls"] for w in wins if w["tiled"] and not w["min"]]
    out(not tiled, args[0], "tiled %s" % tiled)
elif kind == "thirdalone":        # LABEL NAME: NAME is the only window in the middle third
    g = 6
    size = (area["w"] - 2 * g) / 3
    x1 = round(area["x"] + size + g)
    there = [w["cls"] for w in wins if not w["tiled"] and not w["min"] and abs(w["x"] - x1) <= 4
             and abs(w["y"] - area["y"]) <= 4 and w["w"] <= size + 4]
    out(len(there) == 1 and args[1] in there[0], args[0], "in the middle third %s" % there)
elif kind == "emptythirds":       # LABEL: nothing (untiled, not minimised) in the second and third thirds
    g = 6
    size = (area["w"] - 2 * g) / 3
    starts = [round(area["x"] + size + g), round(area["x"] + 2 * (size + g))]
    there = [w["cls"] for w in wins if not w["tiled"] and not w["min"] and abs(w["y"] - area["y"]) <= 4
             and any(abs(w["x"] - s) <= 4 for s in starts) and w["w"] <= size + 4]
    out(not there, args[0], "in the second or third third %s" % there)
elif kind == "thirdother":        # LABEL NAME: a window other than NAME sits in the middle third
    g = 6
    size = (area["w"] - 2 * g) / 3
    x1 = round(area["x"] + size + g)
    there = [w["cls"] for w in wins if not w["tiled"] and not w["min"] and abs(w["x"] - x1) <= 4
             and abs(w["y"] - area["y"]) <= 4 and w["w"] <= size + 4 and args[1] not in w["cls"]]
    out(len(there) >= 1, args[0], "in the middle third besides %s: %s" % (args[1], there))
elif kind == "thirds":            # NAMES...: not tiled, each in a different third (top-left within 4 px)
    g = 6
    size = (area["w"] - 2 * g) / 3
    starts = [area["x"], round(area["x"] + size + g), round(area["x"] + 2 * (size + g))]
    slots = set()
    for n in args:
        w = find(n)
        if not w or w["tiled"] or w["min"]:
            continue
        for k, s in enumerate(starts):
            if abs(w["x"] - s) <= 4 and abs(w["y"] - area["y"]) <= 4 and w["w"] <= size + 4:
                slots.add(k)
    out(len(slots) == 3, "the picker filled all three thirds", "thirds %s" % sorted(slots))
PY
judge() { python3 "$OUT/judge.py" "$@" >>"$CHK"; } # KIND STATE ARGS...

# ---- the Fusion setup (it enables the snap script) and four windows
fc_rc=0
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || fc_rc=$?
info "fusion-config rc=$fc_rc"
kwriteconfig6 --file kwinrc --group Plugins --key plasmafusion-snapEnabled true
qdbus org.kde.KWin /KWin reconfigure
sleep 3
loaded=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-snap)
[ "$loaded" = true ] && pass "the snap script is loaded" || fail "the snap script is not loaded ($loaded)"
# The pointer rests away from where the flyout opens (a hovered zone would win over the keys).
pfinput 'move 1400 520'
for app in konsole kwrite dolphin kate; do
  "$app" >/dev/null 2>&1 &
  sleep 3
done
sleep 2
state "$OUT/s0.json"
info "windows: $(python3 -c 'import json,sys; print([w["cls"] for w in json.load(open(sys.argv[1]))["wins"]])' "$OUT/s0.json")"

# ---- 1. quarters through the flyout, the picker for the other three
act konsole
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 3' 'sleep 0.5' 'key enter'
sleep 1.5
shot 10-picker-first
pfinput 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 2
shot 11-quarters
state "$OUT/s1.json"
judge quarters "$OUT/s1.json" konsole kwrite dolphin kate

# ---- 2. one group: minimise one, all go; restore one, all come back
minimize kate true
sleep 1.5
state "$OUT/s2.json"
judge minimized "$OUT/s2.json" "minimising one quarter minimises its group" true konsole kwrite dolphin kate
minimize konsole false
sleep 1.5
state "$OUT/s3.json"
judge minimized "$OUT/s3.json" "restoring one restores the group" false konsole kwrite dolphin kate
shot 20-restored

# ---- 3. a window covers the group; activating one member brings the group up
okular >/dev/null 2>&1 &
sleep 4
act okular
sleep 1
act kwrite
sleep 1.5
state "$OUT/s4.json"
judge above "$OUT/s4.json" "activating one member raises the group above a covering window" okular konsole kwrite dolphin kate
shot 30-raised

# ---- 4. a member leaves its quarter: the group goes on without it
place dolphin 300 180 700 460
sleep 1.5
minimize konsole true
sleep 1.5
state "$OUT/s5.json"
judge minimized "$OUT/s5.json" "the group still minimises together" true konsole kwrite kate
judge minimized "$OUT/s5.json" "the window that left its quarter stays up" false dolphin
minimize konsole false
sleep 1.5
shot 40-left

# ---- 5. thirds through the flyout (plain geometry, not KWin tiles)
act okular
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 4' 'sleep 0.5' 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 2
shot 50-thirds
state "$OUT/s6.json"
thirds=$(python3 -c 'import json,sys
d = json.load(open(sys.argv[1])); a = d["area"]; g = 6; size = (a["w"] - 2 * g) / 3
starts = [a["x"], round(a["x"] + size + g), round(a["x"] + 2 * (size + g))]
print(" ".join(w["cls"] for w in d["wins"] if not w["tiled"] and not w["min"] and abs(w["y"] - a["y"]) <= 4
               and any(abs(w["x"] - s) <= 4 for s in starts) and w["w"] <= size + 4))' "$OUT/s6.json")
info "in the thirds: $thirds"
# shellcheck disable=SC2086 # the class names, one word each
judge thirds "$OUT/s6.json" $thirds
minimize okular true
sleep 1.5
state "$OUT/s7.json"
# shellcheck disable=SC2086
judge minimized "$OUT/s7.json" "the thirds group minimises together" true $thirds
minimize okular false
sleep 1.5

# ---- 5b. a new layout choice is a new arrangement: okular moves to the middle third through the
# flyout (no tile changes) and leaves its old group; Esc ends the new picker without a pick
act okular
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 4' 'sleep 0.4' 'key right' 'sleep 0.4' 'key enter'
sleep 1.5
pfinput 'key esc'
sleep 1
others=""
for c in $thirds; do
  case $c in *okular*) ;; *) others="$others $c" ;; esac
done
others=${others# }
info "the old thirds group without okular: $others"
minimize "${others%% *}" true
sleep 1.5
state "$OUT/s7b.json"
judge minimized "$OUT/s7b.json" "a window placed anew through the flyout left its old group" false okular
# shellcheck disable=SC2086
judge minimized "$OUT/s7b.json" "the rest of the old group still minimises together" true $others
minimize "${others%% *}" false
sleep 1.5

# ---- 6. the halves flow from an edge snap still pairs its two windows
act dolphin
sleep 0.5
pfinput 'key meta+left'
sleep 1.5
shot 60-halves-picker
pfinput 'key enter'
sleep 2
state "$OUT/s8.json"
pair=$(python3 -c 'import json,sys
d = json.load(open(sys.argv[1])); a = d["area"]
print(" ".join(w["cls"] for w in d["wins"] if w["tiled"] and not w["min"] and w["w"] > a["w"] * 0.4 and w["h"] > a["h"] * 0.9))' "$OUT/s8.json")
info "the halves: $pair"
[ "$(echo "$pair" | wc -w)" = 2 ] && pass "the edge snap's picker filled the other half" || fail "the halves are not filled ($pair)"
minimize dolphin true
sleep 1.5
state "$OUT/s9.json"
# shellcheck disable=SC2086
judge minimized "$OUT/s9.json" "the halves pair minimises together" true $pair
minimize dolphin false
sleep 1

# Every window out of its tile, restored, on the first desktop and all activities, and cascaded to
# a spot of its own (no zone of any layout), for the sections that need an empty layout: a window
# left in a third or on another desktop by an earlier section would otherwise still count. Any
# group from before ends (its members left their zones).
reset_tiles() {
  K run "var l = workspace.windowList(), n = 0;
    for (var i = 0; i < l.length; ++i) { var w = l[i]; if (!w.normalWindow) { continue; }
      if (w.tile) { w.tile.unmanage(w); } w.minimized = false;
      w.desktops = [workspace.desktops[0]]; w.activities = [];
      w.frameGeometry = {x: 160 + 28 * n, y: 110 + 24 * n, width: 640, height: 420}; ++n; }
    report(n);" >>"$OUT/act.log"
}

# ---- 7. Kate holds the top-right quarter; Konsole's quarters fill the bottom-left first, Kate (the
# most recent window) is picked for it, and the top-right quarter it leaves is offered in its turn
reset_tiles
sleep 1.5
act kate
sleep 0.5
K run "workspace.slotWindowQuickTileTopRight(); report(true);" >>"$OUT/act.log"
sleep 1.5
act konsole
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 3' 'sleep 0.5' 'key enter'
sleep 1.5
shot 70-held-zone-picker
pfinput 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 2
shot 71-held-zone-filled
state "$OUT/s10.json"
judge quartersfilled "$OUT/s10.json" "the zone a picked window left is offered in its turn (four quarters filled)"

# ---- 8. a pick that cannot be placed ends the sequence; the halves picker still works afterwards
reset_tiles
sleep 1.5
kcharselect >/dev/null 2>&1 &
sleep 3
act kcharselect
sleep 0.5
act konsole
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 3' 'sleep 0.5' 'key enter'
sleep 1.5
shot 80-picker-before-close
# KCharSelect, the first card, closes while the picker is open; Enter then picks the closed window
K run "var l = workspace.windowList();
  for (var i = 0; i < l.length; ++i) { if (String(l[i].resourceClass).indexOf('kcharselect') >= 0) { l[i].closeWindow(); } }
  report(true);" >>"$OUT/act.log"
sleep 1.5
pfinput 'key enter'
sleep 1.5
# Meta+Left on a window in the top-left quarter keeps it there (KWin's quick-tile combination), so
# the windows float first; a sequence left stuck by the rejected pick would survive this.
reset_tiles
sleep 1.5
act konsole
sleep 0.5
pfinput 'key meta+left'
sleep 1.5
shot 81-halves-after-rejected
pfinput 'key enter'
sleep 2
state "$OUT/s11.json"
judge halves "$OUT/s11.json" "after a rejected pick the halves picker still fills the other half" konsole

# ---- 9. the first window leaves its quarter right after its placement (a test script moves it,
# through an async D-Bus round trip, inside the settle before the next offer): the sequence ends
reset_tiles
sleep 1.5
act konsole
sleep 0.5
K run "var w = workspace.activeWindow, done = false;
  w.tileChanged.connect(function () {
    if (done || !w.tile) { return; }
    done = true;
    callDBus('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'GetId', function () {
      if (w.tile) { w.tile.unmanage(w); }
      w.frameGeometry = {x: 260, y: 160, width: 760, height: 520};
      report(String(w.resourceClass));
    });
  });" >"$OUT/anchormove.json" &
mover=$!
sleep 1
pfinput 'key meta+z' 'sleep 1' 'key 3' 'sleep 0.5' 'key enter'
wait "$mover"
sleep 1.5
shot 90-anchor-moved
# A picker that still came would take this Enter and tile a window.
pfinput 'key enter'
sleep 1.5
state "$OUT/s12.json"
judge untiled "$OUT/s12.json" "the sequence ends when its first window leaves the zone before the next offer"

# ---- 10. Okular holds the middle third and the switcher skips it (as a window rule can make it):
# the thirds offer skips that third, nothing is placed over Okular
reset_tiles
sleep 1.5
K run "var a = workspace.clientArea(KWin.MaximizeArea, workspace.activeScreen, workspace.currentDesktop);
  var size = (a.width - 12) / 3, x1 = Math.round(a.x + size + 6), x2 = Math.round(a.x + 2 * size + 6);
  var l = workspace.windowList(), w = null;
  for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('okular') >= 0) { w = l[i]; } }
  if (w) { w.skipSwitcher = true; w.frameGeometry = {x: x1, y: a.y, width: x2 - x1, height: a.height}; }
  report(w ? [x1, a.y, x2 - x1, a.height] : null);" >"$OUT/occupant.json"
sleep 1.5
act konsole
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 4' 'sleep 0.5' 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
shot 100-occupied-third
state "$OUT/s13.json"
judge thirdalone "$OUT/s13.json" "a window the switcher skips keeps its third (nothing placed over it)" okular
K run "var l = workspace.windowList();
  for (var i = 0; i < l.length; ++i) { if (String(l[i].resourceClass).indexOf('okular') >= 0) { l[i].skipSwitcher = false; } }
  report(true);" >>"$OUT/act.log"

# ---- 11. the window in the third third (Konsole's partner) goes to a second desktop: it leaves
# the group, so minimising Konsole leaves it alone
third=$(python3 -c 'import json,sys
d = json.load(open(sys.argv[1])); a = d["area"]; g = 6; size = (a["w"] - 2 * g) / 3
x2 = round(a["x"] + 2 * (size + g))
print(" ".join(w["cls"] for w in d["wins"] if not w["tiled"] and not w["min"] and abs(w["x"] - x2) <= 4
               and abs(w["y"] - a["y"]) <= 4))' "$OUT/s13.json")
third=${third%% *}
info "the third-third window: ${third:-none}"
K run "if (workspace.desktops.length < 2) { workspace.createDesktop(1, 'two'); }
  var l = workspace.windowList(), w = null;
  for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && '${third:-none}' !== 'none' && String(l[i].resourceClass) === '${third:-none}') { w = l[i]; } }
  if (w && workspace.desktops.length > 1) { w.desktops = [workspace.desktops[1]]; }
  report(w ? workspace.desktops.length : null);" >>"$OUT/act.log"
sleep 1.5
minimize konsole true
sleep 1.5
state "$OUT/s14.json"
# shellcheck disable=SC2086 # one class name, or none (then the check fails: no windows)
judge minimized "$OUT/s14.json" "a member sent to another desktop left its group" false ${third:+$third}
minimize konsole false
sleep 1

# A window (newest of CLASS) to a spot: X Y W H.
geometry() { # CLASS X Y W H
  K run "var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('$1') >= 0) { w = l[i]; } }
    if (w) { w.frameGeometry = {x: $2, y: $3, width: $4, height: $5}; } report(w ? String(w.resourceClass) : null);" >>"$OUT/act.log"
}
# The middle third's rectangle as "X Y W H" (the snap script's arithmetic, 6 px gap).
middle_third() {
  K run "var a = workspace.clientArea(KWin.MaximizeArea, workspace.activeScreen, workspace.currentDesktop);
    var size = (a.width - 12) / 3, x1 = Math.round(a.x + size + 6), x2 = Math.round(a.x + 2 * size + 6);
    report([x1, a.y, x2 - x1, a.height]);" | python3 -c 'import json,sys; print(" ".join(str(int(v)) for v in json.load(sys.stdin)))'
}
second_desktop() { # CLASS: the newest window of CLASS to a second virtual desktop (made if needed)
  K run "if (workspace.desktops.length < 2) { workspace.createDesktop(1, 'two'); }
    var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('$1') >= 0) { w = l[i]; } }
    if (w && workspace.desktops.length > 1) { w.desktops = [workspace.desktops[1]]; }
    report(w ? workspace.desktops.length : null);" >>"$OUT/act.log"
}
first_desktop() { # CLASS: back to the first desktop
  K run "var l = workspace.windowList();
    for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('$1') >= 0) { l[i].desktops = [workspace.desktops[0]]; } }
    report(true);" >>"$OUT/act.log"
}

# ---- 12. a minimised Okular in the middle third still holds it: Konsole's thirds skip it
reset_tiles
sleep 1.5
# shellcheck disable=SC2046 # "X Y W H"
geometry okular $(middle_third)
sleep 1.5
minimize okular true
sleep 1
act kate
sleep 0.3
act kwrite
sleep 0.3
act konsole
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 4' 'sleep 0.5' 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
minimize okular false
sleep 1.5
state "$OUT/s15.json"
judge thirdalone "$OUT/s15.json" "a minimised window still holds its third (it comes back alone)" okular

# ---- 13. Konsole (in the first third) goes to another desktop while the picker is open: the
# sequence ends, nothing is placed for it
reset_tiles
sleep 1.5
act konsole
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 4' 'sleep 0.5' 'key enter'
sleep 1.5
shot 130-picker-open
second_desktop konsole
sleep 1.5
pfinput 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
state "$OUT/s16.json"
judge emptythirds "$OUT/s16.json" "the first window sent to another desktop ends the sequence (nothing placed)"
first_desktop konsole
sleep 1.5

# ---- 14. a thirds member moved to another activity leaves its group
reset_tiles
sleep 1.5
act konsole
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 4' 'sleep 0.5' 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
state "$OUT/s17.json"
member=$(python3 -c 'import json,sys
d = json.load(open(sys.argv[1])); a = d["area"]; g = 6; size = (a["w"] - 2 * g) / 3
x2 = round(a["x"] + 2 * (size + g))
print(" ".join(w["cls"] for w in d["wins"] if not w["tiled"] and not w["min"] and abs(w["x"] - x2) <= 4
               and abs(w["y"] - a["y"]) <= 4))' "$OUT/s17.json")
member=${member%% *}
activity=$(qdbus org.kde.ActivityManager /ActivityManager/Activities org.kde.ActivityManager.Activities.AddActivity two 2>>"$OUT/errors.log" || true)
info "activity: ${activity:-none}; the third-third window: ${member:-none}"
if [ -n "$activity" ] && [ -n "$member" ]; then
  K run "var l = workspace.windowList();
    for (var i = 0; i < l.length; ++i) { if (String(l[i].resourceClass) === '$member') { l[i].activities = ['$activity']; } }
    report(true);" >>"$OUT/act.log"
  sleep 1.5
  minimize konsole true
  sleep 1.5
  state "$OUT/s18.json"
  judge minimized "$OUT/s18.json" "a member moved to another activity left its group" false "$member"
  minimize konsole false
  sleep 1
  K run "var l = workspace.windowList();
    for (var i = 0; i < l.length; ++i) { if (String(l[i].resourceClass) === '$member') { l[i].activities = []; } }
    report(true);" >>"$OUT/act.log"
  sleep 1
else
  fail "a member moved to another activity left its group: no second activity or member (activity '${activity}', member '${member}')"
fi

# ---- 15. KCharSelect, placed in the top-right quarter by the sequence, closes right away - in
# the settle before the next offer (a test script closes it on its placement, through an async
# D-Bus round trip): the top-right quarter is offered again and all four quarters fill. (Closed
# while the next picker is open, the active window it was takes the focus with it, and the picker
# closes on that focus change by design.)
reset_tiles
sleep 1.5
kcharselect >/dev/null 2>&1 &
sleep 3
act kcharselect
sleep 0.5
act konsole
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 3' 'sleep 0.5' 'key enter'
sleep 1.5
shot 150-before-close
K run "var l = workspace.windowList(), w = null, done = false;
  for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('kcharselect') >= 0) { w = l[i]; } }
  w.tileChanged.connect(function () {
    if (done || !w.tile) { return; }
    done = true;
    callDBus('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus', 'GetId', function () {
      w.closeWindow();
      report(true);
    });
  });" >"$OUT/closer.json" &
closer=$!
sleep 1
pfinput 'key enter'
wait "$closer"
sleep 1.5
pfinput 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 2
shot 151-after-close
state "$OUT/s19.json"
judge quartersfilled "$OUT/s19.json" "a zone whose window closed during the sequence is offered again (four quarters filled)"

# ---- 16. Dolphin and its halves partner form a group and are minimised together; Konsole's new
# quarters pick Dolphin (the first card): Dolphin is restored alone, its old partner stays minimised
reset_tiles
sleep 1.5
act dolphin
sleep 0.5
pfinput 'key meta+left'
sleep 1.5
shot 161-halves-picker
pfinput 'key enter'
sleep 2
state "$OUT/s20.json"
partner=$(python3 -c 'import json,sys
d = json.load(open(sys.argv[1])); a = d["area"]
print(" ".join(w["cls"] for w in d["wins"] if w["tiled"] and not w["min"] and w["w"] > a["w"] * 0.4
               and w["h"] > a["h"] * 0.9 and "dolphin" not in w["cls"]))' "$OUT/s20.json")
partner=${partner%% *}
info "dolphin's halves partner: ${partner:-none}"
# The new layout's first window is one outside the pair (activating a minimised partner would
# restore it, and its group with it, by design).
anchor=konsole
for c in konsole kwrite kate okular; do
  case $partner in *"$c"*) ;; *) anchor=$c; break ;; esac
done
info "the new layout's first window: $anchor"
act dolphin
sleep 0.5
minimize dolphin true
sleep 1.5
act "$anchor"
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 3' 'sleep 0.5' 'key enter'
sleep 1.5
shot 160-picker-minimised
# Dolphin's card: the picker lists the windows top of the stack first with the snap script's own
# filter (candidatesFor); the order of minimised windows in the stack is KWin's, so the card is
# counted rather than assumed first.
card=$(K run "var l = workspace.stackingOrder, d = workspace.currentDesktop, n = 0, found = -1;
  for (var i = l.length - 1; i >= 0; --i) { var w = l[i];
    if (!w || w.deleted || !w.normalWindow || w.popupWindow || !w.moveable || !w.resizeable || w.fullScreen
        || w.specialWindow || w.skipSwitcher || w.transient || String(w.resourceClass).indexOf('$anchor') >= 0) { continue; }
    var here = w.onAllDesktops; for (var k = 0; k < w.desktops.length; ++k) { if (w.desktops[k] === d) { here = true; } }
    if (!here) { continue; }
    if (String(w.resourceClass).indexOf('dolphin') >= 0) { found = n; break; }
    ++n; }
  report(found);" | python3 -c 'import json,sys; print(int(json.load(sys.stdin)))')
info "dolphin's card: $card"
keys=()
for ((i = 0; i < card; ++i)); do keys+=('key right' 'sleep 0.2'); done
pfinput "${keys[@]}" 'key enter'
sleep 1.5
pfinput 'key esc'
sleep 1.5
state "$OUT/s21.json"
judge minimized "$OUT/s21.json" "Dolphin was picked and restored" false dolphin
# shellcheck disable=SC2086 # one class name, or none (then the check fails: no windows)
judge minimized "$OUT/s21.json" "its old group's partner stays minimised" true ${partner:+$partner}

# ---- 17. Konsole's thirds partner is moved by a script (as an app can move itself): it leaves
reset_tiles
sleep 2
act konsole
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 4' 'sleep 0.5' 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
pfinput 'key esc'
sleep 2.5
state "$OUT/s22.json"
moved=$(python3 -c 'import json,sys
d = json.load(open(sys.argv[1])); a = d["area"]; g = 6; size = (a["w"] - 2 * g) / 3
x1 = round(a["x"] + size + g)
print(" ".join(w["cls"] for w in d["wins"] if not w["tiled"] and not w["min"] and abs(w["x"] - x1) <= 4
               and abs(w["y"] - a["y"]) <= 4))' "$OUT/s22.json")
moved=${moved%% *}
info "konsole's partner in the middle third: ${moved:-none}"
if [ -n "$moved" ]; then
  K run "var l = workspace.windowList();
    for (var i = 0; i < l.length; ++i) { if (String(l[i].resourceClass) === '$moved') { l[i].frameGeometry = {x: 380, y: 220, width: 620, height: 420}; } }
    report(true);" >>"$OUT/act.log"
  sleep 1.5
  minimize konsole true
  sleep 1.5
  state "$OUT/s23.json"
  judge minimized "$OUT/s23.json" "a member moved by a script left its group" false "$moved"
  minimize konsole false
  sleep 1
else
  fail "a member moved by a script left its group: no partner in the middle third"
fi

# The class of the window in the middle third right now (or none).
middle_window() { # STATE
  python3 -c 'import json,sys
d = json.load(open(sys.argv[1])); a = d["area"]; g = 6; size = (a["w"] - 2 * g) / 3
x1 = round(a["x"] + size + g)
hits = [w["cls"] for w in d["wins"] if not w["tiled"] and not w["min"] and abs(w["x"] - x1) <= 4 and abs(w["y"] - a["y"]) <= 4]
print(hits[-1] if hits else "")' "$1"
}
move_away() { # EXACT_CLASS: a script moves the window out of its zone (as an app can move itself)
  K run "var l = workspace.windowList();
    for (var i = 0; i < l.length; ++i) { if (String(l[i].resourceClass) === '$1') { l[i].frameGeometry = {x: 380, y: 220, width: 620, height: 420}; } }
    report(true);" >>"$OUT/act.log"
}

# ---- 17b. the same, but the script moves the partner right after its placement (within the
# settle, no geometry change after it): the group's next use asks it, and it is left out
reset_tiles
sleep 2
act kwrite
sleep 0.3
act konsole
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 4' 'sleep 0.5' 'key enter'
sleep 1.5
# KWrite (the first card) goes to the middle third and is moved away at once, inside the settle.
pfinput 'key enter'
move_away org.kde.kwrite
sleep 0.4
pfinput 'key esc'
quick=org.kde.kwrite
state "$OUT/s24.json"
info "moved within the settle: $quick"
if [ -n "$quick" ]; then
  sleep 2.5
  minimize konsole true
  sleep 1.5
  state "$OUT/s25.json"
  judge minimized "$OUT/s25.json" "a member moved within its placement's settle is left out of the next group action" false "$quick"
  minimize konsole false
  sleep 1
else
  fail "a member moved within its placement's settle is left out of the next group action: no partner in the middle third"
fi

# ---- 18. Konsole (first third) is moved by a script while the picker is open, after the settle:
# the sequence ends, the next Enters place nothing
reset_tiles
sleep 2
act konsole
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 4' 'sleep 0.5' 'key enter'
sleep 2
move_away org.kde.konsole
sleep 1
pfinput 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
state "$OUT/s26.json"
judge emptythirds "$OUT/s26.json" "the first window moved by a script while the picker is open ends the sequence"

# ---- 20. Okular sits in the middle third on another activity: from this activity the third is
# empty, so it is offered (Konsole's first pick lands there)
reset_tiles
sleep 2
other=${activity:-}
[ -n "$other" ] || other=$(qdbus org.kde.ActivityManager /ActivityManager/Activities org.kde.ActivityManager.Activities.AddActivity two 2>>"$OUT/errors.log" || true)
# shellcheck disable=SC2046 # "X Y W H"
geometry okular $(middle_third)
sleep 1
K run "var l = workspace.windowList();
  for (var i = 0; i < l.length; ++i) { if (String(l[i].resourceClass).indexOf('okular') >= 0) { l[i].activities = ['$other']; } }
  report(true);" >>"$OUT/act.log"
sleep 1.5
act konsole
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 4' 'sleep 0.5' 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
pfinput 'key esc'
sleep 1.5
state "$OUT/s27.json"
judge thirdother "$OUT/s27.json" "a window of another activity does not hold the third (it is offered)" okular
K run "var l = workspace.windowList();
  for (var i = 0; i < l.length; ++i) { if (String(l[i].resourceClass).indexOf('okular') >= 0) { l[i].activities = []; } }
  report(true);" >>"$OUT/act.log"
sleep 1

# ---- 21. the window placed in the middle third is moved out by a script while the picker for the
# last third is open (after its settle): after the next pick, the middle third is offered again
reset_tiles
sleep 2
act kate
sleep 0.3
act kwrite
sleep 0.3
act konsole
sleep 0.5
pfinput 'key meta+z' 'sleep 1' 'key 4' 'sleep 0.5' 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 2.5
state "$OUT/s28.json"
first=$(middle_window "$OUT/s28.json")
info "placed in the middle third first: ${first:-none}"
[ -n "$first" ] && move_away "$first"
sleep 1
pfinput 'key enter'
sleep 1.5
pfinput 'key enter'
sleep 1.5
pfinput 'key esc'
sleep 1.5
state "$OUT/s29.json"
judge thirdother "$OUT/s29.json" "a third whose window a script moved out is offered again" "${first:-none}"

grep -a 'plasmafusion-snap' "$OUT/kwin.log" | grep -aE 'Error|error:' | tail -5 >>"$CHK" || true
# The verdict: every check runs, and the scenario's status says whether any failed.
failed=$(grep -c '^FAIL' "$CHK" || true)
info "verdict: $(grep -c '^PASS' "$CHK" || true) passed, $failed failed"
info "done"
trap - ERR
set +e
[ "$failed" = 0 ]
