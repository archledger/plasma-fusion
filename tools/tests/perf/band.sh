#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Rubber-band selection with 20, 60 and 100 desktop icons (BACKLOG S5; decides whether the upstream
# Folder View fix is needed), run from the laptop in private sessions on the test host.
#
#   band.sh [--stage DIR] [--runs N] [--name NAME] [--work DIR] [--size WxH] [--scale S]
#
#   defaults: <repo>/stage/home, 3 runs, name band, <repo>/build/tests/band, 1920x1200 at 1.333333
#
# Each run is one session (scen-band.sh): Plasma Fusion installed, the desktop a Folder View (the
# layout's, or the BACKLOG M1 settings written by the test), then a 3 s band sweep over 20, 60 and
# 100 icons with pfstat.py snapshots and KWin's frame log. band.py prints the table. Each run holds
# every session slot and the build lock (a quiet host; tools/tests/lib/common.sh, slot_prefix).
# Exit status: 0 the 100-icon budget holds (<= 15 % plasmashell CPU, 0 late frames), 1 it does
# not, 2 setup error or no usable run.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
# shellcheck source=tools/tests/lib/common.sh
source "$HERE/../lib/common.sh"
STAGE=$ROOT/stage/home; RUNS=3; NAME=band; WORK=$ROOT/build/tests/band; SIZE=1920x1200; SCALE=1.333333
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE=$2; shift 2 ;;
    --runs) RUNS=$2; shift 2 ;;
    --name) NAME=$2; shift 2 ;;
    --work) WORK=$2; shift 2 ;;
    --size) SIZE=$2; shift 2 ;;
    --scale) SCALE=$2; shift 2 ;;
    -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[ -d "$STAGE/.local/share/plasma" ] || { echo "no built HOME tree at $STAGE (run tools/build.sh)" >&2; exit 2; }
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bad session name $NAME" >&2; exit 2; }
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || { echo "bad --runs $RUNS" >&2; exit 2; }
slot_prefix exclusive || exit 2
mkdir -p "$WORK" || exit 2
WORK=$(cd "$WORK" && pwd)
RES=$WORK/results
rm -rf "$RES" "$WORK/vsession-out"; mkdir -p "$RES/runs"
make_seed "$STAGE" "$ROOT/tools" "$WORK/seed" || { echo "seed failed" >&2; exit 2; }
mkdir -p "$WORK/seed/.config"
printf 'KWIN_LOG_PERFORMANCE_DATA=1\n' >"$WORK/seed/.config/pfv-env"
T0=$(hssh 'date +%s') || { echo "host $HOST not reachable" >&2; exit 2; }
# shellcheck disable=SC2046
if session_in_use $(for i in $(seq 1 "$RUNS"); do echo "$NAME-$i"; done); then
  echo "a session named $NAME-N is running on $HOST; choose another --name" >&2; exit 2
fi
slot_note | tee "$RES/slot.txt"
host_packages >"$RES/packages.txt"
cd "$WORK" || exit 2
cur=
trap 'echo "interrupted; cleaning up $cur on $HOST"; [ -n "$cur" ] && host_cleanup "$cur"; exit 130' INT TERM
for i in $(seq 1 "$RUNS"); do
  echo "== run $i/$RUNS ($(date +%T)) $(host_state)"
  cur=$NAME-$i
  run_remote "$RES/remote-$i.log" "$cur" "${SLOT[@]}" env PFV_SCALE="$SCALE" PFV_CWD=out \
    bash "$ROOT/tools/vsession/remote.sh" "$cur" "$HERE/scen-band.sh" "$WORK/seed" "$SIZE" 300 \
    || echo "   run $i: remote.sh failed (see $RES/remote-$i.log)"
  [ -d "vsession-out/$cur" ] && mv "vsession-out/$cur" "$RES/runs/$cur"
  host_cleanup "$cur"; cur=
done
trap - INT TERM
for i in $(seq 1 "$RUNS"); do host_coredumps "$T0" "/var/tmp/pfv-$NAME-$i/run"; done \
  | python3 -c 'import json,sys; print(json.dumps([d for l in sys.stdin for d in json.loads(l)]))' >"$RES/coredumps.json"
echo "core dumps of these sessions: $(cat "$RES/coredumps.json")"
python3 "$HERE/band.py" "$RES"/runs/* | tee "$RES/table.md"
rc=${PIPESTATUS[0]}
[ "$(cat "$RES/coredumps.json")" = "[]" ] || rc=1
echo "results: $RES (table.md, band.json, runs/*)"
exit "$rc"
