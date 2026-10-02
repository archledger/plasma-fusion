#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Undo tools/system/plymouth-install.sh. Run as root on the target machine.
#
#   plymouth-uninstall.sh [--theme NAME] [--all-kernels] [--keep-files] [--remove-plugin] [--dry-run]
#
#   --theme NAME     theme to go back to (default: the one recorded by plymouth-install.sh
#                    --select, else bgrt, Fedora's default)
#   --all-kernels    rebuild the initramfs of every installed kernel, not only the running one
#   --keep-files     leave /usr/share/plymouth/themes/plasma-fusion in place
#   --remove-plugin  also remove plymouth-plugin-script if plymouth-install.sh installed it
#   --dry-run        print what would be done
#
# The greeting choice remembered by plymouth-install.sh --user/--name is forgotten too.
# When Plasma Fusion is the selected theme, the saved /etc/plymouth/plymouthd.conf is put back
# (or the previous theme selected) and the initramfs rebuilt (also when it is no longer selected
# but the running kernel's image still holds it). A copy made by --select
# (/boot/initramfs-<kernel>.img.pre-plasma-fusion) is removed once that kernel's image no longer
# contains the theme, or when that kernel is gone. --dry-run lists the exact steps only as root.
# Emergency rollback without this script: at the GRUB menu press e and add plymouth.enable=0 (or
# change the initrd line to the .pre-plasma-fusion copy), or run plymouth-set-default-theme -R bgrt.
set -euo pipefail

NAME=plasma-fusion
THEMES=/usr/share/plymouth/themes
STATE=/var/lib/plasma-fusion/plymouth
THEME=
THEME_GIVEN=0
ALL=0
KEEP=0
PLUGIN=0
DRY=0
while [ $# -gt 0 ]; do
  case $1 in
    --theme) shift; THEME=${1:?--theme needs a value}; THEME_GIVEN=1 ;;
    --all-kernels) ALL=1 ;;
    --keep-files) KEEP=1 ;;
    --remove-plugin) PLUGIN=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) awk 'NR > 3 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    *) echo "plymouth-uninstall: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
# The counterpart of plymouth-install.sh: dracut and dnf (Fedora) only.
if ! command -v dracut >/dev/null || ! command -v lsinitrd >/dev/null || ! command -v dnf >/dev/null; then
  echo "plymouth-uninstall: this tool needs dracut and dnf (Fedora), as plymouth-install.sh. Nothing was changed." >&2
  exit 3
fi
if [ "$DRY" = 0 ] && [ "$(id -u)" != 0 ]; then
  echo "plymouth-uninstall: run as root (sudo)" >&2; exit 1
fi
run() {
  echo "+ $*"
  [ "$DRY" = 1 ] || "$@"
}

KVER=$(uname -r)
IMG=/boot/initramfs-$KVER.img
BACKUP=$IMG.pre-$NAME
if [ -z "$THEME" ]; then
  THEME=$(cat "$STATE/previous-theme" 2>/dev/null || true)
  [ -n "$THEME" ] || THEME=bgrt
fi

# Prints "theme" when the initramfs image $1 holds the theme, "clean" when it does not, and
# "unknown" when it cannot be listed.
image_state() {
  local listing
  if ! listing=$(lsinitrd "$1" 2>/dev/null) || [ -z "$listing" ]; then
    echo unknown
  elif grep -q "usr/share/plymouth/themes/$NAME/" <<< "$listing"; then
    echo theme
  else
    echo clean
  fi
}

rebuild=0
if [ "$(plymouth-set-default-theme)" = "$NAME" ]; then
  if [ -f "$STATE/plymouthd.conf.orig" ] && [ "$THEME_GIVEN" = 0 ]; then
    run install -m 0644 "$STATE/plymouthd.conf.orig" /etc/plymouth/plymouthd.conf
    command -v restorecon >/dev/null && run restorecon /etc/plymouth/plymouthd.conf
    now=$(plymouth-set-default-theme)
    if [ "$DRY" = 0 ] && [ "$now" = "$NAME" ]; then
      run plymouth-set-default-theme "$THEME"
    fi
  else
    run plymouth-set-default-theme "$THEME"
  fi
  if [ "$DRY" = 0 ]; then
    echo "default theme is now: $(plymouth-set-default-theme)"
  else
    echo "(dry run: the default theme would become the one in the saved plymouthd.conf, or $THEME)"
  fi
  rebuild=1
else
  echo "$NAME is not the selected theme (current: $(plymouth-set-default-theme))"
  # Deselected by hand without -R: the running kernel's image may still carry it.
  if [ "$DRY" = 0 ] && [ "$(image_state "$IMG")" = theme ]; then
    echo "$IMG still contains $NAME"
    rebuild=1
  fi
fi
if [ "$rebuild" = 1 ] || [ "$ALL" = 1 ]; then
  if [ "$ALL" = 1 ]; then
    run nice -n 10 dracut -f --regenerate-all
  else
    run nice -n 10 dracut -f "$IMG" "$KVER"
  fi
  if [ "$DRY" = 0 ] && [ "$(image_state "$IMG")" != clean ]; then
    echo "plymouth-uninstall: $IMG still contains $NAME (or cannot be listed); the backup $BACKUP is kept" >&2
    exit 1
  fi
else
  echo "no initramfs rebuild needed"
fi

# The copies made by --select: remove each one once its kernel's image no longer holds the
# theme, or the kernel has been removed since; keep the others as that kernel's way back.
for b in /boot/initramfs-*.img.pre-"$NAME"; do
  [ -e "$b" ] || continue
  base=${b%.pre-"$NAME"}
  if [ ! -e "$base" ]; then
    run rm -f "$b"
  elif [ "$DRY" = 1 ]; then
    echo "+ rm -f $b (if $base no longer contains $NAME)"
  elif [ "$(image_state "$base")" = clean ]; then
    run rm -f "$b"
  else
    echo "note: keeping $b: $base still contains $NAME (rebuild it with dracut -f --regenerate-all)"
  fi
done

if [ "$KEEP" = 0 ] && [ -d "$THEMES/$NAME" ]; then
  if [ "$ALL" = 0 ] && [ "$DRY" = 0 ]; then
    for img in /boot/initramfs-*.img; do
      [ "$img" = "$IMG" ] && continue
      if [ "$(image_state "$img")" = theme ]; then
        echo "note: $img still contains $NAME (rebuild it with dracut -f --regenerate-all)"
      fi
    done
  fi
  run rm -rf "$THEMES/$NAME"
fi
if [ "$PLUGIN" = 1 ] && grep -qx plymouth-plugin-script "$STATE/installed-packages" 2>/dev/null; then
  run dnf remove -y plymouth-plugin-script
  [ "$DRY" = 1 ] || rm -f "$STATE/installed-packages"
fi
if [ "$DRY" = 0 ]; then
  rm -f "$STATE/previous-theme" "$STATE/plymouthd.conf.orig" "$STATE/greeting"
  rmdir "$STATE" /var/lib/plasma-fusion 2>/dev/null || true
fi
echo "done"
