#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Put back a profile snapshot made by backup-profile.sh, then restart the shell.
#
#   restore-profile.sh TARBALL [--dry-run]
#
# Every path recorded in the snapshot is restored exactly; paths that did not exist when the
# snapshot was taken but are known Plasma Fusion additions are removed. Log out and back in
# afterwards for KWin, fonts and the lock screen to pick up everything.
set -euo pipefail
TARBALL=${1:?tarball}
DRY=${2:-}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
tar -xzf "$TARBALL" -C "$WORK"

# Paths Plasma Fusion adds. Removed when they were absent in the snapshot.
ADDED=(
  .local/share/color-schemes/PlasmaFusionDark.colors .local/share/color-schemes/PlasmaFusionLight.colors
  .local/share/plasma/look-and-feel/org.plasmafusion.dark.desktop .local/share/plasma/look-and-feel/org.plasmafusion.light.desktop
  .local/share/plasma/desktoptheme/plasma-fusion-dark .local/share/plasma/desktoptheme/plasma-fusion-light
  .local/share/plasma/shells/org.plasmafusion.lockshell
  .local/share/plasma/plasmoids/org.plasmafusion.appname .local/share/plasma/plasmoids/org.plasmafusion.clockpill
  .local/share/plasma/plasmoids/org.plasmafusion.quicksettings .local/share/plasma/plasmoids/org.plasmafusion.launcher
  .local/share/plasma/plasmoids/org.plasmafusion.dock .local/share/plasma/plasmoids/org.plasmafusion.pen
  .local/share/plasma/plasmoids/org.plasmafusion.weathercard .local/share/plasma/plasmoids/org.plasmafusion.calendarcard
  .local/share/plasma/plasmoids/org.plasmafusion.systemcard
  .local/share/plasma/look-and-feel/org.plasmafusion.previous.desktop
  .local/share/icons/PlasmaFusion .local/share/icons/PlasmaFusion-Dark
  .local/share/icons/PlasmaFusion-cursors .local/share/icons/PlasmaFusion-Light-cursors
  .local/share/aurorae/themes/PlasmaFusionDark .local/share/aurorae/themes/PlasmaFusionLight
  .local/share/aurorae/themes/PlasmaFusionDark-Left .local/share/aurorae/themes/PlasmaFusionLight-Left
  .local/share/kwin/tabbox/org.plasmafusion.switcher .local/share/kwin/scripts/plasmafusion-snap
  .local/share/kwin/scripts/plasmafusion-attach .local/share/kwin/scripts/plasmafusion-tablet
  .local/share/fonts/plasma-fusion .local/share/plasma-fusion
  .local/share/kglobalaccel/org.plasmafusion.notifications.desktop .local/libexec/plasma-fusion
  .config/systemd/user/plasma-kwin_wayland.service.d/plasma-fusion-lockscreen.conf
  .config/plasma-workspace/env/plasma-fusion-gate.sh .config/plasma-workspace/env/plasma-fusion-session.sh
  .config/systemd/user/plasma-fusion-gate-notify.service
  .config/systemd/user/xdg-desktop-autostart.target.wants/plasma-fusion-gate-notify.service
  .config/systemd/user/plasma-fusion-powerfx.service
  .config/systemd/user/graphical-session.target.wants/plasma-fusion-powerfx.service
  .config/systemd/user/plasma-fusion-pen-garage.service
  .config/systemd/user/graphical-session.target.wants/plasma-fusion-pen-garage.service
)

run() { if [ "$DRY" = --dry-run ]; then echo "would: $*"; else "$@"; fi; }

cd "$HOME"
# Stop plasmashell first: it writes its layout file when it quits.
SHELL_UNIT=plasma-plasmashell.service
if [ "$DRY" != --dry-run ]; then
  if systemctl --user -q is-active "$SHELL_UNIT"; then
    systemctl --user stop "$SHELL_UNIT"
  else
    kquitapp6 plasmashell >/dev/null 2>&1 || true
    SHELL_UNIT=
  fi
  sleep 2
fi
# The power service gives its values back when it stops (and is not started again once its
# files are gone).
if [ "$DRY" != --dry-run ] && ! grep -q '^\.config/systemd/user/plasma-fusion-powerfx\.service$' "$WORK/paths.txt"; then
  systemctl --user stop plasma-fusion-powerfx.service plasma-fusion-pen-garage.service 2>/dev/null || true
fi
for p in "${ADDED[@]}"; do
  if ! grep -qx -- "$p" "$WORK/paths.txt" && ! grep -q -- "^$p/" "$WORK/paths.txt" && { [ -e "$p" ] || [ -L "$p" ]; }; then
    run rm -rf -- "$p"
  fi
done
for w in .local/share/wallpapers/PlasmaFusion*; do [ -e "$w" ] && run rm -rf -- "$w"; done
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ -d "$WORK/$p" ]; then
    run rm -rf -- "$p"; run mkdir -p "$(dirname "$p")"; run cp -a "$WORK/$p" "$p"
  else
    run mkdir -p "$(dirname "$p")"; run cp -a "$WORK/$p" "$p"
  fi
done <"$WORK/paths.txt"

if [ "$DRY" != --dry-run ]; then
  fc-cache -f >/dev/null 2>&1 || true
  systemctl --user daemon-reload || true
  qdbus-qt6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
  if [ -n "$SHELL_UNIT" ]; then systemctl --user start "$SHELL_UNIT"; else setsid -f plasmashell >/dev/null 2>&1; fi
fi
echo "Restored from $TARBALL. The display scale was recorded in kscreen.json inside it; log out and in to finish."
