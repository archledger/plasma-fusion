#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build every part into a HOME tree (default: stage/home), ready to copy to a user's HOME.
#
#   tools/build.sh [PART...]     build all parts, or only the named ones (e.g. "icons plasma-style")
#
# Each part is tools/build.d/NN-<part>.sh. It receives ROOT (repository root) and STAGE (the HOME
# tree) in the environment and writes only below $STAGE in the paths docs/PLAN.md assigns to it.
#
# Before the parts, the QML checks in tools/checks/ run over packages/: motion-lint.sh (literal
# durations, endless loops, animations without a duration; EFFECTS.md 6.2) and a11y-lint.py
# (interactive items without an accessible name; GAPS.md G25). PF_LINTS=fail (default: stop on
# a finding), warn (list the findings, build anyway) or off.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE=${STAGE:-$ROOT/stage/home}
export ROOT STAGE
mkdir -p "$STAGE"
shopt -s nullglob

lints=${PF_LINTS:-fail}
case "$lints" in
  off) ;;
  warn|fail)
    flag=(); [ "$lints" = warn ] && flag=(--warn)
    echo "== checks ($lints)"
    failed=0
    bash "$ROOT/tools/checks/motion-lint.sh" "${flag[@]}" "$ROOT/packages" || failed=1
    python3 "$ROOT/tools/checks/a11y-lint.py" "${flag[@]}" "$ROOT/packages" || failed=1
    python3 "$ROOT/tools/checks/calendar-tile.py" "${flag[@]}" "$ROOT/packages" || failed=1
    [ "$failed" = 0 ] || { echo "build.sh: the checks found problems (PF_LINTS=$lints); nothing was built" >&2; exit 1; }
    ;;
  *) echo "build.sh: PF_LINTS must be warn, fail or off (not '$lints')" >&2; exit 2 ;;
esac
for script in "$ROOT"/tools/build.d/*.sh; do
  part=$(basename "$script" .sh); part=${part#*-}
  if [ $# -gt 0 ]; then
    wanted=0
    for p in "$@"; do [ "$p" = "$part" ] && wanted=1; done
    [ "$wanted" = 1 ] || continue
  fi
  echo "== $part"
  bash "$script"
done
