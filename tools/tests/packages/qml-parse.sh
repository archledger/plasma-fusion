#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# After a package install (tools/tests/packages/*.sh): every installed Plasma Fusion QML file must
# parse with this system's Qt (qmlformat). Debian testing has Qt 6.10, whose parser still reserves
# words that Qt 6.11 accepts as names ("short" broke the clock pill there, 2026-10-03).
set -euo pipefail
q=''
for c in qmlformat6 qmlformat /usr/lib/qt6/bin/qmlformat /usr/lib64/qt6/bin/qmlformat /usr/lib/x86_64-linux-gnu/qt6/bin/qmlformat; do
  if command -v "$c" >/dev/null 2>&1; then q=$(command -v "$c"); break; fi
done
[ -n "$q" ] || q=$(find /usr/lib /usr/lib64 /usr/libexec -name qmlformat -type f -perm -u+x 2>/dev/null | head -n 1)
[ -n "$q" ] || { echo "qmlformat is not installed (Qt's declarative development tools)" >&2; exit 1; }
n=0 bad=0
while IFS= read -r -d '' f; do
  n=$((n + 1))
  if ! out=$("$q" "$f" 2>&1 >/dev/null); then
    bad=$((bad + 1))
    printf 'does not parse with %s: %s\n%s\n' "$("$q" --version 2>/dev/null | tail -n 1)" "$f" "$(head -n 3 <<<"$out")"
  fi
done < <(find /usr/share/plasma/plasmoids/org.plasmafusion.* /usr/share/plasma/shells/org.plasmafusion.* \
  /usr/share/plasma/look-and-feel/org.plasmafusion.* /usr/share/kwin/tabbox/org.plasmafusion.* \
  /usr/share/kwin/scripts/plasmafusion-* /usr/share/kwin/effects/plasmafusion_* -name '*.qml' -print0 2>/dev/null)
echo "QML parse ($("$q" --version 2>/dev/null | tail -n 1)): $n files, $bad failed"
[ "$bad" = 0 ]
