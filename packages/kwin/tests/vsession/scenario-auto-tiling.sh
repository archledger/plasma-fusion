#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Test-only native characterization. Requires a disposable cvsession container and pf-tools seed.
set -euo pipefail
export OUT
probe_status=0
python3 "$HOME/auto_tiling_probe.py" || probe_status=$?
# The outer private-session cleanup must run even when a probe assertion fails.
set +e
[ "$probe_status" = 0 ]
