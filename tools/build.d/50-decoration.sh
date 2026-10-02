#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Window decorations: Aurorae v2 SVG themes PlasmaFusionDark, PlasmaFusionLight,
# PlasmaFusionDark-Left and PlasmaFusionLight-Left -> $STAGE/.local/share/aurorae/themes/
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"
out="$STAGE/.local/share/aurorae/themes"
themes=(PlasmaFusionDark PlasmaFusionLight PlasmaFusionDark-Left PlasmaFusionLight-Left)
mkdir -p "$out"
for t in "${themes[@]}"; do rm -rf "${out:?}/$t"; done
python3 -B "$ROOT/generators/decoration/gen_aurorae.py" "$out" >/dev/null
for t in "${themes[@]}"; do
  d="$out/$t"
  for f in metadata.desktop "${t}rc" decoration.svg minimize.svg maximize.svg restore.svg close.svg; do
    [ -s "$d/$f" ] || { echo "decoration: missing $d/$f" >&2; exit 1; }
  done
  # the menu slot must stay empty so Aurorae draws the window's own icon there
  [ ! -e "$d/menu.svg" ] || { echo "decoration: unexpected $d/menu.svg" >&2; exit 1; }
  find "$d" -type f -exec chmod 0644 {} +
  chmod 0755 "$d"
done
echo "decoration: ${themes[*]}"
