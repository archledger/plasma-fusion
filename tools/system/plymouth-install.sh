#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Install the Plasma Fusion Plymouth theme (boot splash and disk unlock) system-wide. Run as
# root on the target machine, with a theme directory built by generators/plymouth/build.sh or
# the copy the plasma-fusion package ships.
#
#   plymouth-install.sh [--select] [--user LOGIN|--name TEXT|--name none|--name auto]
#                       [--layout LABEL|none] [--no-packages] [--dry-run] [THEME_DIR]
#
#   THEME_DIR        the built theme (plasma-fusion.plymouth, plasma-fusion.script, *.png and
#                    greeting/); default: /usr/share/plasma-fusion/plymouth/plasma-fusion from
#                    the package
#   --select         also make it the default theme and rebuild the initramfs of the running
#                    kernel (Arch: every preset's). The way depends on the system:
#                    plymouth-set-default-theme, or the default.plymouth alternative where that
#                    tool is missing (Ubuntu, KDE neon); dracut (Fedora, Debian, Ubuntu),
#                    mkinitcpio (Arch: the plymouth hook added by a drop-in in
#                    /etc/mkinitcpio.conf.d when missing) or initramfs-tools (KDE neon). A copy
#                    of each image it rebuilds is kept first as <image>.pre-plasma-fusion (only
#                    the first time, so it always holds the image from before Plasma Fusion);
#                    /etc/plymouth/plymouthd.conf and the previous theme are saved under
#                    /var/lib/plasma-fusion/plymouth/. Plymouth shows the theme only with
#                    "splash" (or "rhgb") on the kernel command line: the installer says when it
#                    is missing and how to add it, and leaves the boot loader as it is.
#   --user LOGIN     greet the owner of this account ("Welcome back, <first word of the full
#                    name, else the login name>"), e.g. when the machine has more than one
#                    account. Remembered in /var/lib/plasma-fusion/plymouth/greeting for later
#                    runs, which then pick up a changed name
#   --name TEXT      greet with TEXT instead (remembered the same way); "none": only "Welcome
#                    back"; "auto": forget a remembered choice and use the default
#                    Without --user/--name or a remembered choice: the machine's only human
#                    account (UID_MIN..UID_MAX of /etc/login.defs, a login shell from
#                    /etc/shells, not nobody or plasmalogin); with none or several, only
#                    "Welcome back". The greeting is drawn into the installed NNN-greeting.png
#                    (needs python3-pillow; without it the greeting stays "Welcome back"). After
#                    a name change run the installer again with --select.
#   --layout LABEL   keyboard layout label shown next to the unlock field (default: derived from
#                    /etc/vconsole.conf, e.g. "us" -> "EN" as Plasma shows it); "none" hides it
#   --no-packages    do not install Plymouth's script plugin (Fedora: plymouth-plugin-script with
#                    dnf; Arch, Debian, Ubuntu: plymouth with pacman or apt-get); fail if it is
#                    missing. --no-dnf is the same
#   --dry-run        print what would be done
#
# Without --select only the files are installed: /usr/share/plymouth/themes/plasma-fusion/.
# The splash in use does not change until the theme is selected and the initramfs rebuilt.
# Initramfs images of other installed kernels keep their old theme until they are rebuilt
# (dracut -f --regenerate-all, update-initramfs -u -k all); new kernels get the selected theme
# automatically. NixOS: the module's option (docs/parts/nixos.md).
#
# Undo: tools/system/plymouth-uninstall.sh (puts the previous theme back and rebuilds), or by
# hand: plymouth-set-default-theme -R bgrt (Fedora). See docs/parts/plymouth.md.
set -euo pipefail

NAME=plasma-fusion
THEMES=/usr/share/plymouth/themes
STATE=/var/lib/plasma-fusion/plymouth
SELECT=0
LAYOUT=auto
GREET=
DNF=1
DRY=0
SRC=

usage() { awk 'NR > 3 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit "${1:-0}"; }
while [ $# -gt 0 ]; do
  case $1 in
    --select) SELECT=1 ;;
    --layout) shift; LAYOUT=${1:?--layout needs a value} ;;
    --user) shift; GREET="user=${1:?--user needs a login name}" ;;
    --name)
      shift
      case ${1?--name needs a value} in
        none) GREET=none ;;
        auto) GREET=auto ;;
        *) GREET="name=$1" ;;
      esac ;;
    --no-packages|--no-dnf) DNF=0 ;;
    --dry-run) DRY=1 ;;
    -h|--help) usage ;;
    -*) echo "plymouth-install: unknown option $1" >&2; usage 2 ;;
    *) [ -z "$SRC" ] || usage 2; SRC=$1 ;;
  esac
  shift
