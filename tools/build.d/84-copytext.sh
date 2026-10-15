#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copy text from the screen in one step (docs/parts/device.md), staged into the HOME tree:
#   $STAGE/.local/libexec/plasma-fusion/plasma-fusion-copytext   the helper (0755); the system
#                                                               package installs it as
#                                                               /usr/libexec/plasma-fusion/...
# fusion-config.sh gives Meta+Shift+T its command, quick settings' header button runs it too.
# Checks: bash -n and ShellCheck (its behaviour: packages/copytext/tests/helper-unit.sh, CI).
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"
SRC=$ROOT/packages/copytext/plasma-fusion-copytext
bash -n "$SRC"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "$SRC"
fi
install -D -m 0755 "$SRC" "$STAGE/.local/libexec/plasma-fusion/plasma-fusion-copytext"
echo "  copytext -> .local/libexec/plasma-fusion/plasma-fusion-copytext"
