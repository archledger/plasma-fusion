#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The charge-limit helper's argument check, run as an ordinary user: a rejected END exits 64 before
# the root check, an accepted one reaches the root check and exits 77. Nothing is written.
#   args_test.sh HELPER
set -euo pipefail
helper=${1:?helper}
[ "$(id -u)" != 0 ] || { echo "args_test: run as an ordinary user" >&2; exit 2; }
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
for good in 50 55 79 80 95 99 100; do expect 77 set "$good"; done
expect 64 set
[ "$fail" = 0 ] && echo "charge-limit args: ok"
exit "$fail"