done
# The system's initramfs builder and the tool that lists an image of it: dracut (Fedora; Debian and
# Ubuntu since they moved to it), mkinitcpio (Arch), initramfs-tools (KDE neon, older Debian and
# Ubuntu). NixOS builds its initramfs from the configuration: the module's plymouth option.
# mkinitcpio first where it has presets: Arch's configured generator, even with dracut installed too.
BUILDER=
if [ -e /etc/NIXOS ]; then :
elif command -v mkinitcpio >/dev/null && command -v lsinitcpio >/dev/null && compgen -G "/etc/mkinitcpio.d/*.preset" >/dev/null; then
  BUILDER=mkinitcpio LIST=lsinitcpio
elif command -v dracut >/dev/null && command -v lsinitrd >/dev/null; then BUILDER=dracut LIST=lsinitrd
elif command -v update-initramfs >/dev/null && command -v lsinitramfs >/dev/null; then BUILDER=initramfs-tools LIST=lsinitramfs
fi
if [ -z "$BUILDER" ]; then
  if [ -e /etc/NIXOS ]; then
    echo "plymouth-install: NixOS builds the initramfs from its configuration: programs.plasma-fusion.plymouth = true (docs/parts/nixos.md). Nothing was changed." >&2
  else
    echo "plymouth-install: no initramfs builder found (dracut, mkinitcpio or initramfs-tools)." >&2
    echo "  The theme itself is in /usr/share/plasma-fusion/plymouth/plasma-fusion for your distribution's" >&2
    echo "  Plymouth tools. Nothing was changed." >&2
  fi
  exit 3
