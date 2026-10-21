#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Undo tools/system/plymouth-install.sh. Run as root on the target machine.
#
#   plymouth-uninstall.sh [--theme NAME] [--all-kernels] [--keep-files] [--remove-plugin] [--dry-run]
#
#   --theme NAME     theme to go back to (default: the one recorded by plymouth-install.sh
#                    --select, else the system's default: bgrt on Fedora, Plymouth's own
#                    elsewhere; where themes are an alternative (Ubuntu, KDE neon) the one it
#                    had)
#   --all-kernels    rebuild the initramfs of every installed kernel, not only the running one
#                    (Arch: mkinitcpio -P rebuilds every preset anyway)
#   --keep-files     leave /usr/share/plymouth/themes/plasma-fusion in place
#   --remove-plugin  also remove the package plymouth-install.sh installed for the script plugin
#                    (Fedora plymouth-plugin-script; Arch, Debian, Ubuntu plymouth)
#   --dry-run        print what would be done
#
# The greeting choice remembered by plymouth-install.sh --user/--name is forgotten too.
# When Plasma Fusion is the selected theme, the saved /etc/plymouth/plymouthd.conf is put back
# (or the previous theme selected; Ubuntu and KDE neon: the default.plymouth alternative put back)
# and the initramfs rebuilt (also when it is no longer selected but the running kernel's image
# still holds it), with the system's builder as plymouth-install.sh picks it; Arch's mkinitcpio
# drop-in of plymouth-install.sh is removed first. A copy made by --select
# (<image>.pre-plasma-fusion) is removed once that image no longer contains the theme, or when
# it is gone. --dry-run lists the exact steps only as root.
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
# The system's initramfs builder, its image lister and the theme selector, as plymouth-install.sh
# picks them.
BUILDER=
if [ -e /etc/NIXOS ]; then :
elif command -v mkinitcpio >/dev/null && command -v lsinitcpio >/dev/null && compgen -G "/etc/mkinitcpio.d/*.preset" >/dev/null; then
  BUILDER=mkinitcpio LIST=lsinitcpio
elif command -v dracut >/dev/null && command -v lsinitrd >/dev/null; then BUILDER=dracut LIST=lsinitrd
elif command -v update-initramfs >/dev/null && command -v lsinitramfs >/dev/null; then BUILDER=initramfs-tools LIST=lsinitramfs
fi
if [ -z "$BUILDER" ]; then
  echo "plymouth-uninstall: no initramfs builder found (dracut, mkinitcpio or initramfs-tools), as plymouth-install.sh needs. Nothing was changed." >&2
  exit 3
fi
if command -v plymouth-set-default-theme >/dev/null; then SELECTOR=set-default-theme
else SELECTOR=alternatives
fi
if [ "$DRY" = 0 ] && [ "$(id -u)" != 0 ]; then
  echo "plymouth-uninstall: run as root (sudo)" >&2; exit 1
fi
run() {
  echo "+ $*"
  [ "$DRY" = 1 ] || "$@"
}
ALT=default.plymouth
alternative() { update-alternatives --query "$ALT" 2>/dev/null | sed -n "s/^$1: //p"; }
current_theme() {
  local path
  if [ "$SELECTOR" = set-default-theme ]; then
    plymouth-set-default-theme
  else
    path=$(alternative Value)
    [ -z "$path" ] || basename "$path" .plymouth
  fi
}

