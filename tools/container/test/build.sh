#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build a Plasma test image for tools/vsession/cvsession.sh from a build image:
#   tools/container/test/build.sh BASE_IMAGE TAG
#   e.g. tools/container/test/build.sh localhost/plasma-fusion-build:f44-6.7.5 localhost/plasma-fusion-test:f44-6.7.5
# The build context is a temporary directory with only the compiled parts' sources (the repository's
# build/ tree is many GB).
set -euo pipefail
BASE=${1:?base image}; TAG=${2:?tag}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CTX=$(mktemp -d "$ROOT/build/container-ctx.XXXXXX")
trap 'rm -rf "$CTX"' EXIT
mkdir -p "$CTX/packages" "$CTX/tools/container/test"
cp -a "$ROOT"/packages/{common,decoration-cpp,kcm-cpp,navigation-cpp} "$CTX/packages/"
cp "$ROOT/tools/container/test/install-parts.sh" "$CTX/tools/container/test/"
podman build --build-arg "BASE=$BASE" -t "$TAG" -f "$ROOT/tools/container/test/Containerfile" "$CTX"
