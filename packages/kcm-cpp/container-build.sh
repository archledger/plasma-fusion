#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Runs inside localhost/plasma-fusion-build:f44-6.7.5 with the work directory mounted at /work
# (SOURCES/ and SPECS/ filled by build-rpm.sh). Results: /work/RPMS, /work/SRPMS, /work/build.log.
# Fedora's rpm takes SOURCE_DATE_EPOCH from the spec's changelog; the packages' build time is that
# time and their build host a fixed name, so two builds of one spec give identical packages.
set -euo pipefail
cd /work
rpmbuild --define "_topdir /work" --define "_smp_mflags -j${PF_JOBS:-6}" \
  --define "use_source_date_epoch_as_buildtime 1" --define "_buildhost reproducible" \
  -ba SPECS/plasma-fusion-settings.spec >/work/build.log 2>&1 || { tail -60 /work/build.log; exit 1; }
tail -5 /work/build.log
