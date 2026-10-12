#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The device tools' --help prints their usage comment and nothing past it: each tool's help is a
# sed range over its own header, and a header reworded at the range's end makes --help print the
# whole script (fusion-restore.sh printed 402 lines in 0.5.0's work). Test tooling only.
#
#   help-unit.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEV=$HERE/..
PASS=0 FAIL=0
for tool in fusion-config.sh fusion-restore.sh; do
  out=$(bash "$DEV/$tool" --help 2>&1) || { FAIL=$((FAIL + 1)); echo "FAIL $tool --help exits non-zero"; continue; }
  # The usage comment ends before the code: no line of shell code may be in the help.
  if printf '%s\n' "$out" | grep -qE '^(set -euo pipefail|[A-Z_]+=|if |for |while )'; then
    FAIL=$((FAIL + 1)); echo "FAIL $tool --help prints code ($(printf '%s\n' "$out" | wc -l) lines)"
  elif [ "$(printf '%s\n' "$out" | wc -l)" -lt 3 ]; then
    FAIL=$((FAIL + 1)); echo "FAIL $tool --help prints almost nothing"
  else
    PASS=$((PASS + 1)); echo "PASS $tool --help prints its usage only ($(printf '%s\n' "$out" | wc -l) lines)"
  fi
done
echo "help-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
