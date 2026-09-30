#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build the Plasma Fusion Plymouth theme directory (system-wide part, not in the HOME stage).
#
#   generators/plymouth/build.sh [OUTDIR]     default: stage/plymouth/plasma-fusion
#
# PF_PLYMOUTH_META=FILE also writes the layout tables for tests/preview.py.
# Install on the target with tools/system/plymouth-install.sh (root).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${1:-$ROOT/stage/plymouth/plasma-fusion}
meta=()
[ -n "${PF_PLYMOUTH_META:-}" ] && meta=(--meta "$PF_PLYMOUTH_META")
python3 -B "$ROOT/generators/plymouth/gen_plymouth.py" "$OUT" "${meta[@]}"
python3 -B "$ROOT/generators/plymouth/tests/check_theme.py" "$OUT"
