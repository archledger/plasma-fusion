#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# What the glass costs on battery (NEXT.md item 7; research D-desktop "blur battery cost unknown",
# E-phone want 1 "battery life first"): the idle desktop with the screen on, alternating KWin's blur
# effect on and off in blocks, battery power sampled every 10 s.
#
#   power-ab.sh [MINUTES_PER_BLOCK=10] [BLOCKS=8] [OUTDIR=~/.local/state/plasma-fusion/power-ab-<time>]
#
# Run in the Plasma session (for example from Konsole), on battery, then leave the machine alone:
# no input, no other load. Sleep and the screen turning off are inhibited for the run (kde-inhibit);
# brightness stays as it is. Only the blur effect changes (unloadEffect/loadEffect, the same as the
# settings module's Solid glass does on the KWin side); at the end the effect is put back as it was.
# Output: samples.tsv (time, block, blur, watts, percent, AC) and summary.txt (mean watts per state
# without each block's first minute, and the difference).
set -u
MIN=${1:-10}; BLOCKS=${2:-8}
OUT=${3:-${XDG_STATE_HOME:-$HOME/.local/state}/plasma-fusion/power-ab-$(date -u +%Y%m%dT%H%M%SZ)}
# PF_POWER_AB_FAKE=DIR (tests only): DIR/BAT0 and DIR/AC stand in for /sys/class/power_supply, and
# the blur effect is not touched (the calls are logged instead).
SYS=${PF_POWER_AB_FAKE:-/sys/class/power_supply}
BAT=$(ls -d "$SYS"/BAT* 2>/dev/null | head -1)
[ -n "$BAT" ] || { echo "power-ab: no battery" >&2; exit 2; }
AC=$(ls -d "$SYS"/A{C,DP}* 2>/dev/null | head -1)
online() { [ -n "$AC" ] && cat "$AC/online" 2>/dev/null || echo 0; }
[ "$(online)" = 0 ] || { echo "power-ab: on AC power; unplug first" >&2; exit 3; }
watts() {
  if [ -r "$BAT/power_now" ]; then
    awk '{printf "%.3f", $1 / 1e6}' "$BAT/power_now"
  else
    awk -v c="$(cat "$BAT/current_now")" -v v="$(cat "$BAT/voltage_now")" 'BEGIN{printf "%.3f", c * v / 1e12}'
  fi
}
blur() { [ -n "${PF_POWER_AB_FAKE:-}" ] && { echo true; return; }; qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded blur 2>/dev/null || qdbus org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded blur; }
setblur() { [ -n "${PF_POWER_AB_FAKE:-}" ] && { echo "setblur $1" >>"$PF_POWER_AB_FAKE/calls"; return; }; local m; m=$([ "$1" = on ] && echo loadEffect || echo unloadEffect); qdbus6 org.kde.KWin /Effects "org.kde.kwin.Effects.$m" blur >/dev/null 2>&1 || qdbus org.kde.KWin /Effects "org.kde.kwin.Effects.$m" blur >/dev/null 2>&1; }
mkdir -p "$OUT"
WAS=$(blur)
trap 'setblur "$([ "$WAS" = true ] && echo on || echo off)"; echo "power-ab: blur restored ($WAS)"' EXIT
echo -e "time\tblock\tblur\twatts\tpercent\tac" >"$OUT/samples.tsv"
echo "power-ab: $BLOCKS blocks of $MIN min, results in $OUT"
kde-inhibit --power --screenSaver bash -c '
  for b in $(seq 1 '"$BLOCKS"'); do
    state=$([ $((b % 2)) = 1 ] && echo on || echo off)
    '"$(declare -f setblur online watts)"'
    BAT='"$BAT"'; AC='"$AC"'; PF_POWER_AB_FAKE='"${PF_POWER_AB_FAKE:-}"'
    setblur "$state"
    end=$(( $(date +%s) + '"$MIN"' * 60 ))
    while [ "$(date +%s)" -lt "$end" ]; do
      [ "$(online)" = 0 ] || { echo "power-ab: AC plugged in, stopping" >&2; exit 4; }
      echo -e "$(date +%s)\t$b\t$state\t$(watts)\t$(cat "$BAT/capacity")\t$(online)" >>"'"$OUT"'/samples.tsv"
      sleep 10
    done
  done'
python3 - "$OUT" <<'PY'
import statistics, sys
rows = [l.split("\t") for l in open(sys.argv[1] + "/samples.tsv").read().splitlines()[1:]]
first = {}
for t, b, s, w, p, a in rows:
    first.setdefault(b, int(t))
data = {"on": [], "off": []}
for t, b, s, w, p, a in rows:
    if int(t) - first[b] >= 60:          # skip each block's first minute (settling)
        data[s].append(float(w))
lines = []
for s in ("on", "off"):
    v = data[s]
    if v:
        lines.append(f"blur {s}: {statistics.mean(v):.2f} W (n={len(v)}, sd {statistics.pstdev(v):.2f})")
if data["on"] and data["off"]:
    d = statistics.mean(data["on"]) - statistics.mean(data["off"])
    lines.append(f"blur costs {d:+.2f} W ({100 * d / statistics.mean(data['off']):+.1f} % of the idle draw)")
open(sys.argv[1] + "/summary.txt", "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
PY
