#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# On a machine with Nix: the release-test NixOS image (nixos-unstable with Plasma 6, the Plasma Fusion
# module from SRC, user pf with the test key of vm.sh, tty1 session) as a compressed qcow2.
#
#   tools/tests/release-vm/nixos/build-image.sh SRC PUBKEY_FILE OUTPUT.qcow2
#   (then: copy OUTPUT to $PF_VM_HOME/images/nixos.qcow2 on the test machine; vm.sh create nixos nixos.qcow2)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(realpath "$1") KEY=$(cat "$2") OUT=$(realpath -m "$3")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed "s|@SRC@|$SRC|" "$HERE/flake.nix" >"$work/flake.nix"
sed "s|@PUBKEY@|$KEY|" "$HERE/configuration.nix" >"$work/configuration.nix"
cd "$work"
nix flake lock
nice -n 10 nixos-rebuild build-image --image-variant qemu --flake "path:$work#pftest"
nice -n 10 qemu-img convert -c -O qcow2 "$(ls "$(readlink -f result)"/*.qcow2)" "$OUT"
sha256sum "$OUT"
