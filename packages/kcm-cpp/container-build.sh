#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Runs inside localhost/plasma-fusion-build:f44-6.7.5 with the work directory mounted at /work
# (SOURCES/ and SPECS/ filled by build-rpm.sh). Results: /work/RPMS, /work/SRPMS, /work/build.log.
set -euo pipefail
cd /work
rpmbuild --define "_topdir /work" --define "_smp_mflags -j${PF_JOBS:-6}" \
  -ba SPECS/plasma-fusion-settings.spec >/work/build.log 2>&1 || { tail -60 /work/build.log; exit 1; }
tail -5 /work/build.log
