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
#   6. the halves flow from an edge snap (Meta+Left) still pairs its two windows.
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
      out.push({cls: String(c.resourceClass), x: g.x, y: g.y, w: g.width, h: g.height, tiled: !!c.tile,
                min: c.minimized, z: i}); }
    var a = workspace.clientArea(KWin.MaximizeArea, workspace.activeScreen, workspace.currentDesktop);
    report({wins: out, area: {x: a.x, y: a.y, w: a.width, h: a.height}});" >"$1"
}
# The newest normal window whose class contains CLASS: made active, minimised or restored.
act() { # CLASS
  K run "var l = workspace.windowList(), w = null;
    for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('$1') >= 0) { w = l[i]; } }
    if (w) { workspace.activeWindow = w; } report(w ? String(w.resourceClass) : null);" >>"$OUT/act.log"
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

grep -a 'plasmafusion-snap' "$OUT/kwin.log" | grep -aE 'Error|error:' | tail -5 >>"$CHK" || true
# The verdict: every check runs, and the scenario's status says whether any failed.
failed=$(grep -c '^FAIL' "$CHK" || true)
info "verdict: $(grep -c '^PASS' "$CHK" || true) passed, $failed failed"
info "done"
trap - ERR
set +e
[ "$failed" = 0 ]
