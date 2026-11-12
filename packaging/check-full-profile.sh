#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The full-profile spec branch's automated checks (docs/full-profile.md): the stock default
# never emits plasma-fusion-full; a full build with a matching exact pin emits it once; a full
# build with a wrong-series pin fails; a full build without a pin fails. Keeps the %{with full}
# gate exercised in CI without building the fork's RPMs.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
spec="$ROOT/packaging/fedora/plasma-fusion.spec"
rc=0
query() { # DESC EXPECTED_COUNT ARGS...
  local desc=$1 expected=$2
  shift 2
  local count
  count=$(rpmspec --define 'fedora 44' "$@" -q --qf '%{NAME}\n' "$spec" 2>/dev/null | grep -c '^plasma-fusion-full$' || true)
  if [ "$count" = "$expected" ]; then
    echo "ok   $desc (plasma-fusion-full x$count)"
  else
    echo "FAIL $desc: expected x$expected, got x$count"
    rc=1
  fi
}
query "stock default never emits the metapackage" 0
query "a pin alone (no --with full) never emits it" 0 --define 'kwin_full_pin 6.8.2-3.fc44.pf2'
query "full + matching fc44 pin emits it once" 1 --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf2'
query "full + fc45 pin is refused" 0 --with full --define 'kwin_full_pin 6.8.2-3.fc45.pf2'
# the refused cases must be hard errors, not silent skips
if rpmspec --define 'fedora 44' --with full --define 'kwin_full_pin 6.8.2-3.fc45.pf2' -q "$spec" >/dev/null 2>&1; then
  echo "FAIL full + fc45 pin: expected a hard error"
  rc=1
else
  echo "ok   full + fc45 pin fails the build"
fi
if rpmspec --define 'fedora 44' --with full -q "$spec" >/dev/null 2>&1; then
  echo "FAIL full without a pin: expected a hard error"
  rc=1
else
  echo "ok   full without a pin fails the build"
fi
exit "$rc"
