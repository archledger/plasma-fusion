# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Provisioning, Fedora: updates (Plasma 6.7) and the KDE desktop.
set -euo pipefail
dnf -y -q upgrade --refresh
dnf -y -q install @kde-desktop-environment konsole dolphin
rpm -q --qf '%{NAME} %{VERSION}\n' plasma-workspace kwin
