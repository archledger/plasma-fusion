#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# coverage_status.sh against stand-in tables: all green exits 0 silently, one failed row exits 1
# with the row on one line, several failures keep their grouping, a missing table is a usage
# error. The regression test for the coverage job's failed-row contract (2026-10-13).
#
#   tools/tests/coverage-status-unit.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
checks=0
pass() { checks=$((checks + 1)); echo "PASS $*"; }
fail() { echo "FAIL $*" >&2; exit 1; }

printf 'a\t0\t3\nb\t0\t5\n' >"$WORK/green.tsv"
out=$(bash "$HERE/coverage_status.sh" "$WORK/green.tsv" 2>&1) && [ -z "$out" ] \
  && pass "all green: exit 0, nothing printed" || fail "all green printed: $out"

printf 'a\t0\t3\nb\t1\t5\nc\t0\t2\n' >"$WORK/red.tsv"
set +e
out=$(bash "$HERE/coverage_status.sh" "$WORK/red.tsv" 2>&1)
rc=$?
set -e
[ "$rc" = 1 ] && pass "one failed row: exit 1" || fail "one failed row: exit $rc"
printf '%s\n' "$out" | grep -qx '  b (exit 1)' \
  && pass "the failed row prints on one line" || fail "the row printed as: $out"

printf 'a\t2\t3\nb\t1\t5\n' >"$WORK/two.tsv"
set +e
out=$(bash "$HERE/coverage_status.sh" "$WORK/two.tsv" 2>&1)
rc=$?
set -e
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -qx '  a (exit 2)' \
  && printf '%s\n' "$out" | grep -qx '  b (exit 1)' \
  && pass "two failures keep their grouping" || fail "two failures printed: $out"

set +e
bash "$HERE/coverage_status.sh" "$WORK/missing.tsv" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = 2 ] && pass "a missing table: exit 2" || fail "missing table: exit $rc"

set +e
bash "$HERE/coverage_status.sh" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" = 2 ] && pass "no argument: exit 2" || fail "no argument: exit $rc"

echo "coverage-status: $checks checks passed"
