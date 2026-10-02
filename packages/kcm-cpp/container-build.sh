#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Runs inside localhost/plasma-fusion-build:f44-6.7.5 with the work directory mounted at /work
# (/work/src filled by build-remote.sh): configure, build and install with DESTDIR=/work/root.
# Development builds only; the packages come from packaging/build-rpm.sh --compiled.
set -euo pipefail
cd /work
{
  cmake -S src -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr \
    -DKDE_INSTALL_USE_QT_SYS_PATHS=ON -DBUILD_TESTING=OFF &&
    ninja -C build -j"${PF_JOBS:-6}" &&
    DESTDIR=/work/root ninja -C build install
} >/work/build.log 2>&1 || { tail -60 /work/build.log; exit 1; }
tail -3 /work/build.log
