#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Saved app pairs (docs/parts/apppairs.md), staged into the HOME tree:
#   $STAGE/.local/libexec/plasma-fusion/plasma-fusion-app-pair   the helper (0755); the system
#                                                                package installs it as
#                                                                /usr/libexec/plasma-fusion/...
# The app switcher's "Save pair" runs it, the home screen's pair menu too.
# Checks: bash -n and ShellCheck (its behaviour: packages/apppairs/tests/helper-unit.sh, CI).
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"
SRC=$ROOT/packages/apppairs/plasma-fusion-app-pair
bash -n "$SRC"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "$SRC"
fi
install -D -m 0755 "$SRC" "$STAGE/.local/libexec/plasma-fusion/plasma-fusion-app-pair"
echo "  app pairs -> .local/libexec/plasma-fusion/plasma-fusion-app-pair"
