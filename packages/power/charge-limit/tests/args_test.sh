#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The charge-limit helper's argument check: a rejected END exits 64 before the root check, an
# accepted one reaches the root check and exits 77 when run as an ordinary user. Nothing is written.
# As root (an RPM build in a container) an accepted END would go on to write the battery's charge
# thresholds, so only the rejected values run then.
#   args_test.sh HELPER
set -euo pipefail
helper=${1:?helper}
root=0
[ "$(id -u)" != 0 ] || root=1
fail=0
expect() {  # RC ARG...
  local want=$1 rc=0
  shift
  bash "$helper" "$@" >/dev/null 2>&1 || rc=$?
  if [ "$rc" != "$want" ]; then
    echo "args_test: '$*' exited $rc, expected $want" >&2
    fail=1
  fi
}
for bad in 050 080 060 0100 49 101 1000 5 '' ' 80' '80 ' 8O +80 -80 80.0 1e2; do expect 64 set "$bad"; done
if [ "$root" = 0 ]; then
  for good in 50 55 79 80 95 99 100; do expect 77 set "$good"; done
fi
expect 64 set
[ "$fail" = 0 ] && echo "charge-limit args: ok$([ "$root" = 0 ] || echo ' (as root: the rejected values only)')"
exit "$fail"
