#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Rebuild Fedora's plasma-workspace with the patches in this directory (README.md), in a Fedora
# container with podman. The RPMs and the source RPM land in OUT_DIR, with SHA256SUMS, rpmbuild.log
# and download.log (the fetch of Fedora's source package by ../fetch-source.sh).
#
#   build.sh OUT_DIR [VERSION-RELEASE [FEDORA]]
#
# VERSION-RELEASE is Fedora's build to start from (default: the one installed here, for example
# 6.7.5-1.fc44); FEDORA the release whose container builds it (default: this machine's).
# The rebuilt packages are VERSION-RELEASE.pf1: newer than Fedora's same build, older than its next.
# Exit status: 0 built; 3 Fedora's source package of that build could not be fetched (no mirror
# read carries it: ../fetch-source.sh says why); 64 usage; another failure its own status.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
[ $# -ge 1 ] || { sed -n '5,/^set -euo pipefail$/p' "$0" | sed '$d'; exit 64; }
mkdir -p "$1"
out=$(cd "$1" && pwd)
vr=${2:-$(rpm -q --qf '%{VERSION}-%{RELEASE}' plasma-workspace)}
fedora=${3:-$(rpm -E %fedora)}
podman run --rm -v "${here%/*}/fetch-source.sh":/fetch-source.sh:ro,z \
    -v "$here":/patches:ro,z -v "$out":/out:z "registry.fedoraproject.org/fedora:$fedora" \
    bash /patches/build-in-container.sh "$vr"
(cd "$out" && sha256sum -- *.rpm > SHA256SUMS)
ls "$out"
