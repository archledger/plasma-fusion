#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Battery charge limit (docs/parts/charge-limit.md), staged into the HOME tree:
#   $STAGE/.local/libexec/plasma-fusion/plasma-fusion-charge-limit   the helper (0755); the system
#                                                                   package installs it as
#                                                                   /usr/libexec/plasma-fusion/...
#   $STAGE/.local/share/polkit-1/actions/org.plasmafusion.charge-limit.policy
#                                                                   its polkit action (0644; only
#                                                                   effective in /usr/share/polkit-1)
# The quick settings' charge-limit tile shows only where both are installed system-wide and a
# battery has a stop threshold. Checks: bash -n, shellcheck -S warning (when installed), xmllint.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

SRC=$ROOT/packages/power/charge-limit
bash -n "$SRC/plasma-fusion-charge-limit"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "$SRC/plasma-fusion-charge-limit"
fi
if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$SRC/org.plasmafusion.charge-limit.policy"
fi
bash "$SRC/tests/args_test.sh" "$SRC/plasma-fusion-charge-limit"
grep -q '<annotate key="org.freedesktop.policykit.exec.path">/usr/libexec/plasma-fusion/plasma-fusion-charge-limit</annotate>' \
  "$SRC/org.plasmafusion.charge-limit.policy" || { echo "charge-limit: exec.path annotation missing" >&2; exit 1; }

install -D -m 0755 "$SRC/plasma-fusion-charge-limit" "$STAGE/.local/libexec/plasma-fusion/plasma-fusion-charge-limit"
install -D -m 0644 "$SRC/org.plasmafusion.charge-limit.policy" "$STAGE/.local/share/polkit-1/actions/org.plasmafusion.charge-limit.policy"
echo "  charge-limit -> .local/libexec/plasma-fusion/plasma-fusion-charge-limit, .local/share/polkit-1/actions/org.plasmafusion.charge-limit.policy"