fi
# The images --select rebuilds, worked out before anything changes: the running kernel's
# (PF_PLYMOUTH_KERNEL names another installed kernel: tests in containers, where the running kernel
# is the host's) where the builder makes one per kernel - an existing image only, since a new one
# under another name would be one the boot loader does not use (dracut on Arch names them after the
# package) - or every mkinitcpio preset's images and unified kernel images.
KVER=${PF_PLYMOUTH_KERNEL:-$(uname -r)}
IMAGES=()
if [ "$SELECT" = 1 ]; then
  case $BUILDER in
    dracut)
      for img in "/boot/initramfs-$KVER.img" "/boot/initrd.img-$KVER"; do
        if [ -f "$img" ]; then IMAGES=("$img"); break; fi
      done ;;
    initramfs-tools) [ ! -f "/boot/initrd.img-$KVER" ] || IMAGES=("/boot/initrd.img-$KVER") ;;
    mkinitcpio)
      # The presets are bash, read as mkinitcpio -P reads them
      mapfile -t IMAGES < <(for f in /etc/mkinitcpio.d/*.preset; do
        # shellcheck source=/dev/null # the system's presets
        ( . "$f"; for p in "${PRESETS[@]}"; do
            for k in image uki; do v=${p}_$k; [ -z "${!v:-}" ] || printf '%s\n' "${!v}"; done
          done )
      done) ;;
  esac
  if [ "${#IMAGES[@]}" = 0 ]; then
    echo "plymouth-install: no initramfs image of kernel $KVER that $BUILDER makes (/boot/initramfs-$KVER.img," >&2
    echo "  /boot/initrd.img-$KVER, or a mkinitcpio preset's): the boot loader's image is not known here. Nothing was changed." >&2
    exit 1
  fi
fi
# Arch: mkinitcpio puts Plymouth into an image only with its hook in HOOKS, which Arch's default
# lacks. A drop-in of ours in /etc/mkinitcpio.conf.d adds it (step 5), but a preset that names its
# own configuration (ALL_config, <preset>_config) is built with -c, which reads no drop-ins
# (mkinitcpio(8)): such a configuration must have the hook already. Decided before any change.
DROPIN=/etc/mkinitcpio.conf.d/90-plasma-fusion-plymouth.conf
NEED_DROPIN=0
if [ "$SELECT" = 1 ] && [ "$BUILDER" = mkinitcpio ]; then
  hooks_of() { # $1 a configuration file, or "" for mkinitcpio.conf with the drop-ins: " HOOKS "
    if [ -n "$1" ]; then
      bash -c '. "$1"; echo " ${HOOKS[*]} "' _ "$1"
    else
      bash -c '. /etc/mkinitcpio.conf; for f in /etc/mkinitcpio.conf.d/*.conf; do [ ! -e "$f" ] || . "$f"; done; echo " ${HOOKS[*]} "'
    fi
  }
  # Each preset's configuration: its own, ALL_config, or none (mkinitcpio.conf and the drop-ins)
  mapfile -t configs < <(for f in /etc/mkinitcpio.d/*.preset; do
    # shellcheck source=/dev/null # the system's presets
    ( . "$f"; for p in "${PRESETS[@]}"; do v=${p}_config; printf '%s\n' "${!v:-${ALL_config:-}}"; done )
  done | sort -u)
  for cfg in "${configs[@]}"; do
    hooks=$(hooks_of "$cfg")
    [[ $hooks == *" plymouth "* ]] && continue
    if [ -n "$cfg" ]; then
      echo "plymouth-install: a mkinitcpio preset is built with its own configuration, $cfg, which reads no" >&2
      echo "  drop-ins and has no plymouth hook: add plymouth to its HOOKS after systemd (or udev), before the" >&2
      echo "  encryption hooks, and run this again. Nothing was changed." >&2
      exit 1
    fi
    [[ $hooks == *" systemd "* || $hooks == *" udev "* ]] || {
      echo "plymouth-install: HOOKS has neither systemd nor udev; add the plymouth hook by hand (after it, before encrypt). Nothing was changed." >&2
      exit 1; }
    NEED_DROPIN=1
  done
fi
# The package that brings Plymouth's script plugin: Fedora's plymouth-plugin-script, elsewhere
# Plymouth itself (Arch, Debian and Ubuntu ship script.so in plymouth).
if command -v dnf >/dev/null; then PKG=dnf PLUGIN_PKG=plymouth-plugin-script
elif command -v pacman >/dev/null; then PKG=pacman PLUGIN_PKG=plymouth
elif command -v apt-get >/dev/null; then PKG=apt PLUGIN_PKG=plymouth
else PKG='' PLUGIN_PKG=plymouth
fi
PACKAGED=/usr/share/plasma-fusion/plymouth/$NAME
[ -n "$SRC" ] || { [ -d "$PACKAGED" ] && SRC=$PACKAGED; } || usage 2
[ -f "$SRC/$NAME.plymouth" ] && [ -f "$SRC/$NAME.script" ] || {
  echo "plymouth-install: $SRC is not a built $NAME theme" >&2; exit 1; }
if [ "$DRY" = 0 ] && [ "$(id -u)" != 0 ]; then
  echo "plymouth-install: run as root (sudo)" >&2; exit 1
fi

run() {
  echo "+ $*"
  [ "$DRY" = 1 ] || "$@"
}

# 1. The greeting: whom to greet (checked before anything is changed). An explicit
#    --user/--name is remembered for later runs.
GREET_RECORD=$STATE/greeting
login_defs() { sed -n "s/^[[:space:]]*$1[[:space:]]\{1,\}\([0-9]\{1,\}\).*/\1/p" /etc/login.defs 2>/dev/null | tail -1; }
# Login names of the human accounts: UID_MIN..UID_MAX, a login shell listed in /etc/shells.
human_accounts() {
  local min max user uid shell
  min=$(login_defs UID_MIN); max=$(login_defs UID_MAX)
  getent passwd | while IFS=: read -r user _ uid _ _ _ shell; do
    [ "$uid" -ge "${min:-1000}" ] && [ "$uid" -le "${max:-60000}" ] || continue
    case $user in nobody|nfsnobody|plasmalogin) continue ;; esac
    case $shell in ''|*/nologin|*/false) continue ;; esac
    grep -qxF -- "$shell" /etc/shells 2>/dev/null || continue
    printf '%s\n' "$user"
  done
}
# Candidates for one account: the first word of its full name (GECOS), then the login name.
account_names() {
  local entry full
  entry=$(getent passwd "$1") || return 1
  full=$(cut -d: -f5 <<< "$entry"); full=${full%%,*}
  read -r full _ <<< "$full" || true
  [ -n "$full" ] && printf '%s\n' "$full"
  printf '%s\n' "$1"
}
case $GREET in
  auto) choice=auto ;;
  '') choice=$(head -1 "$GREET_RECORD" 2>/dev/null || true); choice=${choice:-auto} ;;
  *) choice=$GREET ;;
