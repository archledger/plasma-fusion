#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# After the packages are installed (fedora.sh, deb.sh, arch.sh, as root in their container): every
# compiled part installed its record of what it was built against, and `plasma-fusion status` names
# each one as installed, with that record.
set -euo pipefail
parts=(decoration settings navigation quicklook copytext)
status=$(plasma-fusion status)
printf '%s\n' "$status" | sed -n '1,/tested with Plasma/p'
for p in "${parts[@]}"; do
  f=/usr/share/plasma-fusion/built-against/$p
  test -s "$f" || { echo "parts: no $f" >&2; exit 1; }
  line="  $p: installed, built against $(tr '\n' ' ' <"$f" | sed 's/ $//')"
  grep -qxF -- "$line" <<<"$status" || { echo "parts: plasma-fusion status does not say '$line'" >&2; exit 1; }
done
echo "parts: ${#parts[@]} compiled parts installed and named by plasma-fusion status"
