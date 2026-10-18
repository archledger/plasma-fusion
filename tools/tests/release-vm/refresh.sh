#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# refresh.sh NAME...: each VM's base brought to its system's current packages before a release
# test, the way that system updates itself, then the Plasma versions it has. A failed update fails
# the refresh (exit 1, the VM's update log on stdout). Log: ~/pf-vm/vms/NAME/refresh.log
#   Fedora: dnf upgrade, then the RPM database checked (rpmdb --verifydb) and rebuilt if it fails
#     (2026-10-18: a base refreshed this way was left with a malformed database, and the next
#     install failed);
#   Arch: pacman -Syu;
#   KDE neon: apt full-upgrade with --allow-downgrades, as neon's own updater does: neon's pins move
#     some Ubuntu packages to neon's versions, and plain apt-get -y refuses that, leaving the system
#     at its old Plasma (2026-10-18: still at 6.7.5 while neon had 6.8.0);
#   Ubuntu, Debian: apt full-upgrade;
#   NixOS: nothing (the image is built from the candidate, nixos/build-image.sh).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
H=${PF_VM_HOME:-$HOME/pf-vm}
[ $# -gt 0 ] || { echo "usage: refresh.sh NAME..." >&2; exit 2; }
vm() { bash "$HERE/vm.sh" "$@"; }
# shellcheck disable=SC2016 # expanded in the VM
UPDATE='set -uo pipefail
. /etc/os-release
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l
case $ID in
  fedora)
    dnf -y upgrade --refresh >/tmp/refresh.log 2>&1 || { tail -20 /tmp/refresh.log; exit 1; }
    if ! rpm -qa >/dev/null 2>&1 || ! rpmdb --verifydb >/dev/null 2>&1; then
      echo "rpm database: rebuilt"; rpm --rebuilddb && rpmdb --verifydb || { echo "rpm database: broken"; exit 1; }
    fi
    rpm -q plasma-workspace kwin kscreenlocker qt6-qtbase ;;
  arch)
    pacman -Syu --noconfirm >/tmp/refresh.log 2>&1 || { tail -20 /tmp/refresh.log; exit 1; }
    pacman -Q plasma-workspace kwin kscreenlocker qt6-base ;;
  neon)
    { apt-get update -q && apt-get -y -q --allow-downgrades full-upgrade; } >/tmp/refresh.log 2>&1 || { tail -20 /tmp/refresh.log; exit 1; }
    dpkg-query -W plasma-workspace kwin-wayland libplasma6 ;;
  ubuntu | debian)
    { apt-get update -q && apt-get -y -q full-upgrade; } >/tmp/refresh.log 2>&1 || { tail -20 /tmp/refresh.log; exit 1; }
    dpkg-query -W plasma-workspace kwin-wayland ;;
  nixos) echo "NixOS: nothing to refresh (the image is built from the candidate)" ;;
  *) echo "refresh: no rule for $ID"; exit 1 ;;
esac'
failed=0
for name in "$@"; do
  d=$H/vms/$name
  [ -d "$d" ] || { echo "$name: no VM" >&2; failed=1; continue; }
  {
    echo "== $(date -u +%FT%TZ) refresh $name"
    rc=0
    vm start "$name" base && vm wait "$name" && printf '%s\n' "$UPDATE" | vm ssh "$name" sudo bash -s || rc=$?
    vm stop "$name"
    echo "== $(date -u +%FT%TZ) refresh $name rc=$rc"
  } >"$d/refresh.log" 2>&1
  rc=$(sed -n 's/^== .* rc=\([0-9]*\)$/\1/p' "$d/refresh.log" | tail -n 1)
  echo "$name: rc=${rc:-?} $(grep -vE '^(== |started |stopped |.*: ssh up$)' "$d/refresh.log" | tr '\n' ' ' | cut -c1-300)"
  [ "${rc:-1}" = 0 ] || failed=1
done
exit "$failed"
