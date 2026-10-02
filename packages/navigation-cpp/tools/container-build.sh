#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Runs INSIDE localhost/plasma-fusion-build:f44-6.7.5 with the work directory mounted at /work:
#   /work/src      this package (packages/navigation-cpp)
#   /work/build    CMake build directory
#   /work/stage    DESTDIR install of the build (for private test sessions; nothing is installed)
# Development builds only (the packages: packaging/build-rpm.sh --compiled). Started by
# tools/build-remote.sh; JOBS (default 6) limits the parallelism, CLEAN=1 starts from an empty build
# directory.
set -euo pipefail
JOBS=${JOBS:-6}
cd /work
[ "${CLEAN:-0}" = 1 ] && rm -rf build
cmake -S src -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DKDE_INSTALL_USE_QT_SYS_PATHS=ON >build-cmake.log 2>&1 \
  || { cat build-cmake.log; exit 1; }
nice -n 10 ninja -C build -j"$JOBS" 2>&1 | tee build-ninja.log
[ "${PIPESTATUS[0]}" = 0 ] || exit 1
rm -rf stage
DESTDIR=/work/stage ninja -C build install >build-install.log 2>&1 || { tail -30 build-install.log; exit 1; }
find stage -type f | sort
