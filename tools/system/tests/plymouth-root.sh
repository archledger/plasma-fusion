#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tools/system/plymouth-install.sh --select and plymouth-uninstall.sh as root on a system's own
# initramfs builder and Plymouth, with an installed kernel: the theme selected and in the rebuilt
# image with Plymouth's script plugin, the state from before put back by the uninstall (the theme
# or the default.plymouth alternative, plymouthd.conf byte for byte, Arch's mkinitcpio hooks), the
# image without it, the backups and the files gone. It changes /boot, /etc and /usr/share/plymouth,
# so it runs only as root in a throw-away container (PF_DISPOSABLE_SYSTEM=1 allows another machine
# meant to be thrown away), with a kernel and the builder installed, e.g.:
#   podman run --rm -v "$PWD:/src:ro,z" registry.fedoraproject.org/fedora:44 bash -c \
#     'dnf -y -q install kernel-core dracut plymouth && cp -a /src /work && /work/tools/system/tests/plymouth-root.sh'
# The theme is a minimal stand-in (the installer's paths, not the drawing), or THEME_DIR, a build
# of generators/plymouth/build.sh. Test tooling only.
#
#   tools/system/tests/plymouth-root.sh [THEME_DIR]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../../.." && pwd)
INSTALL=$TOP/tools/system/plymouth-install.sh
UNINSTALL=$TOP/tools/system/plymouth-uninstall.sh
NAME=plasma-fusion
[ "$(id -u)" = 0 ] || { echo "plymouth-root: run as root, in a throw-away container" >&2; exit 1; }
[ -e /run/.containerenv ] || [ -e /.dockerenv ] || [ "${PF_DISPOSABLE_SYSTEM:-}" = 1 ] ||
  { echo "plymouth-root: not in a container; this changes /boot and the boot splash" >&2; exit 1; }
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
has() { grep -qF -- "$1" <<<"$OUT"; }
WORK=$(mktemp -d)

