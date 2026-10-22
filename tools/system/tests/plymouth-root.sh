#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# tools/system/plymouth-install.sh --select and plymouth-uninstall.sh as root on a system's own
# initramfs builder and Plymouth, with an installed kernel: the theme selected and in the rebuilt
# image with Plymouth's script plugin (and, where that plugin has a console viewer, the text plugin
# the builder copies), the state from before put back by the uninstall (the theme
# or the default.plymouth alternative, plymouthd.conf byte for byte, Arch's mkinitcpio hooks), the
# image without it, the backups and the files gone. It changes /boot, /etc and /usr/share/plymouth,
# so it runs only as root in a throw-away container (PF_DISPOSABLE_SYSTEM=1 allows another machine
# meant to be thrown away), with a kernel and the builder installed, e.g.:
#   podman run --rm -v "$PWD:/src:ro,z" registry.fedoraproject.org/fedora:44 bash -c \
#     'dnf -y -q install kernel-core dracut plymouth && cp -a /src /work && /work/tools/system/tests/plymouth-root.sh'
# The theme is a minimal stand-in (the installer's paths, not the drawing), or THEME_DIR, a build
# of generators/plymouth/build.sh. PF_PLYMOUTH_UKI=1 (Arch, with systemd-ukify): the preset also
# builds a unified kernel image. PF_PLYMOUTH_PRESET_CONFIG=1 (Arch): the preset names its own
# configuration (ALL_config), which reads no drop-ins. PF_PLYMOUTH_EXPECT=refused: a system the
# installer cannot handle (Arch with dracut instead of mkinitcpio, or such a preset without the hook)
# - it must stop with nothing changed; PF_PLYMOUTH_REFUSAL is the reason it must give.
# PF_PLYMOUTH_DEPENDENT: a package that needs one the installer installs (a theme package),
# installed after a last --select; uninstall --remove-plugin must keep the one it needs. Test
# tooling only.
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
if command -v mkinitcpio >/dev/null && command -v lsinitcpio >/dev/null && compgen -G "/etc/mkinitcpio.d/*.preset" >/dev/null; then
  BUILDER=mkinitcpio LIST=lsinitcpio
