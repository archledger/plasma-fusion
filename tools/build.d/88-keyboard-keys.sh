#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Terminal keys for the on-screen keyboard (docs/parts/keyboard.md), staged into the HOME tree:
#   $STAGE/.local/libexec/plasma-fusion/plasma-fusion-keyboard-keys   the tool (0755); the system
#                                                                    package installs it as
#                                                                    /usr/libexec/plasma-fusion/...
# fusion-config.sh runs it ("install"), the login stub ("refresh"). Checks: python3 compile and how
# it patches symbols.qml (tests/patch_test.py).
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

SRC=$ROOT/packages/keyboard/plasma-fusion-keyboard-keys
python3 - "$SRC" <<'PY'
import sys
compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")
PY
python3 "$ROOT/packages/keyboard/tests/patch_test.py" "$SRC"
install -D -m 0755 "$SRC" "$STAGE/.local/libexec/plasma-fusion/plasma-fusion-keyboard-keys"
echo "  keyboard-keys -> .local/libexec/plasma-fusion/plasma-fusion-keyboard-keys"
