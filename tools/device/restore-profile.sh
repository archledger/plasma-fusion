#!/bin/bash
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
  .local/share/plasma/plasmoids/org.plasmafusion.dock
  .local/share/icons/PlasmaFusion .local/share/icons/PlasmaFusion-Dark
  .local/share/icons/PlasmaFusion-cursors .local/share/icons/PlasmaFusion-Light-cursors
  .local/share/aurorae/themes/PlasmaFusionDark .local/share/aurorae/themes/PlasmaFusionLight
  .local/share/aurorae/themes/PlasmaFusionDark-Left .local/share/aurorae/themes/PlasmaFusionLight-Left
  .local/share/kwin/tabbox/org.plasmafusion.switcher .local/share/kwin/scripts/plasmafusion-snap
  .local/share/kwin/scripts/plasmafusion-attach
  .local/share/fonts/plasma-fusion .local/share/plasma-fusion
  .config/systemd/user/plasma-kwin_wayland.service.d/plasma-fusion-lockscreen.conf
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
for p in "${ADDED[@]}"; do
  if ! grep -qx -- "$p" "$WORK/paths.txt" && ! grep -q -- "^$p/" "$WORK/paths.txt" && [ -e "$p" ]; then
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
