#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Self-test of the session-slot lock as the test drivers use it (laptop only; no session starts
# on the test host). It runs a copy of vslot.sh (pf_vslot, see common.sh) on a private lock
# directory with 3 slots, so the team's real slots are never taken:
#   1. three holders take the three slots; a fourth waits until one of them ends;
#   2. slot_prefix inside a holder: "one" reuses the inherited slot, "exclusive" is refused;
#   3. --exclusive waits for a running holder, and a new single-slot run waits for it;
#   4. two --build runs do not overlap.
#
#   slot-test.sh [--work DIR]      (default <repo>/build/tests/slot-test; about 90 s)
# Exit status: 0 all checks passed, 1 a check failed, 2 setup error.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
# shellcheck source=tools/tests/lib/common.sh
source "$HERE/common.sh"
WORK=$ROOT/build/tests/slot-test
[ "${1:-}" = --work ] && WORK=$2
V=$(pf_vslot) || { echo "no vslot.sh found (PFV_VSLOT)" >&2; exit 2; }
rm -rf "$WORK"; mkdir -p "$WORK/lead" "$WORK/locks" || exit 2
WORK=$(cd "$WORK" && pwd -P)
sed "s|^D=.*|D=$WORK/locks|" "$V" >"$WORK/lead/vslot.sh" && chmod +x "$WORK/lead/vslot.sh" || exit 2
grep -q "^D=$WORK/locks\$" "$WORK/lead/vslot.sh" || { echo "vslot.sh has no D= line to redirect" >&2; exit 2; }
echo 3 >"$WORK/locks/slots"
VS=$WORK/lead/vslot.sh
fail=0
ok() { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; fail=1; }
t0=$SECONDS
: >"$WORK/times"

# 1. three holders, a fourth waits. The holders start one after the other: vslot.sh probes the
#    exclusive lock with an exclusive flock, so two starts in the same instant make one of them
#    back off for 10 s (harmless, but it would blur this measurement).
for i in 1 2 3; do
  "$VS" bash -c "echo holder$i-start >>'$WORK/times'; sleep 14" &
  for _ in $(seq 1 30); do grep -q "^holder$i-start" "$WORK/times" && break; sleep 0.5; done
done
[ "$(grep -c '^holder' "$WORK/times")" = 3 ] || { bad "the three holders did not all start: $(tr '\n' ' ' <"$WORK/times")"; }
s=$(date +%s)
"$VS" bash -c "echo fourth-start \$((\$(date +%s) - $s)) >>'$WORK/times'"
w=$(awk '/^fourth-start/{print $2}' "$WORK/times")
wait
if [ "${w:-0}" -ge 9 ]; then ok "a 4th session waited ${w} s until one of 3 held slots was free"; else bad "the 4th session started after ${w:-?} s while 3 slots were held"; fi

# 2. slot_prefix inside a holder
out=$("$VS" bash -c "PFV_VSLOT='$VS'; source '$HERE/common.sh'; slot_prefix one; echo one=\${#SLOT[@]} held=\$HELD_SLOTS; slot_prefix exclusive 2>/dev/null; echo exclusive-rc=\$?")
case "$out" in *"one=0 held=1"*"exclusive-rc=1"*) ok "inside a slot: 'one' reuses it, 'exclusive' is refused ($(echo $out))" ;; *) bad "inside a slot: $out" ;; esac
out=$(PFV_VSLOT=$VS bash -c "source '$HERE/common.sh'; slot_prefix exclusive; echo \${SLOT[*]}")
case "$out" in "$VS --build $VS --exclusive") ok "outside: exclusive = build lock + all slots" ;; *) bad "outside exclusive prefix: $out" ;; esac
out=$("$VS" --build "$VS" --exclusive bash -c "PFV_VSLOT='$VS'; source '$HERE/common.sh'; slot_prefix exclusive; echo n=\${#SLOT[@]}; slot_prefix one; echo one=\${#SLOT[@]}")
case "$out" in *"n=0"*"one=0"*) ok "inside an exclusive run: nothing more is taken" ;; *) bad "inside exclusive: $out" ;; esac

# 3. exclusive waits for a holder; a single slot waits for the exclusive run
: >"$WORK/times"; s=$(date +%s)
"$VS" bash -c "sleep 12" &
sleep 1
"$VS" --exclusive bash -c "echo excl-start \$((\$(date +%s) - $s)) >>'$WORK/times'; sleep 12; echo excl-end \$((\$(date +%s) - $s)) >>'$WORK/times'" &
sleep 3
"$VS" bash -c "echo single-start \$((\$(date +%s) - $s)) >>'$WORK/times'"
wait
es=$(awk '/^excl-start/{print $2}' "$WORK/times"); ee=$(awk '/^excl-end/{print $2}' "$WORK/times"); ss=$(awk '/^single-start/{print $2}' "$WORK/times")
if [ "${es:-0}" -ge 11 ]; then ok "--exclusive waited ${es} s for the running session"; else bad "--exclusive started at ${es:-?} s next to a running session"; fi
if [ "${ss:-0}" -ge "${ee:-99}" ]; then ok "a new session waited for the exclusive run (${ss} s >= ${ee} s)"; else bad "a new session started at ${ss:-?} s during the exclusive run (${es:-?}..${ee:-?} s)"; fi

# 4. build lock
: >"$WORK/times"; s=$(date +%s)
for i in 1 2; do "$VS" --build bash -c "echo b$i-start \$((\$(date +%s) - $s)) >>'$WORK/times'; sleep 4; echo b$i-end \$((\$(date +%s) - $s)) >>'$WORK/times'" & done
wait
if python3 - "$WORK/times" <<'PY'
import sys
t = dict(l.split() for l in open(sys.argv[1]))
a = (int(t["b1-start"]), int(t["b1-end"])); b = (int(t["b2-start"]), int(t["b2-end"]))
sys.exit(0 if a[1] <= b[0] or b[1] <= a[0] else 1)
PY
then ok "two container builds ran one after the other ($(tr '\n' ' ' <"$WORK/times"))"; else bad "two builds overlapped ($(tr '\n' ' ' <"$WORK/times"))"; fi
echo "slot-test: $([ $fail = 0 ] && echo passed || echo FAILED) in $((SECONDS - t0)) s"
rm -rf "$WORK"
exit $fail
