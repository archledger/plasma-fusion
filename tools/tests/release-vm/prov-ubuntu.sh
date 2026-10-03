# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Provisioning, Ubuntu: the KDE Plasma desktop.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get -y -qq full-upgrade >/dev/null
apt-get -y -qq install kde-plasma-desktop konsole dolphin >/tmp/apt.log 2>&1 || { tail -20 /tmp/apt.log; exit 1; }
dpkg-query -W plasma-workspace kwin-wayland
