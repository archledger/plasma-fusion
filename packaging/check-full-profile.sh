#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The full-profile spec branch's automated checks (docs/full-profile.md): the stock default
# never emits plasma-fusion-full; a full build with a matching exact pin emits it once; a full
# build with a wrong-series pin fails; a full build without a pin fails. Keeps the %{with full}
# gate exercised in CI without building the fork's RPMs. The pin's pf suffix carries any number
# of digits (check-version.sh accepts pf10), so the two-digit gates mirror the one-digit ones.
#
# A release sets the pin in the spec itself (%global kwin_full_pin), and a %global in the spec
# wins over a --define on the command line. The gates therefore run on a copy of the spec
# without that line, and the spec as it is has checks of its own at the end.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
real="$ROOT/packaging/fedora/plasma-fusion.spec"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
spec="$work/plasma-fusion.spec"
sed '/^%global kwin_full_pin /d' "$real" >"$spec"
own=$(sed -n 's/^%global kwin_full_pin *//p' "$real" | tr -d '[:space:]')
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
query "full + matching fc44 pin with a two-digit pf suffix emits it once" 1 --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf10'
query "full + fc45 pin is refused" 0 --with full --define 'kwin_full_pin 6.8.2-3.fc45.pf2'
query "full + fc45 pin with a two-digit pf suffix is refused" 0 --with full --define 'kwin_full_pin 6.8.2-3.fc45.pf10'
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
# The profile's record (plasma-fusion status reads it): written by a full build only, with the
# pin and the fork tag it is built from, and shipped by the metapackage only.
record() { # DESC EXPECTED ARGS...: the record's two lines as %install writes them
  local desc=$1 expected=$2 body got
  shift 2
  body=$(rpmspec --define 'fedora 44' "$@" -P "$spec" 2>/dev/null |
    sed -n "/^pin='/,/full-profile\$/p")
  if [ -z "$body" ]; then
    got=
  else
    got=$(buildroot=$(mktemp -d) && eval "$(printf '%s\n' "$body" | sed "s#>.*/plasma-fusion/full-profile#>$buildroot/record#")" &&
      tr '\n' ' ' <"$buildroot/record" && rm -rf "$buildroot")
  fi
  if [ "$got" = "$expected" ]; then
    echo "ok   $desc"
  else
    echo "FAIL $desc: expected '$expected', got '$got'"
    rc=1
  fi
}
record "a full build writes the pin and its fork tag" "kwin=6.8.2-3.fc44.pf2 tag=v6.8.2-pf2 " --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf2'
record "a two-digit pf suffix gives its tag" "kwin=6.8.2-3.fc44.pf10 tag=v6.8.2-pf10 " --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf10'
record "a stock build writes no record" ""
files=$(rpmspec --define 'fedora 44' --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf2' -P "$spec" 2>/dev/null |
  awk '/^%files full$/{p=1; next} /^%files/{p=0} p' | grep -c '/plasma-fusion/full-profile$' || true)
if [ "$files" = 1 ]; then
  echo "ok   the metapackage ships the record"
else
  echo "FAIL the metapackage ships the record: found x$files in its file list"
  rc=1
fi
# The spec as it is: with a pin of its own, the stock build still never emits the metapackage,
# the full build emits it once with exact requires on that pin, and the record names it.
if [ -n "$own" ]; then
  spec=$real
  query "the spec's own pin ($own): a stock build never emits the metapackage" 0
  query "the spec's own pin: a full build emits it once" 1 --with full
  requires=$(rpmspec --define 'fedora 44' --with full -q --requires "$real" 2>/dev/null |
    grep -cxE "kwin(-common|-libs)? = ${own//./\\.}" || true)
  if [ "$requires" = 3 ]; then
    echo "ok   the metapackage requires kwin, kwin-common and kwin-libs at exactly $own"
  else
    echo "FAIL the metapackage's exact requires on $own: found x$requires of 3"
    rc=1
  fi
  record "the spec's own pin: the record names it and its fork tag" "kwin=$own tag=v${own%%-*}-${own##*.} " --with full
else
  echo "ok   the spec sets no pin of its own (plasma-fusion-full is not built)"
fi
exit "$rc"
