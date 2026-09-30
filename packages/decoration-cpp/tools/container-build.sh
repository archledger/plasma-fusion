#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Runs INSIDE localhost/plasma-fusion-build:f44-6.7.5 with the work directory mounted at /work:
#   /work/src      this package (packages/decoration-cpp)
#   /work/build    CMake build directory (plugin + tests/pfdeco-preview)
#   /work/rpmbuild rpmbuild top directory; the RPM lands in /work/rpmbuild/RPMS/x86_64/
# Started by tools/build-rpm.sh; JOBS (default 6) limits the parallelism, CLEAN=1 starts from an
# empty build directory (the compiler warnings of every file land in build-ninja.log).
set -euo pipefail
JOBS=${JOBS:-6}
cd /work
[ "${CLEAN:-0}" = 1 ] && rm -rf build
cmake -S src -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DKDE_INSTALL_USE_QT_SYS_PATHS=ON -DBUILD_TESTING=ON >build-cmake.log 2>&1 \
  || { cat build-cmake.log; exit 1; }
nice -n 10 ninja -C build -j"$JOBS" 2>&1 | tee build-ninja.log
[ "${PIPESTATUS[0]}" = 0 ] || exit 1

VERSION=$(sed -n 's/^Version:[[:space:]]*//p' src/plasma-fusion-decoration.spec)
rm -rf rpmbuild
mkdir -p rpmbuild/SOURCES
tar -czf "rpmbuild/SOURCES/plasma-fusion-decoration-$VERSION.tar.gz" \
  --exclude='src/build' --exclude='src/tools/__pycache__' \
  --transform "s,^src,plasma-fusion-decoration-$VERSION," src
nice -n 10 rpmbuild --define "_topdir /work/rpmbuild" --define "_smp_mflags -j$JOBS" \
  -bb src/plasma-fusion-decoration.spec >rpmbuild.log 2>&1 || { tail -60 rpmbuild.log; exit 1; }
ls -l rpmbuild/RPMS/x86_64/
rpm -qlp rpmbuild/RPMS/x86_64/plasma-fusion-decoration-"$VERSION"-*.x86_64.rpm
