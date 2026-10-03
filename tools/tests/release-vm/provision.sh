#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# provision.sh NAME IMAGE DISTRO: create the VM, boot it, install Plasma, set up the tty1 session,
# power off (base.qcow2 then holds the provisioned system). Log: ~/pf-vm/vms/NAME/provision.log
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
H=${PF_VM_HOME:-$HOME/pf-vm}
name=$1 image=$2 distro=$3
d=$H/vms/$name
mkdir -p "$d"
{
  echo "== $(date -u +%FT%TZ) provision $name from $image ($distro)"
  "$HERE/vm.sh" create "$name" "$image" && "$HERE/vm.sh" start "$name" base && "$HERE/vm.sh" wait "$name" &&
  "$HERE/vm.sh" ssh "$name" 'cloud-init status --wait >/dev/null 2>&1; true' &&
  cat "$HERE/prov-$distro.sh" "$HERE/prov-common.sh" | "$HERE/vm.sh" ssh "$name" sudo bash -s
  rc=$?
  "$HERE/vm.sh" stop "$name"
  echo "== $(date -u +%FT%TZ) provision $name rc=$rc"
} >"$d/provision.log" 2>&1
