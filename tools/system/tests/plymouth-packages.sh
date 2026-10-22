#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Package cleanup without a boot image: the real package database, a stand-in builder and
# selector. An inventory error must preserve the record; individually safe removals must not be
# combined into an unsafe transaction. Run in a fresh disposable container as root.
# Usage: tools/system/tests/plymouth-packages.sh [UNINSTALL_SCRIPT]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
UNINSTALL=${1:-$HERE/../plymouth-uninstall.sh}
STATE=/var/lib/plasma-fusion/plymouth
[ "$(id -u)" = 0 ] && { [ -e /run/.containerenv ] || [ -e /.dockerenv ]; } ||
  { echo "plymouth-packages: run as root in a disposable container" >&2; exit 1; }
[ ! -e "$STATE" ] || { echo "plymouth-packages: existing splash state; refusing" >&2; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin"
for tool in dracut lsinitrd; do printf '#!/bin/sh\nexit 0\n' >"$WORK/bin/$tool"; done
printf '#!/bin/sh\necho stock\n' >"$WORK/bin/plymouth-set-default-theme"
chmod +x "$WORK/bin/"*
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $*"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $*"; printf '%s\n' "$OUT"; }

if command -v dnf >/dev/null; then query=rpm
elif command -v pacman >/dev/null; then query=pacman
else query=dpkg-query
fi
native=$(command -v "$query")
printf '#!/bin/sh\necho "fixture: package database unavailable" >&2\nexit 42\n' >"$WORK/bin/$query"
chmod +x "$WORK/bin/$query"
install -d -m 0700 "$STATE"
printf 'pf-test-absent\n' >"$STATE/installed-packages"
OUT=$(PATH="$WORK/bin:$PATH" bash "$UNINSTALL" --remove-plugin 2>&1) && RC=0 || RC=$?
[ "$RC" != 0 ] && grep -qx pf-test-absent "$STATE/installed-packages" &&
  ok "package-query failure preserves the record and fails" || bad "package-query failure discarded the record or succeeded"
rm "$WORK/bin/$query"
OUT=$(PATH="$WORK/bin:$PATH" bash "$UNINSTALL" --remove-plugin 2>&1) && RC=0 || RC=$?
[ "$RC" = 0 ] && [ ! -e "$STATE/installed-packages" ] &&
  ok "retry with a readable database clears an already-absent package" || bad "readable-database retry"

if [ "$query" = dpkg-query ]; then
  # A and B can each be removed on their own, but not together: D needs A or B. C makes the
  # original complete set unsafe too, forcing the fallback to try individual packages.
  for p in a b c d; do
    mkdir -p "$WORK/$p/DEBIAN"
    {
      printf 'Package: pf-test-%s\nVersion: 1.0\nArchitecture: all\nMaintainer: Test <test@example.invalid>\nDescription: disposable package-removal fixture\n' "$p"
      [ "$p" != d ] || printf 'Depends: pf-test-a | pf-test-b, pf-test-c\n'
    } >"$WORK/$p/DEBIAN/control"
    dpkg-deb --build --root-owner-group "$WORK/$p" "$WORK/$p.deb" >/dev/null
  done
  dpkg -i "$WORK/"*.deb >/dev/null
  install -d -m 0700 "$STATE"
  printf 'pf-test-a\npf-test-b\npf-test-c\n' >"$STATE/installed-packages"
  OUT=$(PATH="$WORK/bin:$PATH" bash "$UNINSTALL" --remove-plugin 2>&1) && RC=0 || RC=$?
  all=1
  for p in a b c d; do
    [ "$("$native" -W -f='${Status}' "pf-test-$p" 2>/dev/null)" = 'install ok installed' ] || all=0
  done
  [ "$RC" = 0 ] && [ "$all" = 1 ] && [ "$(wc -l <"$STATE/installed-packages")" = 3 ] &&
    ok "individually safe alternatives are not removed together" || bad "unsafe combined removal"
  # Once the consumer goes, the three recorded packages can all be removed on retry.
  dpkg -r pf-test-d >/dev/null
  OUT=$(PATH="$WORK/bin:$PATH" bash "$UNINSTALL" --remove-plugin 2>&1) && RC=0 || RC=$?
  removed=1
  for p in a b c; do
    [ "$("$native" -W -f='${Status}' "pf-test-$p" 2>/dev/null)" != 'install ok installed' ] || removed=0
  done
  [ "$RC" = 0 ] && [ "$removed" = 1 ] && [ ! -e "$STATE" ] &&
    ok "retry removes the complete unused set" || bad "unused-set retry"
fi
echo "plymouth-packages: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
