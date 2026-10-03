# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Provisioning, Debian testing: the KDE Plasma desktop and the generic kernel.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get -y -qq full-upgrade >/dev/null
apt-get -y -qq install kde-plasma-desktop konsole dolphin >/tmp/apt.log 2>&1 || { tail -20 /tmp/apt.log; exit 1; }
dpkg-query -W plasma-workspace kwin-wayland
# Debian's cloud kernel has no virtio-gpu DRM driver (KWin needs one): the generic kernel instead.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq linux-image-amd64 >/dev/null
apt-get purge -y -qq 'linux-image-*-cloud-amd64' linux-image-cloud-amd64 >/dev/null 2>&1 || true
update-grub >/dev/null 2>&1 || true
ls /boot/vmlinuz-*
