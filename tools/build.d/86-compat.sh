#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Per-app compatibility rules (HIDPI-1): the LibreOffice scale guard and the desktop entry that
# names its XWayland windows. fusion-config.sh links ~/.local/bin/libreoffice to the guard and
# copies the entry into ~/.local/share/applications when LibreOffice is installed.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"
SRC=$ROOT/packages/compat
bash -n "$SRC/plasma-fusion-libreoffice"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "$SRC/plasma-fusion-libreoffice"
fi
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$SRC/soffice.desktop"
fi
install -D -m 0755 "$SRC/plasma-fusion-libreoffice" "$STAGE/.local/libexec/plasma-fusion/plasma-fusion-libreoffice"
install -D -m 0644 "$SRC/soffice.desktop" "$STAGE/.local/share/plasma-fusion/compat/soffice.desktop"
echo "  compat -> .local/libexec/plasma-fusion/plasma-fusion-libreoffice, .local/share/plasma-fusion/compat/soffice.desktop"