elif command -v dracut >/dev/null && command -v lsinitrd >/dev/null; then BUILDER=dracut LIST=lsinitrd
elif command -v update-initramfs >/dev/null && command -v lsinitramfs >/dev/null; then BUILDER=initramfs-tools LIST=lsinitramfs
else echo "plymouth-root: no initramfs builder" >&2; exit 1
fi
if [ "${PF_PLYMOUTH_PRESET_CONFIG:-}" = 1 ]; then
  sed -i 's|^#ALL_config=|ALL_config=|' /etc/mkinitcpio.d/*.preset
fi
if [ "${PF_PLYMOUTH_UKI:-}" = 1 ]; then
  # The preset builds an image and a unified kernel image (mkinitcpio(8): <preset>_uki)
  mkdir -p /efi/EFI/Linux /etc/kernel
  echo "root=/dev/vda1 rw" >/etc/kernel/cmdline
  sed -i 's|^#default_uki=|default_uki=|' /etc/mkinitcpio.d/*.preset
fi
case $BUILDER in
  dracut) if [ -e /etc/debian_version ]; then IMAGES=("/boot/initrd.img-$KVER"); else IMAGES=("/boot/initramfs-$KVER.img"); fi ;;
  initramfs-tools) IMAGES=("/boot/initrd.img-$KVER") ;;
  mkinitcpio)
    # shellcheck source=/dev/null # the system's presets
    mapfile -t IMAGES < <(for f in /etc/mkinitcpio.d/*.preset; do (. "$f"; for p in "${PRESETS[@]}"; do for k in image uki; do v=${p}_$k; [ -z "${!v:-}" ] || echo "${!v}"; done; done); done) ;;
esac
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

if [ "${PF_PLYMOUTH_EXPECT:-}" = refused ]; then
  # No image at the names the installer knows (or another reason given): it must stop before
  # changing anything
  unknown="the boot loader's image is not known"
  RC=0
  OUT=$(bash "$INSTALL" --select "$THEME" 2>&1) || RC=$?
  reason=${PF_PLYMOUTH_REFUSAL:-}
  [ -n "$reason" ] || reason="no initramfs image of kernel $KVER"
  [ "$RC" = 1 ] && has "$reason" && has "Nothing was changed." &&
    ok "--select refused: ${PF_PLYMOUTH_REFUSAL:-$unknown}" || bad "refusal" "$OUT"
  [ ! -e "/usr/share/plymouth/themes/$NAME" ] && [ ! -e /var/lib/plasma-fusion ] && ! compgen -G "/boot/*.pre-$NAME" >/dev/null &&
    [ ! -e /etc/mkinitcpio.conf.d/90-plasma-fusion-plymouth.conf ] && { ! command -v plymouth-set-default-theme >/dev/null ||
      [ "$(plymouth-set-default-theme)" != "$NAME" ]; } &&
    ok "  nothing was changed" || bad "  changes left" "$(ls -la /usr/share/plymouth/themes /var/lib/plasma-fusion /boot 2>&1)"
  echo "plymouth-root ($BUILDER, refused): $PASS passed, $FAIL failed"
  [ "$FAIL" = 0 ]
  exit
fi
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

installed() { # $1 a package
  rpm -q "$1" >/dev/null 2>&1 || pacman -Q "$1" >/dev/null 2>&1 ||
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}
package_list() {
  if command -v dnf >/dev/null; then rpm -qa --qf '%{NAME}\n'
  elif command -v pacman >/dev/null; then pacman -Qq
  else dpkg-query -W -f='${Package} ${Status}\n' | awk '$2 == "install" && $3 == "ok" && $4 == "installed" {print $1}'
  fi | sort -u
}

# --- install and select
OUT=$(PF_PLYMOUTH_CMDLINE=$WORK/cmdline-plain bash "$INSTALL" --select --name Alex "$THEME" 2>&1); RC=$?
[ "$RC" = 0 ] && has "contains the $NAME theme and the script plugin" && ok "install --select ($BUILDER)" || bad "install --select" "$OUT"
[ "$(current_theme)" = "$NAME" ] && ok "  $NAME is the selected theme" || bad "  selected theme: $(current_theme)"
# A script plugin with a console viewer (Plymouth after 24.004.60) needs a text plugin in the image,
# or plymouthd crashes as the splash starts: the one the builder copies
label=''
if grep -q ply_console_viewer "$(plymouth --get-splash-plugin-path)script.so" 2>/dev/null; then
  label='label-freetype.so'
  [ "$BUILDER" != initramfs-tools ] || label='label-pango.so'
fi
for img in "${IMAGES[@]}"; do
  l=$("$LIST" "$img" 2>/dev/null)
  grep -q "usr/share/plymouth/themes/$NAME/$NAME.script" <<<"$l" && grep -q "plymouth/script.so" <<<"$l" &&
    ok "  $img holds the theme and script.so" || bad "  $img without the theme"
  [ -z "$label" ] || { grep -q "plymouth/$label" <<<"$l" &&
    ok "  $img holds $label (the script plugin's console viewer needs a text plugin)" || bad "  $img without $label"; }
  [ -f "$img.pre-$NAME" ] && ok "  $img.pre-$NAME kept" || bad "  no backup of $img"
done
mapfile -t recorded < <(cat /var/lib/plasma-fusion/plymouth/installed-packages 2>/dev/null)
echo "installed by the installer: ${recorded[*]:-nothing}"
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
package_list >"$WORK/packages-before"
# A user's apt configuration may enable automatic removal. Only recorded packages are ours to
# remove, not their dependencies or other unused packages; test that setting rather than assuming
# the distribution's default. DNF enables dependency cleanup by default already.
echo 'APT::Get::AutomaticRemove "true";' >"$WORK/apt.conf"
OUT=$(APT_CONFIG="$WORK/apt.conf" bash "$UNINSTALL" --remove-plugin 2>&1); RC=$?
[ "$RC" = 0 ] && ok "uninstall" || bad "uninstall" "$OUT"
package_list >"$WORK/packages-after"
missing=$(comm -23 "$WORK/packages-before" "$WORK/packages-after")
for p in "${recorded[@]}"; do missing=$(grep -vxF "$p" <<<"$missing"); done
[ -z "$missing" ] && ok "  no unrecorded package removed" || bad "  unrecorded packages removed" "$missing"
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
for p in "${recorded[@]}"; do
  ! installed "$p" && ok "  $p, which the installer installed, removed (--remove-plugin)" || bad "  $p still installed"
done

# --- Arch with the plymouth hook already in HOOKS (no drop-in of ours) and two images: another
# theme selected by hand and only the first image rebuilt; the uninstall must still rebuild, since
# the second image carries the theme
if [ "$BUILDER" = mkinitcpio ] && [ "${#IMAGES[@]}" -gt 1 ]; then
  cp -a /etc/mkinitcpio.conf "$WORK/mkinitcpio.conf.before"
  sed -i 's/^HOOKS=(\(.*\)\bsystemd\b/HOOKS=(\1systemd plymouth/' /etc/mkinitcpio.conf
  OUT=$(PF_PLYMOUTH_CMDLINE=$WORK/cmdline-splash bash "$INSTALL" --select "$THEME" 2>&1); RC=$?
  [ "$RC" = 0 ] && [ ! -e /etc/mkinitcpio.conf.d/90-plasma-fusion-plymouth.conf ] || bad "install with the hook already there" "$OUT"
  plymouth-set-default-theme text
  mkinitcpio -k "$KVER" -g "${IMAGES[0]}" >/dev/null 2>&1
  OUT=$(bash "$UNINSTALL" 2>&1); RC=$?
  clean=1
  for img in "${IMAGES[@]}"; do image_has "$img" && clean=0; done
  [ "$RC" = 0 ] && [ "$clean" = 1 ] && ok "deselected by hand with one image rebuilt: the uninstall rebuilds the others" ||
    bad "image left with the theme" "$OUT"
  cp -a "$WORK/mkinitcpio.conf.before" /etc/mkinitcpio.conf
fi

# --- Ubuntu, neon: another theme chosen by hand after the install; the uninstall removes ours from
# the alternative and keeps that choice
other=$(update-alternatives --query default.plymouth 2>/dev/null | sed -n 's/^Alternative: //p' | grep -v "/$NAME/" | head -n 1 || true)
if ! command -v plymouth-set-default-theme >/dev/null && [ -n "$other" ]; then
  OUT=$(PF_PLYMOUTH_CMDLINE=$WORK/cmdline-splash bash "$INSTALL" --select "$THEME" 2>&1); RC=$?
  [ "$RC" = 0 ] || bad "install for the chosen-since case" "$OUT"
  update-alternatives --set default.plymouth "$other" >/dev/null
  OUT=$(bash "$UNINSTALL" 2>&1); RC=$?
  # The database itself, before update-alternatives reads it again (it drops a missing file's entry
  # then, with a warning, which would hide a stale one)
  [ "$RC" = 0 ] && ! grep -q "/$NAME/" /var/lib/dpkg/alternatives/default.plymouth &&
    [ "$(update-alternatives --query default.plymouth | sed -n 's/^Value: //p')" = "$other" ] &&
    ok "a theme chosen since: the uninstall removes ours from the alternative, the choice stays" ||
    bad "alternative chosen since" "$OUT
$(update-alternatives --query default.plymouth)"
  update-alternatives --auto default.plymouth >/dev/null
fi

# --- a package installed since needs one the installer installed (PF_PLYMOUTH_DEPENDENT, a theme
# package): --remove-plugin keeps that one, on record and with a note, and removes nothing else
if [ -n "${PF_PLYMOUTH_DEPENDENT:-}" ]; then
  OUT=$(PF_PLYMOUTH_CMDLINE=$WORK/cmdline-splash bash "$INSTALL" --select "$THEME" 2>&1); RC=$?
  [ "$RC" = 0 ] || bad "install for the package installed since" "$OUT"
  mapfile -t recorded < <(cat /var/lib/plasma-fusion/plymouth/installed-packages 2>/dev/null)
  if command -v dnf >/dev/null; then dnf -y -q install "$PF_PLYMOUTH_DEPENDENT"
  elif command -v pacman >/dev/null; then pacman -S --noconfirm --needed "$PF_PLYMOUTH_DEPENDENT"
  else DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$PF_PLYMOUTH_DEPENDENT"
  fi >/dev/null 2>&1 || bad "could not install $PF_PLYMOUTH_DEPENDENT"
  OUT=$(bash "$UNINSTALL" --remove-plugin 2>&1); RC=$?
  [ "$RC" = 0 ] && installed "$PF_PLYMOUTH_DEPENDENT" &&
    ok "$PF_PLYMOUTH_DEPENDENT installed since: uninstall --remove-plugin, and it stays" ||
    bad "uninstall with $PF_PLYMOUTH_DEPENDENT installed since" "$OUT"
  mapfile -t kept < <(cat /var/lib/plasma-fusion/plymouth/installed-packages 2>/dev/null)
  [ "${#kept[@]}" -gt 0 ] && ok "  kept on record: ${kept[*]}" || bad "  nothing kept on record" "$OUT"
  for p in "${recorded[@]}"; do
    if [[ " ${kept[*]} " == *" $p "* ]]; then
      installed "$p" && has "note: $p stays" && ok "  $p stays, with a note" || bad "  $p on record, but not installed or no note" "$OUT"
    else
      ! installed "$p" && ok "  $p, which nothing else needs, removed" || bad "  $p still installed"
    fi
  done
  [ ! -e "/usr/share/plymouth/themes/$NAME" ] && [ "$(ls -A /var/lib/plasma-fusion/plymouth)" = installed-packages ] &&
    ok "  the files and the state removed, but for the record" ||
    bad "  files or state left" "$(ls -la /usr/share/plymouth/themes /var/lib/plasma-fusion/plymouth 2>&1)"
fi
set -e

echo "plymouth-root ($BUILDER): $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
