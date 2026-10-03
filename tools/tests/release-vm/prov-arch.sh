# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Provisioning, Arch: Plasma.
set -euo pipefail
pacman -Syu --noconfirm --needed plasma-meta konsole dolphin >/tmp/pacman.log 2>&1 || { tail -20 /tmp/pacman.log; exit 1; }
pacman -Q plasma-workspace kwin
