#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# SDDM login theme (packages/sddm-theme/, docs/parts/sddm.md). Nothing is staged into the HOME
# tree - the theme is a system part (share/sddm/themes/plasmafusion) built by its build.sh and
# installed by packaging/install-tree.sh. Selection by greeter-apply.sh is a follow-up. This runs
# the file/packaging contract and the actual theme with Qt key events and stand-in SDDM models;
# no greeter daemon or session is contacted.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"
python3 "$ROOT/packages/sddm-theme/tests/contract_test.py"
QT_QPA_PLATFORM=offscreen python3 "$ROOT/packages/sddm-theme/tests/behavior_test.py"
QT_QPA_PLATFORM=offscreen python3 "$ROOT/packages/sddm-theme/tests/avatar_test.py"
echo "  sddm -> contract + behavior + avatar checks (theme staged by packages/sddm-theme/build.sh)"
