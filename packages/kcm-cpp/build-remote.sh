#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build the settings module (development: no package) in the Fedora 44 build container on the test
# device and fetch the installed tree. The packages come from packaging/build-rpm.sh --compiled.
#
#   packages/kcm-cpp/build-remote.sh [OUTDIR]
#
# OUTDIR (default build/kcm-cpp) receives build.log and root/, the module installed with
# DESTDIR (usr/lib64/qt6/plugins/..., usr/share/...) for test sessions (QT_PLUGIN_PATH,
# tests/make-seed.sh). The sources sent are CMakeLists.txt, src/, icons/, LICENSES/ and
# common/FusionMetrics.qml (from packages/common).
# Environment: PF_BUILD_HOST (ssh host, default thinkpad-fedora), PF_BUILD_IMAGE (default
# localhost/plasma-fusion-build:f44-6.7.5, built from tools/container), PF_REMOTE_DIR (scratch
# directory on the host, default /tmp/pfv-kcm-build, removed first), PF_JOBS (default 6).
# The container runs with nice 10, no network, and only the scratch directory mounted.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=$(realpath -m "${1:-$ROOT/build/kcm-cpp}")
HOST=${PF_BUILD_HOST:-thinkpad-fedora}
IMAGE=${PF_BUILD_IMAGE:-localhost/plasma-fusion-build:f44-6.7.5}
REMOTE=${PF_REMOTE_DIR:-/tmp/pfv-kcm-build}
JOBS=${PF_JOBS:-6}
case $REMOTE in /tmp/pfv-*) ;; *) echo "PF_REMOTE_DIR must be below /tmp/pfv-" >&2; exit 2 ;; esac
ssh -o BatchMode=yes "$HOST" "podman image exists $IMAGE" || { echo "image $IMAGE not found on $HOST (podman build -t $IMAGE tools/container)" >&2; exit 1; }
ssh -o BatchMode=yes "$HOST" "rm -rf '$REMOTE' && mkdir -p '$REMOTE/src/common'"
rsync -a "$HERE/CMakeLists.txt" "$HERE/src" "$HERE/icons" "$HERE/LICENSES" "$HERE/container-build.sh" "$HOST:$REMOTE/src/"
rsync -a "$ROOT/packages/common/FusionMetrics.qml" "$HOST:$REMOTE/src/common/"
ssh -o BatchMode=yes "$HOST" "nice -n 10 podman run --rm --network=none -e PF_JOBS=$JOBS -v '$REMOTE:/work:Z' '$IMAGE' bash /work/src/container-build.sh"
rm -rf "$OUT"
mkdir -p "$OUT"
rsync -a "$HOST:$REMOTE/root" "$HOST:$REMOTE/build.log" "$OUT/"
find "$OUT/root" -type f | sed "s|$OUT/root||" | sort
