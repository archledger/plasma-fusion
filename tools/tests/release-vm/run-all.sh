#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The release VM tests, one VM at a time, on the candidate of build-all.sh: the test channels
# (channels.sh), then vmtest.sh per system, or sddmtest.sh (the SDDM login screen on real boots)
# for NAME:LANE:sddm, splashtest.sh (the boot splash on real boots) for NAME:LANE:splash. Results in
# $PF_VM_HOME/results/NAME/ (NAME-sddm/, NAME-splash/), a summary in $PF_VM_HOME/run-all.log. VMs:
# provision.sh (once per system); NixOS: nixos/build-image.sh.
#
#   tools/tests/release-vm/run-all.sh [NAME:LANE[:sddm|:splash] ...]
#   (default fedora44:copr arch:aur ubuntu2610:ppa debian-testing:deb neon:deb nixos:nix)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
H=${PF_VM_HOME:-$HOME/pf-vm}
[ $# -gt 0 ] || set -- fedora44:copr arch:aur ubuntu2610:ppa debian-testing:deb neon:deb nixos:nix
# PF_PUBLIC=1 (vmtest.sh): the public channels, nothing to serve.
[ "${PF_PUBLIC:-}" = 1 ] ||
  bash "$HERE/channels.sh" </dev/null >"$H/channels.log" 2>&1 || { echo "channels.sh failed (see $H/channels.log)" >&2; exit 1; }
failed=0
for vm in "$@"; do
  name=${vm%%:*} lane=${vm#*:} test=vmtest.sh
  result=$name
  case $lane in
    *:sddm) lane=${lane%:sddm} test=sddmtest.sh result=$name-sddm ;;
    *:splash) lane=${lane%:splash} test=splashtest.sh result=$name-splash ;;
  esac
  [ -d "$H/vms/$name" ] || { echo "$(date -u +%T) $result: no VM (provision.sh)" | tee -a "$H/run-all.log"; [ "$failed" != 0 ] || failed=1; continue; }
  rc=0
  bash "$HERE/$test" "$name" "$lane" || rc=$?
  [ "$rc" = 0 ] || { [ "$failed" != 0 ] || failed=$rc; }
  if [ ! -f "$H/results/$result/steps.log" ]; then
    echo "$(date -u +%T) $result: missing result log" | tee -a "$H/run-all.log"
    [ "$failed" != 0 ] || failed=1
    continue
  fi
  if grep -q 'FAIL' "$H/results/$result/steps.log"; then
    [ "$failed" != 0 ] || failed=1
  fi
  echo "$(date -u +%T) $result: $(grep -E 'FAIL' "$H/results/$result/steps.log" | head -n 1 || true)$(tail -n 1 "$H/results/$result/steps.log")" | tee -a "$H/run-all.log"
done
exit "$failed"
