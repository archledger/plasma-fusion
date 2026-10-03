#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The release VM tests, one VM at a time, on the candidate of build-all.sh: the test channels
# (channels.sh), then vmtest.sh per system. Results in $PF_VM_HOME/results/NAME/, a summary in
# $PF_VM_HOME/run-all.log. VMs: provision.sh (once per system); NixOS: nixos/build-image.sh.
#
#   tools/tests/release-vm/run-all.sh [NAME:LANE ...]
#   (default fedora44:copr arch:aur ubuntu2610:ppa debian-testing:deb neon:deb nixos:nix)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
H=${PF_VM_HOME:-$HOME/pf-vm}
[ $# -gt 0 ] || set -- fedora44:copr arch:aur ubuntu2610:ppa debian-testing:deb neon:deb nixos:nix
bash "$HERE/channels.sh" </dev/null >"$H/channels.log" 2>&1 || { echo "channels.sh failed (see $H/channels.log)" >&2; exit 1; }
for vm in "$@"; do
  name=${vm%%:*} lane=${vm#*:}
  [ -d "$H/vms/$name" ] || { echo "$(date -u +%T) $name: no VM (provision.sh)" | tee -a "$H/run-all.log"; continue; }
  bash "$HERE/vmtest.sh" "$name" "$lane"
  echo "$(date -u +%T) $name: $(grep -E 'FAIL' "$H/results/$name/steps.log" | head -n 1 || true)$(tail -n 1 "$H/results/$name/steps.log")" | tee -a "$H/run-all.log"
done
