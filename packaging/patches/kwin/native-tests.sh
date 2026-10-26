#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Build the backported KWin tests from the same prepared source as build.sh, with Fedora's own
# configuration and compiler flags plus BUILD_TESTING=ON, and run the backport's suites.
# --stock builds Fedora's source package without the backport, for comparison.
# Usage: native-tests.sh [--stock] OUT_DIR [VERSION-RELEASE]
# Exit status: 0 every suite passed, 1 a suite failed in all its attempts, 3 setup or build failed,
# 64 usage.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
variant=backport
if [[ ${1:-} == --stock ]]; then
    variant=stock
    shift
fi
if (( $# < 1 || $# > 2 )); then
    echo "usage: $0 [--stock] OUT_DIR [VERSION-RELEASE]" >&2
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
    registry.fedoraproject.org/fedora:44 bash /patches/native-tests-in-container.sh "$vr" "$variant"
