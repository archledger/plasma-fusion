#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Rebuild Fedora 44 KWin 6.7.5 with the optional requestedGeometry backport.
# Usage: build.sh OUT_DIR [VERSION-RELEASE]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
if (( $# < 1 || $# > 2 )); then
    echo "usage: $0 OUT_DIR [VERSION-RELEASE]" >&2
    exit 64
fi
vr=${2:-$(rpm -q --qf '%{VERSION}-%{RELEASE}' kwin)}
if [[ ! $vr =~ ^6\.7\.5-[0-9]+\.fc44$ ]]; then
    echo "unsupported KWin build: $vr (expected 6.7.5-N.fc44)" >&2
    exit 64
fi
mkdir -p "$1"
out=$(cd "$1" && pwd)
if [[ -n $(find "$out" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
    echo "output directory must be empty: $out" >&2
    exit 64
fi
podman run --rm --init --cpus=4 --memory=8g \
    -v "$here":/patches:ro,z -v "$out":/out:Z \
    registry.fedoraproject.org/fedora:44 bash /patches/build-in-container.sh "$vr"
(cd "$out" && sha256sum -- *.rpm > SHA256SUMS)
echo "Built RPMs and SHA256SUMS in $out; nothing was installed."
