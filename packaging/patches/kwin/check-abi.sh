#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Compare debug builds with the same architecture, configuration and dependency versions.
# This checks object layout, not the entire KWin ABI or every plugin's behavior.
set -euo pipefail
[[ $# == 2 ]] || { echo "usage: $0 STOCK_LIBKWIN PATCHED_LIBKWIN" >&2; exit 64; }
stock=$(realpath "$1")
patched=$(realpath "$2")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export LC_ALL=C
for type in Window XdgSurfaceWindow XdgToplevelWindow X11Window InternalWindow XXPipV1Window; do
    for side in stock patched; do
        lib=$stock
        [[ $side == stock ]] || lib=$patched
        gdb --batch --nx -iex 'set auto-load off' -iex 'set debuginfod enabled off' \
            --se="$lib" -ex "ptype /o KWin::$type" > "$work/$side"
        grep -q 'total size (bytes):' "$work/$side"
    done
    diff -u --label "stock/$type" --label "patched/$type" "$work/stock" "$work/patched"
    echo "PASS: KWin::$type object layout"
done