esac
names=()
case $choice in
  user=*)
    login=${choice#user=}
    mapfile -t names < <(account_names "$login")
    [ "${#names[@]}" -gt 0 ] || { echo "plymouth-install: no account named '$login'" >&2; exit 1; }
    why="account $login" ;;
  name=*) names=("${choice#name=}"); why="given name" ;;
  none) why="no name (--name none)" ;;
  *)
    mapfile -t humans < <(human_accounts)
    if [ "${#humans[@]}" -eq 1 ]; then
      mapfile -t names < <(account_names "${humans[0]}")
      why="the only human account, ${humans[0]}"
    else
      why="${#humans[@]} human accounts (${humans[*]:-none}); --user LOGIN picks one"
    fi ;;
esac
echo "greeting: ${names[0]:-(no name)} ($why)"

# 2. Plymouth's script plugin (Fedora ships it separately; Arch installs no Plymouth by default).
plugin_dir() { plymouth --get-splash-plugin-path 2>/dev/null; }
if ! command -v plymouth >/dev/null || [ ! -f "$(plugin_dir)script.so" ]; then
  if [ "$DNF" = 1 ] && [ -n "$PKG" ]; then
    # A package transaction now changes the package database that a prepared offline update
    # (Discover, dnf offline) was computed against. Refuse when one is scheduled for the next
    # boot; mention it when one is only prepared.
    if [ -e /system-update ]; then
      echo "plymouth-install: an offline update is scheduled for the next boot (/system-update)." >&2
      echo "  Install it first (reboot), or install $PLUGIN_PKG yourself and re-run with --no-packages." >&2
      exit 1
    fi
    if [ -f /usr/lib/sysimage/libdnf5/offline/offline-transaction-state.toml ]; then
      echo "note: a prepared offline update exists; it has to be prepared again after this dnf transaction"
    fi
    case $PKG in
      dnf) run dnf install -y "$PLUGIN_PKG" ;;
      pacman) run pacman -S --needed --noconfirm "$PLUGIN_PKG" ;;
      # (waiting for dpkg's lock as apt does, up to 10 minutes: scripts/install.sh, APT_LOCK)
      apt) run env DEBIAN_FRONTEND=noninteractive apt-get install -y "$PLUGIN_PKG" -o DPkg::Lock::Timeout=600 ;;
    esac
    [ "$DRY" = 1 ] || { mkdir -p "$STATE"; echo "$PLUGIN_PKG" > "$STATE/installed-packages"; }
    [ "$DRY" = 1 ] || [ -f "$(plugin_dir)script.so" ] ||
      { echo "plymouth-install: Plymouth's script plugin is still missing after installing $PLUGIN_PKG" >&2; exit 1; }
  else
    echo "plymouth-install: Plymouth's script plugin (script.so) is missing: install $PLUGIN_PKG" >&2
    exit 1
  fi
fi

