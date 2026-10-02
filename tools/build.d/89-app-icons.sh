#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Familiar app icons (docs/parts/app-icons.md), staged into the HOME tree:
#   $STAGE/.local/libexec/plasma-fusion/plasma-fusion-app-icons   the tool (0755); a system package
#                                                                 installs it as
#                                                                 /usr/libexec/plasma-fusion/...
#   $STAGE/.local/share/plasma-fusion/appicons/plasma-fusion-app-icons.service
#                                                                 its user unit, where fusion-config.sh
#                                                                 looks for it to enable it
# Checks: python3 compile, the unit's key lines, and a dry run of the tool's composition on one
# synthetic icon of each kind when Pillow and rsvg-convert or PySide6 are present.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

SRC=$ROOT/packages/appicons
TOOL=$SRC/plasma-fusion-app-icons
UNIT=$SRC/plasma-fusion-app-icons.service
python3 - "$TOOL" <<'PY'
import sys
compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")
PY
for line in 'ExecStart=plasma-fusion-app-icons watch' \
  'ExecSearchPath=%h/.local/libexec/plasma-fusion:/usr/local/libexec/plasma-fusion:/usr/libexec/plasma-fusion' \
  'PartOf=graphical-session.target' 'WantedBy=graphical-session.target'; do
  grep -qxF "$line" "$UNIT" || { echo "app-icons: $UNIT lacks '$line'" >&2; exit 1; }
done
if python3 -c 'import PIL' 2>/dev/null; then
  python3 "$SRC/tests/compose_test.py" "$TOOL"
fi

install -D -m 0755 "$TOOL" "$STAGE/.local/libexec/plasma-fusion/plasma-fusion-app-icons"
install -D -m 0644 "$UNIT" "$STAGE/.local/share/plasma-fusion/appicons/plasma-fusion-app-icons.service"
echo "  app-icons -> .local/libexec/plasma-fusion/plasma-fusion-app-icons, plasma-fusion/appicons/"
