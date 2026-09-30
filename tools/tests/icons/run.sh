#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Desktop icon positions and session lifecycle test (BACKLOG M2), run from the laptop against the
# test host (PFV_HOST, default thinkpad-fedora) in three private virtual sessions (tools/vsession):
#
#   run.sh [--stage DIR] [--name NAME] [--work DIR] [--scale S] [--size WxH] [--keep] [--strict]
#
#   --stage DIR   built HOME tree to test (tools/build.sh output; default <repo>/stage/home)
#   --name NAME   virtual session name (default icons; the host directory is /var/tmp/pfv-NAME)
#   --work DIR    seed, raw session output and the summary (default <repo>/build/tests/icons)
#   --scale S     display scale of the virtual output (default 1.333333, logical 1440x900)
#   --size WxH    virtual output in device pixels (default 1920x1200, the ThinkPad panel)
#   --keep        keep the session directory on the host after the last session
#   --strict      fail a step whose positions entry Plasma rewrote even when every icon kept its cell
#
# Session 1 installs Plasma Fusion, switches the desktop to Folder View with 12 files, drags six
# of them into a pattern (one at column 5, row 4) and saves the baseline; then after each of:
# plasmashell restart, KWin reconfigure, scale 4/3 -> 1 -> 4/3, portrait and back, dock hidden by
# a maximised window, dock auto-hide on and off, it compares the positions entry of the original
# resolution byte for byte and cell by cell, the icon area of the screenshot, the desktop cards,
# open pop-ups and core dumps.
# Session 2 is a new session on the same HOME; session 3 adds a second output and disables and
# re-enables the first one. Result table: WORK/results/summary.md; exit 0 all steps pass, 1 a step
# failed, 2 the setup failed. Runtime about 4 minutes. Step results: PASS (entry byte-identical to
# the one before the step), REWRITTEN (the step saved the entry again, every icon in its cell and
# unchanged on screen), FAIL.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
# shellcheck source=tools/tests/lib/common.sh
source "$HERE/../lib/common.sh"
STAGE=$ROOT/stage/home; NAME=icons; WORK=$ROOT/build/tests/icons; SCALE=1.333333; SIZE=1920x1200; KEEP=0; STRICT=
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE=$2; shift 2 ;;
    --name) NAME=$2; shift 2 ;;
    --work) WORK=$2; shift 2 ;;
    --scale) SCALE=$2; shift 2 ;;
    --size) SIZE=$2; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --strict) STRICT=--strict; shift ;;
    -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[ -d "$STAGE/.local/share/plasma" ] || { echo "no built HOME tree at $STAGE (run tools/build.sh)" >&2; exit 2; }
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bad session name $NAME" >&2; exit 2; }
mkdir -p "$WORK" || exit 2
WORK=$(cd "$WORK" && pwd)
RES=$WORK/results
rm -rf "$RES" "$WORK/vsession-out"; mkdir -p "$RES"
make_seed "$STAGE" "$ROOT/tools" "$WORK/seed" || { echo "seed failed" >&2; exit 2; }
T0=$(hssh 'date +%s') || { echo "host $HOST not reachable" >&2; exit 2; }
if session_in_use "$NAME"; then
  echo "a session named $NAME is running on $HOST (or the host did not answer); choose another --name" >&2
  exit 2
fi
echo "start: $(host_state)" | tee "$RES/host.txt"
host_packages >"$RES/packages.txt"
cd "$WORK" || exit 2
# Interrupted: stop the session and remove its directory on the host (it would stay until the
# timeout and keep ~100 MB in /var/tmp).
trap 'echo "interrupted; cleaning up $NAME on $HOST"; host_cleanup "$NAME"; exit 130' INT TERM
run_session() {  # N SCENARIO SEED TIMEOUT [ENV...]
  local n=$1 scen=$2 seed=$3 tmo=$4; shift 4
  echo "== session $n ($(date +%T))"
  run_remote "$RES/remote-$n.log" "$NAME" \
    env PFV_SCALE="$SCALE" "$@" bash "$ROOT/tools/vsession/remote.sh" "$NAME" "$HERE/$scen" "$seed" "$SIZE" "$tmo"
  local rc=$?
  [ -d "vsession-out/$NAME" ] && mv "vsession-out/$NAME" "$RES/$n"
  grep -h '^\[' "$RES/$n/steps.log" 2>/dev/null | grep -v '^\[.*\] check ' | sed 's/^/   /'
  return "$rc"
}
# Sessions 2 and 3 reuse the HOME session 1 left; without it they would test a fresh HOME.
if run_session 1 scen-1.sh "$WORK/seed" 330 PFV_KEEP=1; then
  run_session 2 scen-2.sh - 120 PFV_KEEP=1 || echo "session 2: remote.sh failed, see $RES/remote-2.log"
  run_session 3 scen-3.sh - 150 PFV_OUTPUTS=2 PFV_KEEP="$KEEP" || echo "session 3: remote.sh failed, see $RES/remote-3.log"
else
  echo "session 1: remote.sh failed, see $RES/remote-1.log; sessions 2 and 3 skipped"
fi
echo "end: $(host_state)" | tee -a "$RES/host.txt"
# remote.sh removes the host directory after the last session; also after a failed one.
trap - INT TERM
[ "$KEEP" = 1 ] || host_cleanup "$NAME"
host_coredumps "$T0" "/var/tmp/pfv-$NAME/run" >"$RES/coredumps.json"
echo
python3 "$HERE/report.py" "$RES" $STRICT
rc=$?
echo "results: $RES (summary.md, summary.json, per-session state-*.json and screenshots)"
exit "$rc"
