#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# In a fedora container, as root: build all the RPMs of this tree (packaging/build-rpm.sh
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
rpm -q plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation plasma-fusion-quicklook \
  plasma-fusion-copytext
test "$(plasma-fusion version)" = "$(tr -d '[:space:]' <"$ROOT/VERSION")"
bash "$ROOT/tools/tests/packages/parts.sh"
bash "$ROOT/tools/tests/packages/qml-imports.sh"
bash "$ROOT/tools/tests/packages/qml-parse.sh"
echo "fedora: ok"