# 3. Keyboard layout label: the first XKB layout (or console keymap) in /etc/vconsole.conf (or
#    Debian's and Ubuntu's /etc/default/keyboard), shown the way Plasma's layout indicator names
#    it (the short description from /usr/share/X11/xkb/rules/evdev.xml, upper case: us -> EN,
#    de -> DE).
layout_label() {
  local conf layout='' short=''
  for conf in /etc/vconsole.conf /etc/default/keyboard; do
    [ -r "$conf" ] || continue
    layout=$(sed -n 's/^XKBLAYOUT="\{0,1\}\([^",]*\).*/\1/p' "$conf" | head -1)
    if [ -z "$layout" ]; then
      layout=$(sed -n 's/^KEYMAP="\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$conf" | head -1)
      layout=${layout%%-*}
    fi
    [ -z "$layout" ] || break
  done
  [ -n "$layout" ] || return 0
  if [ -r /usr/share/X11/xkb/rules/evdev.xml ] && command -v python3 >/dev/null; then
    # -I: no module from the current directory or the environment (this runs as root).
    short=$(python3 -I - "$layout" <<'EOF' 2>/dev/null || true
import sys
import xml.etree.ElementTree as ET
want = sys.argv[1]
for layout in ET.parse("/usr/share/X11/xkb/rules/evdev.xml").getroot().iter("layout"):
    ci = layout.find("configItem")
    if ci is not None and ci.findtext("name") == want:
        print(ci.findtext("shortDescription") or want)
        break
EOF
)
  fi
  [ -n "$short" ] || short=$layout
  printf '%s' "$short" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9+_()-' | cut -c1-6
}
case $LAYOUT in
  auto) LABEL=$(layout_label) ;;
  none) LABEL= ;;
  *) LABEL=$(printf '%s' "$LAYOUT" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9+_()-' | cut -c1-6) ;;
esac
echo "keyboard layout label: ${LABEL:-(none)}"

# How this system names its theme: plymouth-set-default-theme (plymouthd.conf), or, where that tool
# is missing (Ubuntu, KDE neon), the default.plymouth alternative its Plymouth and initramfs read.
if command -v plymouth-set-default-theme >/dev/null; then SELECTOR=set-default-theme
else SELECTOR=alternatives
fi
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

# 4. Files: a fresh copy next to the old one, then swapped in. New files get the default
#    SELinux label of the target directory (restorecon makes sure).
DEST=$THEMES/$NAME
TMP=$THEMES/.$NAME.new
run rm -rf "$TMP"
run install -d -m 0755 "$TMP"
for f in "$SRC"/*; do
  case $f in *.png|*.script|*.plymouth) run install -m 0644 "$f" "$TMP/" ;; esac
done
if [ -n "$LABEL" ]; then
  echo "+ add PFKeyboardLayout=$LABEL to $NAME.plymouth [script-env-vars]"
  [ "$DRY" = 1 ] || sed -i "/^\[script-env-vars\]/a PFKeyboardLayout=$LABEL" "$TMP/$NAME.plymouth"
fi
# The greeting images: drawn again over the theme's generic "Welcome back" (an isolated python3:
# no user site-packages or PYTHON* variables).
if [ "${#names[@]}" -gt 0 ]; then
  if [ ! -f "$SRC/greeting/greeting.py" ]; then
    echo "note: $SRC has no greeting/ (an older build): the greeting has no name"
  elif ! python3 -I -c 'import PIL.ImageFont' 2>/dev/null; then
    echo "note: python3-pillow is not installed: the greeting has no name (dnf install python3-pillow, then run this again)"
  else
    args=()
    for n in "${names[@]}"; do args+=("--name=$n"); done
    echo "+ python3 -I -B $SRC/greeting/greeting.py $SRC/greeting/layout.json $TMP ${args[*]}"
    if [ "$DRY" = 0 ]; then
      if shown=$(python3 -I -B "$SRC/greeting/greeting.py" "$SRC/greeting/layout.json" "$TMP" "${args[@]}"); then
        echo "greeting drawn: $shown"
      else
        echo "warning: the greeting could not be drawn; it stays \"Welcome back\"" >&2
        for f in "$SRC"/*-greeting.png; do install -m 0644 "$f" "$TMP/"; done
      fi
    fi
  fi
fi
case $GREET in
  '') ;;
  auto)
    if [ -f "$GREET_RECORD" ]; then run rm -f "$GREET_RECORD"; fi ;;
  *)
    echo "+ record '$GREET' in $GREET_RECORD"
    [ "$DRY" = 1 ] || { mkdir -p "$STATE"; printf '%s\n' "$GREET" > "$GREET_RECORD"; } ;;
esac
if [ -d "$DEST" ]; then
  run rm -rf "$THEMES/.$NAME.old"
  run mv "$DEST" "$THEMES/.$NAME.old"
fi
run mv "$TMP" "$DEST"
run rm -rf "$THEMES/.$NAME.old"
command -v restorecon >/dev/null && run restorecon -R "$DEST"
if [ "$DRY" = 1 ]; then
  echo "(dry run: would install $DEST from $SRC)"
else
  echo "installed $DEST ($(find "$DEST" -maxdepth 1 -type f | wc -l) files)"
fi

if [ "$SELECT" = 0 ]; then
  if [ "$(current_theme)" = "$NAME" ]; then
    # Shutdown and reboot use these files; the boot splash uses the copy in the initramfs.
    echo "note: $NAME is the selected theme; the initramfs keeps its own copy until it is rebuilt (re-run with --select)"
  else
    echo "not selected (use --select to make it the boot splash)"
  fi
  exit 0
fi

# 5. Select it and rebuild the images listed above, after saving the previous state.
run mkdir -p "$STATE"
current=$(current_theme)
if [ ! -f "$STATE/previous-theme" ] && [ "$current" != "$NAME" ]; then
  echo "+ record previous theme '${current:-none}' in $STATE/previous-theme"
  [ "$DRY" = 1 ] || echo "$current" > "$STATE/previous-theme"
fi
if [ "$SELECTOR" = alternatives ] && [ ! -f "$STATE/previous-alternative" ] && [ "$current" != "$NAME" ]; then
  # Status auto or manual, and the path: the undo puts a manual choice back
  echo "+ record the $ALT alternative ($(alternative Status) ${current:-none}) in $STATE/previous-alternative"
  [ "$DRY" = 1 ] || printf '%s %s\n' "$(alternative Status)" "$(alternative Value)" > "$STATE/previous-alternative"
fi
if [ ! -f "$STATE/plymouthd.conf.orig" ] && [ -f /etc/plymouth/plymouthd.conf ]; then
  run cp -a /etc/plymouth/plymouthd.conf "$STATE/plymouthd.conf.orig"
fi
for img in "${IMAGES[@]}"; do
  if [ ! -f "$img.pre-$NAME" ] && [ -f "$img" ]; then
    # Private, as an image can hold key files; created 0600 rather than chmod'ed (an EFI system
    # partition's FAT has no modes to set)
    echo "+ copy $img to $img.pre-$NAME"
    [ "$DRY" = 1 ] || ( umask 077 && cp -- "$img" "$img.pre-$NAME" )
  fi
done
# Arch: the plymouth hook through a drop-in of ours (read after mkinitcpio.conf, bash), after systemd
# or udev, before the encryption hooks, so the passphrase prompt is the theme's; removed by
# plymouth-uninstall.sh. Whether it is needed was decided above.
if [ "$NEED_DROPIN" = 1 ]; then
  echo "+ write $DROPIN (the plymouth hook after systemd or udev)"
  if [ "$DRY" = 0 ]; then
    install -d -m 0755 /etc/mkinitcpio.conf.d
    cat >"$DROPIN" <<'EOF'
# Plasma Fusion's boot splash (plymouth-install.sh): the plymouth hook after systemd or udev, so
# before the encryption hooks. plymouth-uninstall.sh removes this file.
read -r -a _pf_hooks <<<"${HOOKS[*]}"
HOOKS=()
for _pf_h in "${_pf_hooks[@]}"; do
  HOOKS+=("$_pf_h")
  case $_pf_h in systemd|udev) HOOKS+=(plymouth) ;; esac
done
unset _pf_hooks _pf_h
EOF
    echo "$DROPIN" > "$STATE/mkinitcpio-dropin"
  fi
fi
if [ "$SELECTOR" = set-default-theme ]; then
  run plymouth-set-default-theme "$NAME"
else
  run update-alternatives --install "$THEMES/$ALT" "$ALT" "$DEST/$NAME.plymouth" 100
  run update-alternatives --set "$ALT" "$DEST/$NAME.plymouth"
fi
case $BUILDER in
  dracut) run nice -n 10 dracut -f "${IMAGES[0]}" "$KVER" ;;
  initramfs-tools) run nice -n 10 update-initramfs -u -k "$KVER" ;;
  mkinitcpio) run nice -n 10 mkinitcpio -P ;;
esac
if [ "$DRY" = 0 ]; then
  for img in "${IMAGES[@]}"; do
    # (Read the listing first: "lsinitrd | grep -q" fails under pipefail when grep exits early.)
    listing=$("$LIST" "$img")
    if grep -q "usr/share/plymouth/themes/$NAME/$NAME.script" <<< "$listing" &&
       grep -q "plymouth/script.so" <<< "$listing"; then
      echo "initramfs $img contains the $NAME theme and the script plugin"
    else
      echo "plymouth-install: $img does not contain the theme; roll back with plymouth-uninstall.sh" >&2
      exit 1
    fi
  done
fi
echo "selected; previous initramfs kept as ${IMAGES[*]/%/.pre-$NAME}"
# Plymouth shows a graphical theme only with one of these on the kernel command line (Plymouth's
# main.c, plymouth_should_show_default_splash); without it, its text screen.
CMDLINE=${PF_PLYMOUTH_CMDLINE:-/proc/cmdline}
if ! tr ' ' '\n' <"$CMDLINE" 2>/dev/null | grep -qxE 'splash|rhgb|splash=silent'; then
  echo "note: the kernel command line has no \"splash\" (or \"rhgb\"), so Plymouth shows its text screen, not this theme."
  echo "  Add splash to the boot loader's kernel options: with GRUB in GRUB_CMDLINE_LINUX_DEFAULT of"
  echo "  /etc/default/grub, then update-grub (Debian, Ubuntu) or grub-mkconfig -o /boot/grub/grub.cfg"
  echo "  (Arch); on Fedora grubby --update-kernel=ALL --args=rhgb; with systemd-boot on the options"
  echo "  line of /boot/loader/entries/*.conf. This installer leaves the boot loader as it is."
fi
