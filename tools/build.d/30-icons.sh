#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Icon themes PlasmaFusion (light UI, inherits breeze) and PlasmaFusion-Dark (dark UI, inherits
# breeze-dark) -> $STAGE/.local/share/icons/. Python 3 standard library only; the generator reads
# the committed tables generators/icons/{glyphs,mimetable,outlines,capture}.json (see docs/parts/icons.md).
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"
out="$STAGE/.local/share/icons"
mkdir -p "$out"
python3 "$ROOT/generators/icons/gen_icons.py" --out "$out"
