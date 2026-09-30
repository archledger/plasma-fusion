# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Performance gate scenario (BACKLOG M6), sourced inside a tools/vsession session started with
# PFV_CWD=out and KWIN_LOG_PERFORMANCE_DATA=1 (so KWin's per-frame CSV lands in out/). It is the
# perf-measure study's scen-perf.sh for the Fusion arm, with the pointer targets read from the live
# dock and top bar instead of fixed coordinates:
#   install Plasma Fusion, fresh plasmashell, KWin reconfigure, 30 s settle; idle 30 s with the
#   pointer mid-screen; 10 s dock hover sweep (about 98 motions/s); launcher (Meta) x3; quick settings x3;
#   Konsole + KWrite, Alt+Tab held 1.2 s x3; overview (Meta+W) x3; snapshot "end"; then KWrite
#   maximized over the desktop cards and idle 30 s again (EFFECTS.md X3: the covered case).
# pfstat.py snapshots every session process around each step (stats.jsonl), pfinput marks the
# input times (marks.jsonl), winmon.js logs window mapping and the dock windows' geometry changes
# through dbus-monitor (dbusmon.log).
# Options from ~/pf-perf.env (written by run.sh): PF_DOCK_MAGNIFY=off turns the dock's
# magnification off after the install (the E12 reference); PFSTAT_SUDO=1 lets pfstat.py read
# KWin's GPU counters with sudo -n (KWin's /proc entries are private).
# shellcheck shell=bash
exec 2>&1
[ -f "$HOME/pf-perf.env" ] && . "$HOME/pf-perf.env"
export OUT KWIN_PID=$PPID PFINPUT_MARKS=$OUT/marks.jsonl PFSTAT_SUDO=${PFSTAT_SUDO:-0}
T=$HOME/pf-tools/tests
P() { python3 "$PFV/pfinput.py" "$@" >>"$OUT/pfinput.log" 2>&1; }
S() { python3 "$T/perf/pfstat.py" "$1"; }
M() { python3 -c 'import json,time,sys; open(sys.argv[1],"a").write(json.dumps({"mark":sys.argv[2],"epoch":time.time(),"mono":time.monotonic()})+"\n")' "$PFINPUT_MARKS" "$1"; }
echo "arm=fusion kwin=$KWIN_PID" >"$OUT/arm.txt"
M begin
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fusion-config.log" 2>&1
echo "fusion-config rc=$?" >>"$OUT/fusion-config.log"
# A fresh plasmashell (what a new login gives) and a KWin reconfigure.
kquitapp6 plasmashell >/dev/null 2>&1; sleep 2
M shell-start
plasmashell >>"$OUT/plasmashell2.log" 2>&1 &
wait_for_name org.kde.plasmashell
M shell-on-bus
if [ "${PF_DOCK_MAGNIFY:-}" = off ]; then
  sleep 3
  evaljs - >>"$OUT/arm.txt" 2>&1 <<'JS'
panels().forEach(function (p) { p.widgets("org.plasmafusion.dock").forEach(function (w) {
    w.currentConfigGroup = ["General"]; w.writeConfig("magnify", false); print("dock magnify=false"); }); });
JS
fi
qdbus org.kde.KWin /KWin reconfigure
dbus-monitor "type='method_call',interface='org.freedesktop.DBus',member='NameHasOwner'" >"$OUT/dbusmon.log" 2>&1 &
sleep 0.5
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$T/perf/winmon.js" pfperf-winmon >"$OUT/winmon-id.txt" 2>&1
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.start >>"$OUT/winmon-id.txt" 2>&1
P 'move 720 450'
sleep 20
# Pointer targets from the live layout: the dock's middle line (its window includes the
# floating margin and the headroom for magnified icons) and the status pill at the top right.
python3 "$T/lib/pfkwin.py" windows >"$OUT/windows-start.json" 2>>"$OUT/errors.log"
read -r W H SWX1 SWX2 SWY QSX QSY < <(python3 - "$OUT/windows-start.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
o = d["outputs"][0]["geo"]
docks = [w["geo"] for w in d["windows"] if w["dock"]]
bottom = max(docks, key=lambda g: g["y"]) if docks else {"x": 300, "y": o["h"] - 104, "w": 840, "h": 104}
top = min(docks, key=lambda g: g["y"]) if docks else {"x": 0, "y": 0, "w": o["w"], "h": 34}
print(o["w"], o["h"], int(bottom["x"] + 10), int(bottom["x"] + bottom["w"] - 10), int(bottom["y"] + bottom["h"] / 2),
      int(top["x"] + top["w"] - 88), int(top["y"] + top["h"] / 2))
PY
)
echo "screen=${W}x$H sweep=$SWX1..$SWX2 y=$SWY qs=$QSX,$QSY" >>"$OUT/arm.txt"
MX=$((W / 2)); MY=$((H / 2))
sleep 10
S settled
# 1. idle, 30 s, pointer parked mid-screen
M idle0; S idle0; sleep 30; S idle1; M idle1
# 2. dock hover sweep, 10 s, about 98 motions/s (paced at 8 ms, each motion waits for KWin)
P "move $SWX1 $SWY" 'sleep 1'
S sweep0; P 'mark sweep0' "sweep $SWX1 $SWX2 $SWY 10" 'mark sweep1'; S sweep1
P "move $MX $MY" 'sleep 3'
# 3. launcher (Meta), 3 times
for i in 1 2 3; do
  S "launcher$i-0"; P "mark launcher$i" 'key meta' 'sleep 1.5' "mark launcher$i-close" 'key esc' 'sleep 1.5'; S "launcher$i-1"
done
# 4. quick settings (status pill), 3 times
for i in 1 2 3; do
  S "qs$i-0"; P "mark qs$i" "click $QSX $QSY" 'sleep 1.5' "mark qs$i-close" 'key esc' 'sleep 1.5'; S "qs$i-1"
done
P "move $MX $MY"
# 5. Alt+Tab with two windows open, switcher held 1.2 s, 3 times (one pfinput process presses and
#    releases Alt: KWin 6.7.5 crashes when an input client exits holding a key)
konsole >/dev/null 2>&1 &
sleep 3
kwrite >/dev/null 2>&1 &
sleep 5
S windows-open
for i in 1 2 3; do
  S "alttab$i-0"; P "mark alttab$i" 'keydown alt' 'key tab' 'sleep 1.2' "mark alttab$i-release" 'keyup alt' 'sleep 1.5'; S "alttab$i-1"
done
# 6. overview (Meta+W) open 1.5 s and close, 3 times
for i in 1 2 3; do
  S "ov$i-0"; P "mark ov$i" 'key meta+w' 'sleep 1.5' "mark ov$i-close" 'key meta+w' 'sleep 1.5'; S "ov$i-1"
done
S end
M end
# Outside the measured windows: one screenshot for the record.
shot end
# 7. idle 30 s with a maximized window over the desktop cards (the system card should pause)
python3 "$T/lib/pfkwin.py" maximize org.kde.kwrite >"$OUT/maximize.json" 2>>"$OUT/errors.log"
P "move $MX $MY"
sleep 6
M idlec0; S idlec0; sleep 30; S idlec1; M idlec1
shot covered
qdbus org.kde.KWin /KWin supportInformation >"$OUT/kwin-support-end.txt" 2>&1
