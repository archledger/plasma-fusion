#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Power tiers service (docs/parts/powerfx.md), staged into the HOME tree:
#   $STAGE/.local/libexec/plasma-fusion/plasma-fusion-powerfx   the service (0755); a system package
#                                                               installs it as
#                                                               /usr/libexec/plasma-fusion/plasma-fusion-powerfx
#   $STAGE/.config/systemd/user/plasma-fusion-powerfx.service    its user unit (0644), a per-user
#                                                               template like the other .config files
#   $STAGE/.local/share/plasma-fusion/powerfx/plasma-fusion-powerfx.service
#                                                               the same unit where fusion-config.sh
#                                                               looks for it (the build being
#                                                               installed or /usr/share) to enable it
# The unit finds the script in ~/.local/libexec/plasma-fusion, /usr/local/libexec/plasma-fusion,
# /usr/libexec/plasma-fusion, /usr/lib/plasma-fusion or NixOS's
# /run/current-system/sw/libexec/plasma-fusion (ExecSearchPath). Installing enables nothing:
# fusion-config.sh does.
# Checks: bash -n, shellcheck -S warning (when installed), the unit's key lines, and with node the
# widget script's unit test (packages/powerfx/tests/widgets.test.js).
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

SRC=$ROOT/packages/powerfx
SCRIPT=$SRC/plasma-fusion-powerfx
UNIT=$SRC/plasma-fusion-powerfx.service

bash -n "$SCRIPT"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "$SCRIPT"
fi
for line in 'ExecStart=plasma-fusion-powerfx' 'ExecStopPost=-plasma-fusion-powerfx --apply full' \
  'ExecSearchPath=%h/.local/libexec/plasma-fusion:/usr/local/libexec/plasma-fusion:/usr/libexec/plasma-fusion:/usr/lib/plasma-fusion:/run/current-system/sw/libexec/plasma-fusion' \
  'PartOf=graphical-session.target' 'WantedBy=graphical-session.target'; do
  grep -qxF "$line" "$UNIT" || { echo "powerfx: $UNIT lacks '$line'" >&2; exit 1; }
done
grep -q "<<'JS'\$" "$SCRIPT" && grep -qx 'JS' "$SCRIPT" || { echo "powerfx: widget script not found" >&2; exit 1; }
if command -v node >/dev/null 2>&1; then
  node "$SRC/tests/widgets.test.js" >/dev/null
fi

install -D -m 0755 "$SCRIPT" "$STAGE/.local/libexec/plasma-fusion/plasma-fusion-powerfx"
install -D -m 0644 "$UNIT" "$STAGE/.config/systemd/user/plasma-fusion-powerfx.service"
install -D -m 0644 "$UNIT" "$STAGE/.local/share/plasma-fusion/powerfx/plasma-fusion-powerfx.service"
echo "  powerfx -> .local/libexec/plasma-fusion/plasma-fusion-powerfx, .config/systemd/user/plasma-fusion-powerfx.service"
