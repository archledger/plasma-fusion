# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Idle frames per power tier (POWER-1 acceptance, EFFECTS.md 8.4 and 5), sourced by vsession.sh in a
# session started with PFV_CWD=out and KWIN_LOG_PERFORMANCE_DATA=1 in the seed's .config/pfv-env
# (KWin's per-frame CSV lands in out/). Same seed as scen-tiers.sh plus the tools tree's
# tests/perf/pfstat.py. Run it on a quiet host (build/lead/vslot.sh --exclusive).
# Phases of 30 s, pointer parked mid-screen, each after a settle:
#   full-visible, critical-visible (system card on the desktop), critical-covered (a maximized
#   Dolphin over it: a window without a blinking text cursor), full-covered, then without the
#   system card: critical-nocard, full-nocard.
# marks.jsonl brackets each phase; stats.jsonl has pfstat.py snapshots (CPU of plasmashell, KWin);
# analyse with packages/powerfx/tests/vsession/idle-frames.py OUT_DIR.
# shellcheck shell=bash
exec 2>&1
export OUT KWIN_PID=$PPID
PFX=$HOME/.local/libexec/plasma-fusion/plasma-fusion-powerfx
S() { python3 "$HOME/pf-tools/tests/perf/pfstat.py" "$1"; }
M() { python3 -c 'import json,time,sys; open(sys.argv[1],"a").write(json.dumps({"mark":sys.argv[2],"epoch":time.time(),"mono":time.monotonic()})+"\n")' "$OUT/marks.jsonl" "$1"; }
# the service's journal lines into out/, not the machine's journal
mkdir -p "$PFV/bin"
printf '#!/bin/sh\nshift 2; [ "$1" = -- ] && shift; echo "$(date +%%T.%%3N) $*" >>%s\n' "$OUT/journal.log" >"$PFV/bin/logger"
chmod +x "$PFV/bin/logger"
export PATH=$PFV/bin:$PATH
phase() { # NAME: 30 s idle, bracketed
  M "$1-0"; S "$1-0"; sleep 30; S "$1-1"; M "$1-1"
}
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fusion-config.log" 2>&1
echo "fusion-config rc=$?" >>"$OUT/fusion-config.log"
kquitapp6 plasmashell >/dev/null 2>&1; sleep 2
plasmashell >>"$OUT/plasmashell2.log" 2>&1 &
wait_for_name org.kde.plasmashell
qdbus org.kde.KWin /KWin reconfigure
read -r W H < <(python3 "$HOME/pf-tools/tests/lib/pfkwin.py" windows | python3 -c 'import json,sys; o=json.load(sys.stdin)["outputs"][0]["geo"]; print(o["w"], o["h"])')
pfinput "move $((W / 2)) $((H / 2))"
sleep 25
echo "screen ${W}x$H" >"$OUT/arm.txt"
phase full-visible
bash "$PFX" --apply critical >>"$OUT/apply.log" 2>&1; sleep 8
phase critical-visible
shot critical-visible
dolphin "$HOME" >/dev/null 2>&1 &
sleep 5
for _ in 1 2 3 4 5; do
  python3 "$HOME/pf-tools/tests/lib/pfkwin.py" maximize org.kde.dolphin >"$OUT/maximize.json" 2>>"$OUT/apply.log"
  grep -q '"maximized": "' "$OUT/maximize.json" && break
  sleep 1
done
pfinput "move $((W / 2)) $((H / 2))"
sleep 8
phase critical-covered
shot critical-covered
bash "$PFX" --apply full >>"$OUT/apply.log" 2>&1; sleep 8
phase full-covered
python3 "$HOME/pf-tools/tests/lib/pfkwin.py" close org.kde.dolphin >>"$OUT/apply.log" 2>&1
evaljs - >>"$OUT/apply.log" <<'JS'
var ds = desktops(); for (var i = 0; i < ds.length; i++) { var ws = ds[i].widgets("org.plasmafusion.systemcard");
  for (var j = 0; j < ws.length; j++) ws[j].remove(); }
print("system card removed");
JS
sleep 4
bash "$PFX" --apply critical >>"$OUT/apply.log" 2>&1; sleep 8
phase critical-nocard
shot critical-nocard
bash "$PFX" --apply full >>"$OUT/apply.log" 2>&1; sleep 8
phase full-nocard
M end
