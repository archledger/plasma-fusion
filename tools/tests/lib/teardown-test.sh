#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Self-test of vsession.sh's teardown under a strict-mode scenario (no session, no KWin).
# vsession.sh sources the scenario, so whatever its preamble sets - errexit, pipefail, an ERR trap
# (with errtrace in one scenario), xtrace, its own IFS - is still set when the session shell's EXIT
# trap runs pfv_teardown. The sweep then races processes that end on their own: one that exits
# between the listing and the moment the sweep reads or signals it must neither end the teardown
# before it stopped the rest and wrote out/teardown.log nor be reported by the scenario's ERR trap.
#
# Each round runs the real teardown functions, cut from vsession.sh, in a shell with such a
# preamble, rotating three so each cause shows on its own: `set -euo pipefail` alone (fast enough
# for the sweep to meet processes that end mid-sweep), errtrace with an ERR trap and xtrace, and
# that with the strict-mode IFS idiom. Use a multiple of 3 rounds to run all three equally.
# The shell holds long-lived session processes and a stream of short-lived ones that their parents
# reap at once, all marked with the session's XDG_RUNTIME_DIR as a real session's are. A round
# passes when the shell exits 0, teardown.log ends with "done; left: none", the ERR trap never ran
# and the long-lived processes are gone. Two final checks call cleanup in the middle of a scenario,
# with and without errtrace: the scenario's options, ERR and TERM traps and IFS must survive it.
#
#   teardown-test.sh [--rounds N] [--work DIR]
#   (default 30 rounds in <repo>/build/tests/teardown-test)
# Exit status: 0 all checks passed, 1 a check failed, 2 setup error.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
ROUNDS=30
WORK=$ROOT/build/tests/teardown-test
while [ $# -gt 0 ]; do
  case "$1" in
    --rounds) ROUNDS=${2:?}; shift 2 ;;
    --work) WORK=${2:?}; shift 2 ;;
    *) echo "usage: teardown-test.sh [--rounds N] [--work DIR]" >&2; exit 2 ;;
  esac
done
if ! [[ $ROUNDS =~ ^[1-9][0-9]*$ ]]; then
  echo "teardown-test: --rounds must be a positive number" >&2
  exit 2
fi
# The work directory is deleted first: only ever one this test made.
if [ -e "$WORK" ] && [ ! -e "$WORK/.teardown-test" ]; then
  echo "teardown-test: $WORK exists and is not a teardown-test work directory" >&2
  exit 2
fi

# The teardown as the session shell defines it: from pfv_alive to the EXIT trap, inclusive.
FUNCS=$(sed -n '/^pfv_alive() /,/^trap pfv_teardown EXIT$/p' "$ROOT/tools/vsession/vsession.sh")
case "$FUNCS" in
  *'pfv_teardown() {'*'trap pfv_teardown EXIT') ;;
  *) echo "teardown-test: teardown functions not found in vsession.sh" >&2; exit 2 ;;
esac
# Scenario preambles: as the repository's scenarios write them, and with the strict-mode IFS idiom.
# The text is evaluated later inside the session shell, so it must not expand here.
STRICT='set -euo pipefail'
PREAMBLE='set -Eeuxo pipefail; '
# shellcheck disable=SC2016
PREAMBLE+='trap '"'"'echo "ERR at $LINENO: $BASH_COMMAND" >>"$PFV/err.log"'"'"' ERR'
STRICT_IFS="$PREAMBLE; IFS=\$'\\n\\t'"

