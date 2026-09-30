#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Laptop side: build the decoration and its RPM on the test device in the build container.
#
#   packages/decoration-cpp/tools/build-rpm.sh [OUT_DIR]
#
# Copies this package to ~/.local/state/plasma-fusion/decoration-cpp/src on $PF_HOST (default
# thinkpad-fedora; PF_REMOTE overrides the directory below HOME), runs tools/container-build.sh in
# localhost/plasma-fusion-build:f44-6.7.5 (nice 10, 6 jobs, no network), and fetches the plugin,
# pfdeco-preview and the RPM into OUT_DIR (default build/cx/out). Nothing is installed. CLEAN=1
# rebuilds from scratch.
set -euo pipefail
PKG=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(cd "$PKG/../.." && pwd)
HOST=${PF_HOST:-thinkpad-fedora}
OUT=${1:-$ROOT/build/cx/out}
REMOTE=${PF_REMOTE:-.local/state/plasma-fusion/decoration-cpp}
IMAGE=localhost/plasma-fusion-build:f44-6.7.5

ssh -o BatchMode=yes "$HOST" "mkdir -p ~/$REMOTE/src ~/$REMOTE/build"
rsync -a --delete --exclude build --exclude __pycache__ "$PKG/" "$HOST:$REMOTE/src/"
ssh -o BatchMode=yes "$HOST" "podman image exists $IMAGE && cd ~/$REMOTE && \
  nice -n 10 podman run --rm --network=none -e JOBS=6 -e CLEAN=${CLEAN:-0} -v \$PWD:/work:Z $IMAGE bash /work/src/tools/container-build.sh"
mkdir -p "$OUT"
rsync -a "$HOST:$REMOTE/build/bin/" "$OUT/bin/" 2>/dev/null || true
rsync -a "$HOST:$REMOTE/rpmbuild/RPMS/x86_64/" "$OUT/rpm/"
echo "results in $OUT"
