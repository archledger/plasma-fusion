#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# In a fedora container, as root: build all four RPMs of this tree (packaging/build-rpm.sh
# --compiled: %check, rpmlint), install them and check the installed files.
#
#   tools/tests/packages/fedora.sh TOPDIR
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TOP=$(mkdir -p "$1" && realpath "$1")
dnf install -y -q git rpm-build rpmlint dnf-plugins-core >/dev/null
git config --global --add safe.directory '*'
dnf builddep -y -q "$ROOT/packaging/fedora/plasma-fusion.spec" >/dev/null
"$ROOT/packaging/build-rpm.sh" --topdir "$TOP" --compiled
echo "== install"
rpms=()
for f in "$TOP"/RPMS/*/plasma-fusion*.rpm; do [[ $f == *-debug* ]] || rpms+=("$f"); done
dnf install -y -q "${rpms[@]}" >/dev/null
rpm -q plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation
test "$(plasma-fusion version)" = "$(tr -d '[:space:]' <"$ROOT/VERSION")"
for p in decoration settings navigation; do test -s "/usr/share/plasma-fusion/built-against/$p"; done
bash "$ROOT/tools/tests/packages/qml-imports.sh"
echo "fedora: ok"
