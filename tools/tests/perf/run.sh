#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Performance gate (BACKLOG M6), run from the laptop: measures a built Plasma Fusion HOME tree in
# private virtual sessions on the test host (PFV_HOST, default thinkpad-fedora) with the BACKLOG
# section 8 method, compares the result with the section 7 budget and the stored baseline, prints
# the table and exits non-zero on a regression beyond noise.
#
#   run.sh [--stage DIR] [--runs N] [--name NAME] [--work DIR] [--size WxH] [--scale S]
#          [--baseline FILE] [--save-baseline] [--label TEXT] [--strict-budget] [--quiet-wait SEC]
#
#   --stage DIR       built HOME tree (tools/build.sh output; default <repo>/stage/home)
#   --runs N          sessions to measure (default 3; about 3 minutes each)
#   --name NAME       session name prefix (default perf; sessions NAME-1..N in /var/tmp on the host)
#   --work DIR        seed, raw data and results (default <repo>/build/tests/perf)
#   --size, --scale   virtual output (default 1920x1200 at 1.333333, the ThinkPad panel at 4/3)
#   --baseline FILE   baseline to compare with (default tools/tests/perf/baseline.json)
#   --save-baseline   write this result as the baseline file (after a clean measurement)
#   --label TEXT      what was measured (for example the commit), stored with the result
#   --strict-budget   also fail when a budget row fails (today most rows do; see docs/parts/testing.md)
#   --quiet-wait SEC  before each run, wait up to SEC seconds (default 600) until no other virtual
#                     session runs on the host; a run that saw another session is marked noisy
#
# Exit status: 0 no regression, 1 regression (or budget failure with --strict-budget), 2 setup
# error, 3 no usable run, 4 the baseline is for another geometry, 5 worse than the baseline only in
# runs that overlapped another virtual session (not counted as a regression; re-run when quiet).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
# shellcheck source=tools/tests/lib/common.sh
source "$HERE/../lib/common.sh"
STAGE=$ROOT/stage/home; RUNS=3; NAME=perf; WORK=$ROOT/build/tests/perf; SIZE=1920x1200; SCALE=1.333333
BASELINE=$HERE/baseline.json; SAVE=0; LABEL=; STRICT=(); QUIET=600
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE=$2; shift 2 ;;
    --runs) RUNS=$2; shift 2 ;;
    --name) NAME=$2; shift 2 ;;
    --work) WORK=$2; shift 2 ;;
    --size) SIZE=$2; shift 2 ;;
    --scale) SCALE=$2; shift 2 ;;
    --baseline) BASELINE=$2; shift 2 ;;
    --save-baseline) SAVE=1; shift ;;
    --label) LABEL=$2; shift 2 ;;
    --strict-budget) STRICT=(--strict-budget); shift ;;
    --quiet-wait) QUIET=$2; shift 2 ;;
    -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[ -d "$STAGE/.local/share/plasma" ] || { echo "no built HOME tree at $STAGE (run tools/build.sh)" >&2; exit 2; }
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bad session name $NAME" >&2; exit 2; }
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || { echo "bad --runs $RUNS" >&2; exit 2; }
[ -n "$LABEL" ] || LABEL=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)
mkdir -p "$WORK" || exit 2
WORK=$(cd "$WORK" && pwd)
RES=$WORK/results
rm -rf "$RES" "$WORK/vsession-out"; mkdir -p "$RES/runs"
make_seed "$STAGE" "$ROOT/tools" "$WORK/seed" || { echo "seed failed" >&2; exit 2; }
# KWin's per-frame CSV (render start/end, presentation) and the window log of winmon.js.
mkdir -p "$WORK/seed/.config"
printf 'KWIN_LOG_PERFORMANCE_DATA=1\nQT_LOGGING_RULES=kwin_scripting.debug=true\n' >"$WORK/seed/.config/pfv-env"
T0=$(hssh 'date +%s') || { echo "host $HOST not reachable" >&2; exit 2; }
# shellcheck disable=SC2046  # one name per run
if session_in_use $(for i in $(seq 1 "$RUNS"); do echo "$NAME-$i"; done); then
  echo "a session named $NAME-N is running on $HOST (or the host did not answer); choose another --name" >&2
  exit 2
fi
cd "$WORK" || exit 2

# wait_quiet: until no other virtual session is on the host (at most QUIET seconds).
wait_quiet() {
  local end=$((SECONDS + QUIET)) s
  while :; do
    s=$(host_state) || return 0
    case "$s" in *"sessions=" | *"sessions= ") return 0 ;; esac
    [ "$SECONDS" -ge "$end" ] && { echo "   host still busy after ${QUIET}s: $s"; return 0; }
    sleep 20
  done
}
: >"$RES/host.jsonl"
host_packages >"$RES/packages.txt"
cur=
trap 'echo "interrupted; cleaning up $cur on $HOST"; [ -n "$cur" ] && host_cleanup "$cur"; exit 130' INT TERM
for i in $(seq 1 "$RUNS"); do
  wait_quiet
  before=$(host_state)
  echo "== run $i/$RUNS ($(date +%T)) $before"
  cur=$NAME-$i
  run_remote "$RES/remote-$i.log" "$NAME-$i" env PFV_SCALE="$SCALE" PFV_CWD=out \
    bash "$ROOT/tools/vsession/remote.sh" "$NAME-$i" "$HERE/scen-perf.sh" "$WORK/seed" "$SIZE" 420 \
    || echo "   run $i: remote.sh failed (see $RES/remote-$i.log)"
  after=$(host_state)
  echo "   done $(date +%T) $after"
  printf '{"run": "%s-%s", "before": "%s", "after": "%s"}\n' "$NAME" "$i" "$before" "$after" >>"$RES/host.jsonl"
  [ -d "vsession-out/$NAME-$i" ] && mv "vsession-out/$NAME-$i" "$RES/runs/$NAME-$i"
  # remote.sh removes the host directory; also after a failed run
  host_cleanup "$NAME-$i"; cur=
done
trap - INT TERM
for i in $(seq 1 "$RUNS"); do
  host_coredumps "$T0" "/var/tmp/pfv-$NAME-$i/run"
done | python3 -c 'import json,sys; print(json.dumps([d for l in sys.stdin for d in json.loads(l)]))' >"$RES/coredumps.json"
echo "core dumps of these sessions: $(cat "$RES/coredumps.json")"
echo
# A new baseline is not compared with the old one (it may be for another geometry).
CMP=$BASELINE; [ "$SAVE" = 1 ] && CMP=
python3 "$HERE/gate.py" --geometry "$SIZE@$SCALE" --baseline "$CMP" --label "$LABEL" --host "$RES/host.jsonl" \
  --packages "$RES/packages.txt" --save "$RES/result.json" "${STRICT[@]}" "$RES"/runs/* | tee "$RES/table.md"
rc=${PIPESTATUS[0]}
if [ "$SAVE" = 1 ] && [ -s "$RES/result.json" ]; then
  cp "$RES/result.json" "$BASELINE" && echo "baseline written: $BASELINE"
fi
echo "results: $RES (table.md, result.json, runs/*)"
exit "$rc"
