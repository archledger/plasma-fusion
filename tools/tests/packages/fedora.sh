#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# In a fedora container, as root: build all the RPMs of this tree (packaging/build-rpm.sh
# --compiled: %check, rpmlint), install them and check the installed files.
#
#   tools/tests/packages/fedora.sh TOPDIR | --spec-only
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
spec=$ROOT/packaging/fedora/plasma-fusion.spec
if [[ ${1:-} == --spec-only ]]; then
  names=$(rpmspec -q --rpms --qf '%{NAME}\n' "$spec")
  if [[ $(grep -Fxc plasma-fusion-notifications <<<"$names") != 1 ]]; then
    echo 'FAIL: expected one optional plasma-fusion-notifications RPM in the compiled spec' >&2
    exit 1
  fi
  shared_names=$(rpmspec --without compiled -q --rpms --qf '%{NAME}\n' "$spec")
  if grep -Fxq plasma-fusion-notifications <<<"$shared_names"; then
    echo 'FAIL: the shared-only build gained a compiled notification package' >&2
    exit 1
  fi
  exit 0
fi
TOP=$(mkdir -p "$1" && realpath "$1")
dnf install -y -q git rpm-build rpmlint dnf-plugins-core >/dev/null
git config --global --add safe.directory '*'
dnf builddep -y -q "$ROOT/packaging/fedora/plasma-fusion.spec" >/dev/null
"$ROOT/packaging/build-rpm.sh" --topdir "$TOP" --compiled
echo "== install"
rpms=()
notifications=()
for f in "$TOP"/RPMS/*/plasma-fusion*.rpm; do
  [[ $f != *-debug* ]] || continue
  if [[ $(rpm -qp --qf '%{NAME}' "$f") == plasma-fusion-notifications ]]; then
    notifications+=("$f")
  else
    rpms+=("$f")
  fi
done
test "${#notifications[@]}" = 1
dnf install -y -q "${rpms[@]}" >/dev/null
rpm -q plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation plasma-fusion-quicklook \
  plasma-fusion-copytext
test "$(plasma-fusion version)" = "$(tr -d '[:space:]' <"$ROOT/VERSION")"
bash "$ROOT/tools/tests/packages/parts.sh"
bash "$ROOT/tools/tests/packages/qml-imports.sh"
bash "$ROOT/tools/tests/packages/qml-parse.sh"
if rpm -q plasma-fusion-notifications >/dev/null; then
  echo 'FAIL: the optional notifications package was pulled in by default' >&2
  exit 1
fi

libdir=$(rpm --eval '%{_libdir}')
libexec=$(rpm --eval '%{_libexecdir}')/plasma-fusion
stock=$libdir/qt6/plugins/plasma/applets/org.kde.plasma.notifications.so
copy=$libdir/libexec/plasma-fusion/qt6/plugins/plasma/applets/org.kde.plasma.notifications.so
record=/usr/share/plasma-fusion/built-against/notifications
test "$(rpm -qf --qf '%{NAME}' "$stock")" = plasma-workspace-libs
before=$(sha256sum "$stock")
payload=$(rpm -qpl "${notifications[0]}")
for path in "$copy" "$record" "$libexec/plasma-fusion-notifications-common.sh"; do
  grep -Fxq "$path" <<<"$payload"
done
for helper in check select notify watch; do
  grep -Fxq "$libexec/plasma-fusion-notifications-$helper" <<<"$payload"
done
if grep -Fxq "$stock" <<<"$payload"; then echo 'FAIL: notification RPM owns the stock path' >&2; exit 1; fi
license_files=$(rpm -qp --licensefiles "${notifications[0]}")
grep -Eq '/GPL-3\.0-only\.txt$' <<<"$license_files"
grep -Eq '/LGPL-2\.1-or-later\.txt$' <<<"$license_files"
deps=$(rpm -qpR "${notifications[0]}")
base_evr=$(rpm -q --qf '%{VERSION}-%{RELEASE}' plasma-fusion)
grep -Eq "^plasma-fusion(\([^)]*\))? = " <<<"$deps"
grep -Fq " = $base_evr" <<<"$(grep -E '^plasma-fusion(\([^)]*\))? = ' <<<"$deps")"
if grep -Eq '^plasma-workspace(\([^)]*\))? = ' <<<"$deps"; then
  echo 'FAIL: notification RPM pins Plasma Workspace' >&2
  exit 1
fi
dnf install -y -q "${notifications[0]}" >/dev/null
test "$(sha256sum "$stock")" = "$before"
test "$(rpm -qf --qf '%{NAME}' "$copy")" = plasma-fusion-notifications
test "$(rpm -qf --qf '%{NAME}' "$stock")" = plasma-workspace-libs
"$libexec/plasma-fusion-notifications-check" "$copy"
status=$(plasma-fusion status)
grep -Fxq "  notifications: installed, built against $(paste -sd ' ' "$record")" <<<"$status"
printf 'notifications RPM: %s\n' "$(rpm -q plasma-fusion-notifications)"
printf '%s\n' "$payload"
echo "fedora: ok"
