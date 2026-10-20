#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# SDDM login theme (packages/sddm-theme/, docs/parts/sddm.md). Nothing is staged into the HOME
# tree - the theme is a system part (share/sddm/themes/plasmafusion) built by its build.sh and
# installed by packaging/install-tree.sh; tools/system/greeter-apply.sh selects it. This runs its
# contract checks (the metadata and theme.conf SDDM reads, the dependency-free QML, byte-identical
# builds): packages/sddm-theme/tests/contract_test.py.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"
python3 "$ROOT/packages/sddm-theme/tests/contract_test.py"
echo "  sddm -> contract checks (the theme is staged by packages/sddm-theme/build.sh)"
