#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Internal entry point: called by build.sh, never against the host's RPM database.
set -euo pipefail
[[ $# == 1 && $1 =~ ^6\.7\.5-[0-9]+\.fc44$ ]] || exit 64
vr=$1
top=/root/rpmbuild
spec=$top/SPECS/kwin.spec
dnf install -y rpm-build dnf5-plugins python3 > /out/dependencies.log 2>&1
python3 -B -m unittest discover -s /patches -v
mkdir -p /root/source
cd /root/source
dnf download --srpm "kwin-$vr" > /out/download.log 2>&1
source="kwin-$vr.src.rpm"
[[ $(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}' "$source") == "kwin-$vr" ]]
cp "$source" /out/fedora-"$source"
rpm -i --define "_topdir $top" "$source"
cp /patches/*.patch "$top/SOURCES/"
python3 /patches/prepare_spec.py "$spec" "$vr"
[[ $(rpmspec -q --srpm --qf '%{VERSION}-%{RELEASE}' "$spec") == "$vr.pf1" ]]
cp "$spec" /out/kwin.spec
dnf builddep -y "$spec" >> /out/dependencies.log 2>&1
# Do not disable Fedora's build checks. The separate native test run covers the new tests;
# Fedora's spec decides which checks rpmbuild itself runs.
if ! rpmbuild -ba --define "_topdir $top" --define '_smp_mflags -j4' "$spec" \
    > /out/rpmbuild.log 2>&1; then
    tail -60 /out/rpmbuild.log >&2
    exit 1
fi
cp "$top"/RPMS/*/*.rpm "$top"/SRPMS/*.rpm /out/
