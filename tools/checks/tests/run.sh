#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Self-test of the lints in tools/checks/: each fixture marks the lines a lint must report with
# "expect: RULE"; the lint must report exactly those (file, line, rule) and nothing else.
#   tools/checks/tests/run.sh
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHECKS=$(cd "$HERE/.." && pwd)
fail=0
compare() {  # NAME DIR COMMAND...
  local name=$1 dir=$2; shift 2
  local want got
  want=$(grep -rnoE --include='*.qml' 'expect: [a-z-]+' "$dir" | sed -E 's#^.*/([^/]+):([0-9]+):expect: #\1:\2 #' | sort)
  got=$("$@" "$dir" 2>/dev/null | sed -E 's#^.*/([^/]+):([0-9]+): ([a-z-]+) .*#\1:\2 \3#' | sort || true)
  if [ "$want" = "$got" ]; then
    echo "ok   $name ($(printf '%s\n' "$want" | grep -c .) findings as expected)"
  else
    echo "FAIL $name"; diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed 's/^/     /' || true
    fail=1
  fi
}
compare motion-lint "$HERE/motion" bash "$CHECKS/motion-lint.sh" --warn
compare a11y-lint "$HERE/a11y" python3 "$CHECKS/a11y-lint.py" --warn
exit "$fail"