rm -rf "$WORK"
mkdir -p "$WORK"
touch "$WORK/.teardown-test"
failed=0
rounds_run=0
mid_run=0
for ((round = 1; round <= ROUNDS; round++)); do
  rounds_run=$((rounds_run + 1))
  PFV=$WORK/round-$round
  case $((round % 3)) in
    1) preamble=$STRICT kind=errexit ;;
    2) preamble=$PREAMBLE kind=errtrace+xtrace ;;
    0) preamble=$STRICT_IFS kind=strict-IFS ;;
  esac
  mkdir -p "$PFV/run" "$PFV/out"
  # The session shell: the preamble as a sourced scenario leaves it, then the teardown trap. Only
  # its children carry the session's XDG_RUNTIME_DIR, so the sweep selects them and spares the
  # shell.
  rc=0
  PFV=$PFV bash -c '
    eval "$2"
    OUT=$PFV/out
    eval "$1"
    for _ in 1 2 3; do XDG_RUNTIME_DIR=$PFV/run sleep 300 & done
    # Each lives about as long as the sweep takes to list the session processes, so some are
    # listed and then gone before they are read or stopped.
    for _ in {1..12}; do XDG_RUNTIME_DIR=$PFV/run bash -c "while :; do sleep 0.02; done" & done
    sleep 0.3
    jobs -p >"$PFV/jobs.pid"
  ' teardown-session "$FUNCS" "$preamble" >"$PFV/session.log" 2>&1 || rc=$?
  last=
  if [ -f "$PFV/out/teardown.log" ]; then
    last=$(tail -n 1 "$PFV/out/teardown.log")
  fi
  left=
  if [ -f "$PFV/jobs.pid" ]; then
    while read -r pid; do
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        left+=" $pid"
      fi
    done <"$PFV/jobs.pid"
  else
    left=" <no jobs.pid: the session shell did not start its processes>"
  fi
  if [ "$rc" = 0 ] && [[ $last == *" done; left: none" ]] && [ ! -s "$PFV/err.log" ] \
    && [ -z "$left" ]; then
    rm -rf "$PFV"
  else
    failed=$((failed + 1))
    err_runs=0
    if [ -f "$PFV/err.log" ]; then
      err_runs=$(wc -l <"$PFV/err.log")
    fi
    echo "round $round ($kind): shell exit $rc, last teardown line '${last:-<no teardown.log>}'," \
      "ERR trap runs $err_runs, still running:${left:- none}"
    # A failed teardown leaves its processes: stop them here so nothing outlives the test.
    for pid in $left; do
      if [[ $pid =~ ^[0-9]+$ ]]; then
        kill -KILL "$pid" 2>/dev/null || true
      fi
    done
  fi
done

# cleanup in the middle of a scenario: the scenario's settings must survive it, both when its ERR
# trap reaches functions (errtrace) and when bash hides it from them (no errtrace).
MID_NO_E=${STRICT_IFS/set -Eeuxo/set -euxo}
for mid in errtrace:"$STRICT_IFS" no-errtrace:"$MID_NO_E"; do
  mid_run=$((mid_run + 1))
  name=${mid%%:*}
  PFV=$WORK/mid-$name
  mkdir -p "$PFV/run" "$PFV/out"
  # A failing session shell leaves state empty or partial; the checks below then fail.
  state=$(PFV=$PFV bash -c '
    eval "$2"
    OUT=$PFV/out
    eval "$1"
    trap - EXIT
    cleanup
    pf=off; [[ -o pipefail ]] && pf=on
    printf "%s|%s|%s|%s|%s" "$-" "$pf" "$(trap -p TERM)" "$(trap -p ERR)" "$IFS"
  ' teardown-mid "$FUNCS" "${mid#*:}" 2>"$PFV/stderr.log") || true
  opts=${state%%|*}
  expect=eux
  if [ "$name" = errtrace ]; then
    expect=Eeux
  fi
  ok=1
  for ((i = 0; i < ${#expect}; i++)); do [[ $opts == *"${expect:i:1}"* ]] || ok=0; done
  case "$state" in
    *'|on||'*'ERR at'*' ERR|'$'\n\t') ;;
    *) ok=0 ;;
  esac
  if [ "$ok" = 0 ]; then
    failed=$((failed + 1))
    echo "mid-scenario cleanup ($name) changed the scenario's settings: '$state'" \
      "(stderr in $PFV/stderr.log)"
  fi
done

# A loop that ran fewer times than asked must not read as a pass.
if [ "$rounds_run" != "$ROUNDS" ] || [ "$mid_run" != 2 ]; then
  echo "teardown-test: ran $rounds_run of $ROUNDS rounds and $mid_run of 2 mid-scenario checks"
  exit 1
fi
if [ "$failed" -gt 0 ]; then
  echo "teardown-test: $failed check(s) failed (work files kept in $WORK)"
  exit 1
fi
echo "teardown-test: all $ROUNDS rounds and both mid-scenario checks passed"
