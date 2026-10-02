#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Laptop side: build the decoration (development: the plugin and pfdeco-preview, no package) on the
# test device in the build container. The packages come from packaging/build-rpm.sh --compiled.
#
#   packages/decoration-cpp/tools/build-remote.sh [OUT_DIR]
#
# Copies this package to ~/.local/state/plasma-fusion/decoration-cpp/src on $PF_HOST (default
# thinkpad-fedora; PF_REMOTE overrides the directory below HOME), runs tools/container-build.sh in
# localhost/plasma-fusion-build:f44-6.7.5 (nice 10, 6 jobs, no network), and fetches the plugin and
# pfdeco-preview into OUT_DIR (default build/cx/out). Nothing is installed. CLEAN=1
# rebuilds from scratch. PF_SSH_OPTS (default "-o ConnectTimeout=40") adds ssh options; the
# caller serialises container builds (the team's build lock).
set -euo pipefail
PKG=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(cd "$PKG/../.." && pwd)
HOST=${PF_HOST:-thinkpad-fedora}
OUT=${1:-$ROOT/build/cx/out}
REMOTE=${PF_REMOTE:-.local/state/plasma-fusion/decoration-cpp}
IMAGE=localhost/plasma-fusion-build:f44-6.7.5
read -r -a SSH_OPTS <<<"${PF_SSH_OPTS:--o ConnectTimeout=40}"

ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$HOST" "mkdir -p ~/$REMOTE/src ~/$REMOTE/build"
rsync -a --delete -e "ssh ${SSH_OPTS[*]}" --exclude build --exclude __pycache__ "$PKG/" "$HOST:$REMOTE/src/"
ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$HOST" "podman image exists $IMAGE && cd ~/$REMOTE && \
  nice -n 10 podman run --rm --network=none -e JOBS=6 -e CLEAN=${CLEAN:-0} -v \$PWD:/work:Z $IMAGE bash /work/src/tools/container-build.sh"
mkdir -p "$OUT"
rsync -a -e "ssh ${SSH_OPTS[*]}" "$HOST:$REMOTE/build/bin/" "$OUT/bin/" 2>/dev/null || true
echo "results in $OUT"
