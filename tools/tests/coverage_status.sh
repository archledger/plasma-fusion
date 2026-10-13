#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The tests' own results from a coverage run: reads tests.tsv (NAME<TAB>EXIT<TAB>SECONDS, one row
# per run_test in coverage.sh), prints the failed rows and exits 1 when there is one. coverage.sh
# calls it; tools/tests/coverage-status-unit.sh tests it.
#
#   tools/tests/coverage_status.sh TESTS_TSV
# Exit status: 0 every test passed, 1 one or more failed, 2 usage error or no such table.
set -euo pipefail
TSV=${1:?usage: coverage_status.sh TESTS_TSV}
[ -f "$TSV" ] || { echo "coverage_status.sh: no such file: $TSV" >&2; exit 2; }
failed=$(awk -F'\t' '$2 != 0 { print "  " $1 " (exit " $2 ")" }' "$TSV")
if [ -n "$failed" ]; then
  echo "coverage_status.sh: these tests failed:" >&2
  printf '%s\n' "$failed" >&2
  exit 1
fi
exit 0