# The installed kernel (the running one is the host's in a container)
KVER=$(ls /lib/modules 2>/dev/null | sort -V | tail -n 1)
[ -n "$KVER" ] || { echo "plymouth-root: no kernel in /lib/modules: install one first" >&2; exit 1; }
export PF_PLYMOUTH_KERNEL=$KVER
if command -v dracut >/dev/null && command -v lsinitrd >/dev/null; then BUILDER=dracut LIST=lsinitrd
elif command -v mkinitcpio >/dev/null && command -v lsinitcpio >/dev/null; then BUILDER=mkinitcpio LIST=lsinitcpio
elif command -v update-initramfs >/dev/null && command -v lsinitramfs >/dev/null; then BUILDER=initramfs-tools LIST=lsinitramfs
else echo "plymouth-root: no initramfs builder" >&2; exit 1
fi
case $BUILDER in
  dracut) if compgen -G "/boot/initrd.img-*" >/dev/null || [ -e /etc/debian_version ]; then IMAGES=("/boot/initrd.img-$KVER"); else IMAGES=("/boot/initramfs-$KVER.img"); fi ;;
  initramfs-tools) IMAGES=("/boot/initrd.img-$KVER") ;;
  mkinitcpio)
    # shellcheck source=/dev/null # the system's presets
    mapfile -t IMAGES < <(for f in /etc/mkinitcpio.d/*.preset; do (. "$f"; for p in "${PRESETS[@]}"; do v=${p}_image; [ -z "${!v:-}" ] || echo "${!v}"; done); done) ;;
esac
# The images as the kernel package left them; built here where its hook did not run (containers)
for img in "${IMAGES[@]}"; do
  [ -f "$img" ] && continue
  case $BUILDER in
    dracut) dracut -q -f --no-hostonly "$img" "$KVER" ;;
    initramfs-tools) update-initramfs -c -k "$KVER" >/dev/null ;;
    mkinitcpio) mkinitcpio -P >/dev/null ;;
  esac
done
current_theme() {
  if command -v plymouth-set-default-theme >/dev/null; then plymouth-set-default-theme
  else update-alternatives --query default.plymouth 2>/dev/null | sed -n 's/^Value: //p' | xargs -r basename -s .plymouth
  fi
}
image_has() { local l; l=$("$LIST" "$1" 2>/dev/null) || return 2; grep -q "usr/share/plymouth/themes/$NAME/$NAME.script" <<<"$l"; }
echo "system: $(. /etc/os-release && echo "$PRETTY_NAME"), builder $BUILDER, kernel $KVER, images ${IMAGES[*]}"

# The theme: a minimal one with the installer's files, unless a build is given
THEME=${1:-}
if [ -z "$THEME" ]; then
  THEME=$WORK/theme
  mkdir -p "$THEME"
  printf '[Plymouth Theme]\nName=Plasma Fusion (test)\nDescription=stand-in\nModuleName=script\n\n[script]\nImageDir=/usr/share/plymouth/themes/%s\nScriptFile=/usr/share/plymouth/themes/%s/%s.script\n\n[script-env-vars]\n' \
    "$NAME" "$NAME" "$NAME" >"$THEME/$NAME.plymouth"
  printf 'Window.SetBackgroundTopColor(0.1, 0.1, 0.2);\nWindow.SetBackgroundBottomColor(0.1, 0.1, 0.2);\n' >"$THEME/$NAME.script"
  printf '\x89PNG\r\n\x1a\n' >"$THEME/background.png"
fi

# The state from before
before_theme=$(current_theme 2>/dev/null || true)
before_alt=$(update-alternatives --query default.plymouth 2>/dev/null | sed -n 's/^Status: //p;s/^Value: //p' | tr '\n' ' ' || true)
[ ! -f /etc/plymouth/plymouthd.conf ] || cp -a /etc/plymouth/plymouthd.conf "$WORK/plymouthd.conf.before"
before_hooks=''
[ "$BUILDER" != mkinitcpio ] || before_hooks=$(bash -c '. /etc/mkinitcpio.conf; echo "${HOOKS[*]}"')
echo "before: theme '${before_theme:-none}', alternative '${before_alt:-none}'"
printf 'BOOT_IMAGE=/vmlinuz root=/dev/vda1 ro quiet\n' >"$WORK/cmdline-plain"
printf 'BOOT_IMAGE=/vmlinuz root=/dev/vda1 ro quiet splash\n' >"$WORK/cmdline-splash"
set +e

# --- install and select
OUT=$(PF_PLYMOUTH_CMDLINE=$WORK/cmdline-plain bash "$INSTALL" --select --name Alex "$THEME" 2>&1); RC=$?
[ "$RC" = 0 ] && has "contains the $NAME theme and the script plugin" && ok "install --select ($BUILDER)" || bad "install --select" "$OUT"
[ "$(current_theme)" = "$NAME" ] && ok "  $NAME is the selected theme" || bad "  selected theme: $(current_theme)"
for img in "${IMAGES[@]}"; do
  l=$("$LIST" "$img" 2>/dev/null)
  grep -q "usr/share/plymouth/themes/$NAME/$NAME.script" <<<"$l" && grep -q "plymouth/script.so" <<<"$l" &&
    ok "  $img holds the theme and script.so" || bad "  $img without the theme"
  [ -f "$img.pre-$NAME" ] && ok "  $img.pre-$NAME kept" || bad "  no backup of $img"
done
has 'the kernel command line has no "splash"' && ok "  a command line without splash is named" || bad "  splash note" "$OUT"
if [ "$BUILDER" = mkinitcpio ]; then
  [ -f /etc/mkinitcpio.conf.d/90-plasma-fusion-plymouth.conf ] &&
    [[ " $(bash -c '. /etc/mkinitcpio.conf; for f in /etc/mkinitcpio.conf.d/*.conf; do . "$f"; done; echo "${HOOKS[*]}"') " == *" systemd plymouth "* || " $(bash -c '. /etc/mkinitcpio.conf; for f in /etc/mkinitcpio.conf.d/*.conf; do . "$f"; done; echo "${HOOKS[*]}"') " == *" udev plymouth "* ]] &&
    ok "  the drop-in puts the plymouth hook after systemd/udev" || bad "  mkinitcpio drop-in"
fi
cp -a "${IMAGES[0]}.pre-$NAME" "$WORK/backup-first"
OUT=$(PF_PLYMOUTH_CMDLINE=$WORK/cmdline-splash bash "$INSTALL" --select "$THEME" 2>&1); RC=$?
[ "$RC" = 0 ] && ! has 'has no "splash"' && cmp -s "${IMAGES[0]}.pre-$NAME" "$WORK/backup-first" &&
  ok "a second --select: no note with splash, the first backup kept" || bad "second --select" "$OUT"

# --- uninstall
OUT=$(bash "$UNINSTALL" --remove-plugin 2>&1); RC=$?
[ "$RC" = 0 ] && ok "uninstall" || bad "uninstall" "$OUT"
for img in "${IMAGES[@]}"; do
  image_has "$img"; r=$?
  [ "$r" = 1 ] && ok "  $img without the theme" || bad "  $img still holds it (or cannot be listed: $r)"
  [ ! -e "$img.pre-$NAME" ] && ok "  its backup removed" || bad "  backup left: $img.pre-$NAME"
done
now_theme=$(current_theme 2>/dev/null || true)
[ "$now_theme" = "$before_theme" ] && ok "  the theme from before: '${before_theme:-none}'" || bad "  theme now '$now_theme', before '$before_theme'"
now_alt=$(update-alternatives --query default.plymouth 2>/dev/null | sed -n 's/^Status: //p;s/^Value: //p' | tr '\n' ' ' || true)
[ "$now_alt" = "$before_alt" ] && ok "  the default.plymouth alternative as before" || bad "  alternative now '$now_alt', before '$before_alt'"
if [ -f "$WORK/plymouthd.conf.before" ]; then
  cmp -s /etc/plymouth/plymouthd.conf "$WORK/plymouthd.conf.before" && ok "  plymouthd.conf byte for byte" ||
    bad "  plymouthd.conf changed" "$(diff "$WORK/plymouthd.conf.before" /etc/plymouth/plymouthd.conf)"
fi
if [ "$BUILDER" = mkinitcpio ]; then
  [ ! -e /etc/mkinitcpio.conf.d/90-plasma-fusion-plymouth.conf ] &&
    [ "$(bash -c '. /etc/mkinitcpio.conf; for f in /etc/mkinitcpio.conf.d/*.conf; do [ ! -e "$f" ] || . "$f"; done; echo "${HOOKS[*]}"')" = "$before_hooks" ] &&
    ok "  the drop-in removed, HOOKS as before" || bad "  mkinitcpio hooks after uninstall"
fi
[ ! -e "/usr/share/plymouth/themes/$NAME" ] && [ ! -e /var/lib/plasma-fusion/plymouth ] && ok "  the files and the state removed" ||
  bad "  files or state left" "$(ls -la /usr/share/plymouth/themes /var/lib/plasma-fusion 2>&1)"
set -e

echo "plymouth-root ($BUILDER): $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
