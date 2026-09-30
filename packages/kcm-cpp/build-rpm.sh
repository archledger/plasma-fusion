#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build the plasma-fusion-settings RPM (x86_64) in the Fedora 44 build container on the test
# device and fetch the results.
#
#   packages/kcm-cpp/build-rpm.sh [OUTDIR]
#
# OUTDIR (default build/kcm-cpp) receives RPMS/, SRPMS/, build.log and root/, the binary RPM
# unpacked (usr/lib64/qt6/plugins/..., usr/share/...) for test sessions (QT_PLUGIN_PATH).
# The tarball holds CMakeLists.txt, src/, icons/, LICENSES/ and common/FusionMetrics.qml (from
# packages/common). Run it from a clean checkout of the commit to package.
# Environment: PF_BUILD_HOST (ssh host, default thinkpad-fedora), PF_BUILD_IMAGE (default
# localhost/plasma-fusion-build:f44-6.7.5, built from tools/container), PF_REMOTE_DIR (scratch
# directory on the host, default /tmp/pfv-kcm-build, removed first), PF_JOBS (default 6).
# The container runs with nice 10, no network, and only the scratch directory mounted.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
# Absolute, because the RPM is unpacked from inside OUTDIR/root.
OUT=$(realpath -m "${1:-$ROOT/build/kcm-cpp}")
HOST=${PF_BUILD_HOST:-thinkpad-fedora}
IMAGE=${PF_BUILD_IMAGE:-localhost/plasma-fusion-build:f44-6.7.5}
REMOTE=${PF_REMOTE_DIR:-/tmp/pfv-kcm-build}
JOBS=${PF_JOBS:-6}
NAME=plasma-fusion-settings
VERSION=$(sed -n 's/^Version: *//p' "$HERE/$NAME.spec")
case $REMOTE in /tmp/pfv-*) ;; *) echo "PF_REMOTE_DIR must be below /tmp/pfv-" >&2; exit 2 ;; esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/$NAME-$VERSION"
cp -a "$HERE/CMakeLists.txt" "$HERE/src" "$HERE/icons" "$HERE/LICENSES" "$tmp/$NAME-$VERSION/"
# The shared Plasma Fusion QML the page uses (src/CMakeLists.txt looks for it in common/).
mkdir -p "$tmp/$NAME-$VERSION/common"
cp -a "$ROOT/packages/common/FusionMetrics.qml" "$tmp/$NAME-$VERSION/common/"
# Reproducible tarball: fixed order, owner and times.
tar -C "$tmp" --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -czf "$tmp/$NAME-$VERSION.tar.gz" "$NAME-$VERSION"

ssh -o BatchMode=yes "$HOST" "podman image exists $IMAGE" || { echo "image $IMAGE not found on $HOST (podman build -t $IMAGE tools/container)" >&2; exit 1; }
ssh -o BatchMode=yes "$HOST" "rm -rf '$REMOTE' && mkdir -p '$REMOTE/SOURCES' '$REMOTE/SPECS'"
scp -q "$tmp/$NAME-$VERSION.tar.gz" "$HOST:$REMOTE/SOURCES/"
scp -q "$HERE/$NAME.spec" "$HOST:$REMOTE/SPECS/"
scp -q "$HERE/container-build.sh" "$HOST:$REMOTE/"
ssh -o BatchMode=yes "$HOST" "nice -n 10 podman run --rm --network=none -e PF_JOBS=$JOBS -v '$REMOTE:/work:Z' '$IMAGE' bash /work/container-build.sh"

rm -rf "$OUT"
mkdir -p "$OUT"
rsync -a "$HOST:$REMOTE/RPMS" "$HOST:$REMOTE/SRPMS" "$HOST:$REMOTE/build.log" "$OUT/"
rpm_file=$(ls "$OUT"/RPMS/x86_64/$NAME-$VERSION-*.x86_64.rpm)
mkdir -p "$OUT/root"
(cd "$OUT/root" && rpm2cpio "$rpm_file" | cpio -idm --quiet)
echo "RPM: $rpm_file"
find "$OUT/root" -type f | sed "s|$OUT/root||" | sort
