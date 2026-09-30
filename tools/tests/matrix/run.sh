#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Adaptive test matrix (ADAPTIVE.md section 11, the INT-1 subset), run from the laptop against the
# test host (PFV_HOST, default thinkpad-fedora): one private virtual session per configuration of
# configs.txt, each installing Plasma Fusion from a built HOME tree and walking through the desktop,
# dock, launcher, quick settings, clock, Dolphin, Konsole, Alt+Tab, snap layouts and a
# notification, plus the configuration's own steps (body.sh). Sessions run as the ThinkPad's
# Fedora session does (PFV_KDE_PROFILE=1: plasma-keyboard is the input method; PFV_SHELL=/bin/bash).
# check.py judges the layout of every
# step (widgets inside their screen and clear of the panels and each other, panel applets inside
# their panel, pop-ups on the right screen), the configuration's settings, touch targets (tablet
# configurations) and core dumps.
#
#   run.sh [--stage DIR] [--configs ID,ID...|all] [--name PREFIX] [--work DIR] [--jobs N] [--list]
#
#   --stage DIR     built HOME tree (tools/build.sh output; default <repo>/stage/home)
#   --configs LIST  configuration IDs (default all of configs.txt)
#   --name PREFIX   session name prefix (default mx; sessions PREFIX-<id>, /var/tmp/pfv-PREFIX-<id>)
#   --work DIR      seed, raw session output and results (default <repo>/build/tests/matrix)
#   --jobs N        configurations run at the same time, one session slot each (default 1)
#   --list          print the configurations and exit
#
# Each session runs in one session slot of build/lead/vslot.sh (tools/tests/lib/common.sh); a
# driver started under vslot.sh runs its sessions in that slot (then --jobs is 1).
# Results: WORK/results/<ID>/ (screenshots, state-*.json, logs, checks.json), WORK/results/summary.md
# and summary.json. About 2.5 minutes per configuration. Exit status: 0 every check passed (checks
# that no widget can answer yet are NOT RUN, not failures), 1 a check failed, 2 setup error or a
# configuration without result.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
# shellcheck source=tools/tests/lib/common.sh
source "$HERE/../lib/common.sh"
STAGE=$ROOT/stage/home; CONFIGS=all; NAME=mx; WORK=$ROOT/build/tests/matrix; JOBS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE=$2; shift 2 ;;
    --configs) CONFIGS=$2; shift 2 ;;
    --name) NAME=$2; shift 2 ;;
    --work) WORK=$2; shift 2 ;;
    --jobs) JOBS=$2; shift 2 ;;
    --list) grep -v '^#' "$HERE/configs.txt" | grep -v '^$'; exit 0 ;;
    -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[ -d "$STAGE/.local/share/plasma" ] || { echo "no built HOME tree at $STAGE (run tools/build.sh)" >&2; exit 2; }
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bad session name $NAME" >&2; exit 2; }
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo "bad --jobs $JOBS" >&2; exit 2; }
mapfile -t ROWS < <(grep -v -e '^#' -e '^[[:space:]]*$' "$HERE/configs.txt")
IDS=()
for r in "${ROWS[@]}"; do IDS+=("${r%% *}"); done
if [ "$CONFIGS" != all ]; then
  want=(); IFS=, read -r -a want <<<"$CONFIGS"
  for id in "${want[@]}"; do
    printf '%s\n' "${IDS[@]}" | grep -qx "$id" || { echo "unknown configuration $id (--list)" >&2; exit 2; }
  done
  IDS=("${want[@]}")
fi
slot_prefix one || exit 2
[ ${#SLOT[@]} -eq 0 ] && pf_vslot >/dev/null && JOBS=1  # one inherited slot
mkdir -p "$WORK" || exit 2
WORK=$(cd "$WORK" && pwd)
RES=$WORK/results
rm -rf "$RES" "$WORK/vsession-out" "$WORK/scen"; mkdir -p "$RES" "$WORK/scen"
make_seed "$STAGE" "$ROOT/tools" "$WORK/seed" || { echo "seed failed" >&2; exit 2; }
T0=$(hssh 'date +%s') || { echo "host $HOST not reachable" >&2; exit 2; }
names=(); for id in "${IDS[@]}"; do names+=("$NAME-${id,,}"); done
if session_in_use "${names[@]}"; then
  echo "a session named $NAME-<id> is running on $HOST (or the host did not answer); choose another --name" >&2
  exit 2
fi
{ echo "start: $(host_state)"; slot_note; } | tee "$RES/host.txt"
host_packages >"$RES/packages.txt"
cd "$WORK" || exit 2
trap 'echo "interrupted; cleaning up"; host_cleanup "${names[@]}"; exit 130' INT TERM

run_config() {  # ID
  local id=$1 row size scale outs flags n env=()
  row=$(printf '%s\n' "${ROWS[@]}" | awk -v id="$id" '$1 == id')
  read -r _ size scale outs flags _ <<<"$row"
  n=$NAME-${id,,}
  { echo "MX_ID=$id"; echo "MX_FLAGS=${flags/#-/}"; cat "$HERE/body.sh"; } >"$WORK/scen/$id.sh"
  # as the ThinkPad's Fedora session: kde-profile (plasma-keyboard as the input method), SHELL
  env+=(PFV_KDE_PROFILE=1 PFV_SHELL=/bin/bash)
  case ",$flags," in *,tablet,*) env+=(PFV_TABLET=on) ;; esac
  echo "== $id ($(date +%T)): $size @$scale x$outs ${flags}"
  run_remote "$RES/remote-$id.log" "$n" "${SLOT[@]}" env PFV_SCALE="$scale" PFV_OUTPUTS="$outs" "${env[@]}" \
    bash "$ROOT/tools/vsession/remote.sh" "$n" "$WORK/scen/$id.sh" "$WORK/seed" "$size" 360 \
    || echo "   $id: remote.sh failed (see $RES/remote-$id.log)"
  if [ -d "vsession-out/$n" ]; then rm -rf "${RES:?}/$id"; mv "vsession-out/$n" "$RES/$id"; fi
  host_cleanup "$n"
  mkdir -p "$RES/$id"
  host_coredumps "$T0" "/var/tmp/pfv-$n/run" >"$RES/$id/coredumps.json"
  printf '%s\n' "$row" >"$RES/$id/config.txt"
  echo "   $id done ($(date +%T))"
}
for id in "${IDS[@]}"; do
  if [ "$JOBS" -gt 1 ]; then
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
    run_config "$id" &
    sleep 5
  else
    run_config "$id"
  fi
done
wait
trap - INT TERM
echo "end: $(host_state)" | tee -a "$RES/host.txt"
echo
python3 "$HERE/check.py" "$RES" "${IDS[@]}"
rc=$?
echo "results: $RES (summary.md, summary.json, <ID>/checks.json and screenshots)"
exit "$rc"
