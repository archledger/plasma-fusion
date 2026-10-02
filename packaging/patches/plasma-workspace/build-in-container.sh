#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Inside the container of build.sh: Fedora's source RPM VERSION-RELEASE, the patches of /patches
# added after Fedora's own, Release suffixed .pf1 with a changelog entry, built into /out.
set -euo pipefail
vr=$1
top=/root/rpmbuild
spec=$top/SPECS/plasma-workspace.spec
dnf install -y -q rpm-build 'dnf-command(download)' 'dnf-command(builddep)' >/dev/null
cd /root
dnf download -q --source "plasma-workspace-$vr"
rpm -i --define "_topdir $top" "plasma-workspace-$vr.src.rpm" 2>/dev/null
cp /patches/*.patch "$top/SOURCES/"
grep -q '^Release:.*%{?dist}$' "$spec" || { echo "unexpected Release line: $(grep '^Release:' "$spec")" >&2; exit 1; }
grep -q '^%autosetup -p1' "$spec" || { echo "the spec no longer uses %autosetup -p1" >&2; exit 1; }
sed -i -E 's/^(Release:.*%\{\?dist\})$/\1.pf1/' "$spec"
# Fedora numbers its patches below 9000; ours follow them.
patches=$(n=9001; for p in /patches/*.patch; do printf 'Patch%d: %s\\n' "$n" "$(basename "$p")"; n=$((n + 1)); done)
last=$(grep -n '^Patch[0-9]*:' "$spec" | tail -1 | cut -d: -f1)
sed -i "${last}a # Plasma Fusion (packaging/patches/plasma-workspace)\\n${patches%\\n}" "$spec"
release=$(rpmspec -q --srpm --qf '%{VERSION}-%{RELEASE}' "$spec")
entry="* $(LC_ALL=C date -u '+%a %b %d %Y') Wisbendji Fimerlus <archledger236@gmail.com> - ${release%.fc*}.pf1\\n- Plasma Fusion: guard the global menu search results against deleted actions\\n"
sed -i "/^%changelog/a ${entry}" "$spec"
grep -n -E '^(Release|Patch9[0-9]{3}):|^# Plasma Fusion' "$spec"
sed -n '/^%changelog/,+3p' "$spec"
dnf builddep -y -q "$spec" >/dev/null
rpmbuild -ba --define "_topdir $top" "$spec" > /out/rpmbuild.log 2>&1 || { tail -40 /out/rpmbuild.log; exit 1; }
cp "$top"/RPMS/*/*.rpm "$top"/SRPMS/*.rpm /out/
