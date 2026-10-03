#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# After a package install (tools/tests/packages/*.sh): every QML module the installed Plasma Fusion
# files import must be on the system (its qmldir in Qt's QML directory), apart from the modules
# their hosts provide in-process and those of optional tiles. A dependency the packages forget (the
# dock's org.kde.layershell on Debian and Ubuntu, 2026-10-03) fails here instead of on a desktop.
set -euo pipefail
qml=$(qtpaths6 --query QT_INSTALL_QML 2>/dev/null || true)
for d in "$qml" /usr/lib64/qt6/qml /usr/lib/qt6/qml /usr/lib/x86_64-linux-gnu/qt6/qml; do
  [ -n "$d" ] && [ -d "$d/QtQuick" ] && { qml=$d; break; }
done
[ -d "$qml/QtQuick" ] || { echo "no Qt QML directory found" >&2; exit 1; }
# Provided by the process that loads the file: KWin (window switcher, scripts, effects) and the lock
# screen greeter. Files loaded with a Loader degrade on their own: the quick settings services
# (services/*.qml; a missing module leaves its tile out: no Bluetooth stack, no KDE Connect, no
# PowerDevil) and the lock screen's network indicator (no plasma-nm): reported, not an error.
inprocess=" org.kde.kwin org.kde.kwin.private.effects org.kde.kscreenlocker "
loaded='/org\.plasmafusion\.quicksettings/contents/ui/services/|/org\.plasmafusion\.lockshell/contents/lockscreen/NetworkIndicator\.qml$'
files=$(find /usr/share/plasma/plasmoids/org.plasmafusion.* /usr/share/plasma/shells/org.plasmafusion.* \
  /usr/share/plasma/look-and-feel/org.plasmafusion.* /usr/share/kwin/tabbox/org.plasmafusion.* \
  /usr/share/kwin/scripts/plasmafusion-* /usr/share/kwin/effects/plasmafusion_* \
  -name '*.qml' 2>/dev/null)
[ -n "$files" ] || { echo "no Plasma Fusion QML files installed" >&2; exit 1; }
missing=0
for m in $(printf '%s\n' "$files" | xargs grep -hoE '^[[:space:]]*import[[:space:]]+[A-Za-z][A-Za-z0-9_.]*' | awk '{print $2}' | sort -u); do
  [ -f "$qml/${m//.//}/qmldir" ] && continue
  case $inprocess in *" $m "*) continue ;; esac
  users=$(printf '%s\n' "$files" | xargs grep -lE "^[[:space:]]*import[[:space:]]+${m//./\\.}([[:space:]]|$)")
  if ! printf '%s\n' "$users" | grep -qvE "$loaded"; then
    echo "optional, not installed: $m (loaded with a Loader: $(printf '%s\n' "$users" | head -n 1 | xargs basename))"
    continue
  fi
  echo "MISSING QML module: $m (imported by $(printf '%s\n' "$users" | head -n 1))"
  missing=1
done
[ "$missing" = 0 ] && echo "QML imports: all present in $qml"
exit "$missing"