# The images to rebuild, as plymouth-install.sh --select lists them (PF_PLYMOUTH_KERNEL: tests)
KVER=${PF_PLYMOUTH_KERNEL:-$(uname -r)}
IMAGES=()
case $BUILDER in
  dracut)
    for img in "/boot/initramfs-$KVER.img" "/boot/initrd.img-$KVER"; do
      if [ -f "$img" ]; then IMAGES=("$img"); break; fi
    done ;;
  initramfs-tools) [ ! -f "/boot/initrd.img-$KVER" ] || IMAGES=("/boot/initrd.img-$KVER") ;;
  mkinitcpio)
    mapfile -t IMAGES < <(for f in /etc/mkinitcpio.d/*.preset; do
      # shellcheck source=/dev/null # the system's presets, read as mkinitcpio -P reads them
      ( . "$f"; for p in "${PRESETS[@]}"; do
          for k in image uki; do v=${p}_$k; [ -z "${!v:-}" ] || printf '%s\n' "${!v}"; done
        done )
    done) ;;
esac
IMG=${IMAGES[0]:-}
if [ -z "$THEME" ]; then
  THEME=$(cat "$STATE/previous-theme" 2>/dev/null || true)
fi

# Prints "theme" when the initramfs image $1 holds the theme, "clean" when it does not, and
# "unknown" when it cannot be listed.
image_state() {
  local listing
  if ! listing=$("$LIST" "$1" 2>/dev/null) || [ -z "$listing" ]; then
    echo unknown
  elif grep -q "usr/share/plymouth/themes/$NAME/" <<< "$listing"; then
    echo theme
  else
    echo clean
  fi
}

# Arch: the plymouth hook drop-in plymouth-install.sh wrote (only that file, and only if it is still
# ours), before the rebuild
DROPIN=$(cat "$STATE/mkinitcpio-dropin" 2>/dev/null || true)
dropin=0
if [ -n "$DROPIN" ] && [ -f "$DROPIN" ] && grep -q "^# Plasma Fusion's boot splash (plymouth-install.sh)" "$DROPIN"; then
  run rm -f "$DROPIN"
  dropin=1
fi

rebuild=0
if [ "$(current_theme)" = "$NAME" ]; then
  if [ "$SELECTOR" = alternatives ]; then
    # Ours out of the alternative: back to the best remaining (auto), or to the theme chosen by hand
    # before (manual), or the --theme given
    run update-alternatives --remove "$ALT" "$THEMES/$NAME/$NAME.plymouth"
    read -r status path < "$STATE/previous-alternative" 2>/dev/null || status='' path=''
    if [ "$THEME_GIVEN" = 1 ]; then
      run update-alternatives --set "$ALT" "$THEMES/$THEME/$THEME.plymouth"
    elif [ "$status" = manual ] && [ -n "$path" ] && [ -e "$path" ]; then
      run update-alternatives --set "$ALT" "$path"
    fi
  elif [ -f "$STATE/plymouthd.conf.orig" ] && [ "$THEME_GIVEN" = 0 ]; then
    run install -m 0644 "$STATE/plymouthd.conf.orig" /etc/plymouth/plymouthd.conf
    command -v restorecon >/dev/null && run restorecon /etc/plymouth/plymouthd.conf
    now=$(plymouth-set-default-theme)
    if [ "$DRY" = 0 ] && [ "$now" = "$NAME" ]; then
      if [ -n "$THEME" ]; then run plymouth-set-default-theme "$THEME"; else run plymouth-set-default-theme --reset; fi
    fi
  elif [ -n "$THEME" ]; then
    run plymouth-set-default-theme "$THEME"
  elif command -v dnf >/dev/null; then
    # Fedora's default
    run plymouth-set-default-theme bgrt
  else
    run plymouth-set-default-theme --reset
  fi
  if [ "$DRY" = 0 ]; then
    echo "default theme is now: $(current_theme)"
  else
    fallback="the system's default"
    echo "(dry run: the default theme would become the one saved before Plasma Fusion, or ${THEME:-$fallback})"
  fi
  rebuild=1
else
  echo "$NAME is not the selected theme (current: $(current_theme))"
  # Ubuntu, neon: a theme chosen since leaves ours registered; removing it changes no selection
  if [ "$SELECTOR" = alternatives ] && update-alternatives --query "$ALT" 2>/dev/null | grep -qxF "Alternative: $THEMES/$NAME/$NAME.plymouth"; then
    run update-alternatives --remove "$ALT" "$THEMES/$NAME/$NAME.plymouth"
  fi
  # Deselected by hand without a rebuild: the running kernel's image may still carry it.
  if [ "$DRY" = 0 ] && [ -n "$IMG" ] && [ "$(image_state "$IMG")" = theme ]; then
    echo "$IMG still contains $NAME"
    rebuild=1
  fi
fi
[ "$dropin" = 0 ] || rebuild=1
if [ "$rebuild" = 1 ] || [ "$ALL" = 1 ]; then
  case $BUILDER:$ALL in
    dracut:1) run nice -n 10 dracut -f --regenerate-all ;;
    dracut:0)
      [ -n "$IMG" ] || { echo "plymouth-uninstall: no image of kernel $KVER to rebuild (--all-kernels rebuilds every one)" >&2; exit 1; }
      run nice -n 10 dracut -f "$IMG" "$KVER" ;;
    initramfs-tools:1) run nice -n 10 update-initramfs -u -k all ;;
    initramfs-tools:0) run nice -n 10 update-initramfs -u -k "$KVER" ;;
    mkinitcpio:*) run nice -n 10 mkinitcpio -P ;;
  esac
  if [ "$DRY" = 0 ]; then
    for img in "${IMAGES[@]}"; do
      if [ "$(image_state "$img")" != clean ]; then
        echo "plymouth-uninstall: $img still contains $NAME (or cannot be listed); its backup $img.pre-$NAME is kept" >&2
        exit 1
      fi
    done
  fi
else
  echo "no initramfs rebuild needed"
fi

# The copies made by --select: remove each one once its kernel's image no longer holds the
# theme, or the kernel has been removed since; keep the others as that kernel's way back.
mapfile -t backups < <({ printf '%s\n' /boot/*.pre-"$NAME"; printf '%s\n' "${IMAGES[@]/%/.pre-$NAME}"; } | sort -u)
for b in "${backups[@]}"; do
  [ -e "$b" ] || continue
  base=${b%.pre-"$NAME"}
  if [ ! -e "$base" ]; then
    run rm -f "$b"
  elif [ "$DRY" = 1 ]; then
    echo "+ rm -f $b (if $base no longer contains $NAME)"
  elif [ "$(image_state "$base")" = clean ]; then
    run rm -f "$b"
  else
    echo "note: keeping $b: $base still contains $NAME (rebuild it: --all-kernels)"
  fi
done

if [ "$KEEP" = 0 ] && [ -d "$THEMES/$NAME" ]; then
  if [ "$ALL" = 0 ] && [ "$DRY" = 0 ]; then
    for img in /boot/initramfs-*.img /boot/initrd.img-*; do
      [ -e "$img" ] || continue
      case " ${IMAGES[*]} " in *" $img "*) continue ;; esac
      case $img in *.pre-"$NAME") continue ;; esac
      if [ "$(image_state "$img")" = theme ]; then
        echo "note: $img still contains $NAME (rebuild it: --all-kernels)"
      fi
    done
  fi
  run rm -rf "$THEMES/$NAME"
fi
pkg=$(cat "$STATE/installed-packages" 2>/dev/null || true)
if [ "$PLUGIN" = 1 ] && [ -n "$pkg" ]; then
  if command -v dnf >/dev/null; then run dnf remove -y "$pkg"
  elif command -v pacman >/dev/null; then run pacman -R --noconfirm "$pkg"
  elif command -v apt-get >/dev/null; then run env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$pkg"
  fi
  [ "$DRY" = 1 ] || rm -f "$STATE/installed-packages"
fi
if [ "$DRY" = 0 ]; then
  rm -f "$STATE/previous-theme" "$STATE/plymouthd.conf.orig" "$STATE/greeting" "$STATE/previous-alternative" \
    "$STATE/mkinitcpio-dropin"
  rmdir "$STATE" /var/lib/plasma-fusion 2>/dev/null || true
fi
echo "done"
