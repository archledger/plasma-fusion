# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Provisioning, KDE neon: neon's archive on the Ubuntu base, then neon-desktop.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
curl -fsSL https://archive.neon.kde.org/public.key -o /etc/apt/trusted.gpg.d/neon.asc
gpg --show-keys /etc/apt/trusted.gpg.d/neon.asc 2>/dev/null | sed -n '2p;3p' || true
echo "deb http://archive.neon.kde.org/user noble main" >/etc/apt/sources.list.d/neon.list
apt-get update -qq
apt-get -y -qq full-upgrade >/tmp/apt.log 2>&1 || { tail -20 /tmp/apt.log; exit 1; }
apt-get -y -qq install neon-desktop >>/tmp/apt.log 2>&1 || { tail -20 /tmp/apt.log; exit 1; }
dpkg-query -W plasma-workspace kwin-wayland
grep -E '^(ID|PRETTY_NAME)=' /etc/os-release
