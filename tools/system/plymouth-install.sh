#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Install the Plasma Fusion Plymouth theme (boot splash and disk unlock) system-wide. Run as
# root on the target machine, with a theme directory built by generators/plymouth/build.sh or
# the copy the plasma-fusion package ships.
#
#   plymouth-install.sh [--select] [--user LOGIN|--name TEXT|--name none|--name auto]
#                       [--layout LABEL|none] [--no-dnf] [--dry-run] [THEME_DIR]
#
#   THEME_DIR        the built theme (plasma-fusion.plymouth, plasma-fusion.script, *.png and
#                    greeting/); default: /usr/share/plasma-fusion/plymouth/plasma-fusion from
#                    the package
#   --select         also make it the default theme and rebuild the initramfs of the running
#                    kernel (plymouth-set-default-theme -R plasma-fusion). A copy of the current
#                    initramfs is kept first as /boot/initramfs-<kernel>.img.pre-plasma-fusion
#                    (only the first time, so it always holds the image from before Plasma
#                    Fusion); /etc/plymouth/plymouthd.conf and the previous theme name are saved
#                    under /var/lib/plasma-fusion/plymouth/.
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
#   --no-dnf         do not install plymouth-plugin-script (fail if it is missing)
#   --dry-run        print what would be done
#
# Without --select only the files are installed: /usr/share/plymouth/themes/plasma-fusion/.
# The splash in use does not change until the theme is selected and the initramfs rebuilt.
# Initramfs images of other installed kernels keep their old theme until they are rebuilt
# (dracut -f --regenerate-all); new kernels get the selected theme automatically.
#
# Undo: tools/system/plymouth-uninstall.sh (puts the previous theme back and rebuilds), or by
# hand: plymouth-set-default-theme -R bgrt. See docs/parts/plymouth.md.
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
    --no-dnf) DNF=0 ;;
    --dry-run) DRY=1 ;;
    -h|--help) usage ;;
    -*) echo "plymouth-install: unknown option $1" >&2; usage 2 ;;
    *) [ -z "$SRC" ] || usage 2; SRC=$1 ;;
  esac
  shift
done
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

# 2. The script plugin (Fedora ships it separately).
PLUGIN_DIR=$(plymouth --get-splash-plugin-path 2>/dev/null || echo /usr/lib64/plymouth/)
if [ ! -f "$PLUGIN_DIR/script.so" ]; then
  if [ "$DNF" = 1 ]; then
    # A package transaction now changes the package database that a prepared offline update
    # (Discover, dnf offline) was computed against. Refuse when one is scheduled for the next
    # boot; mention it when one is only prepared.
    if [ -e /system-update ]; then
      echo "plymouth-install: an offline update is scheduled for the next boot (/system-update)." >&2
      echo "  Install it first (reboot), or install plymouth-plugin-script yourself and re-run with --no-dnf." >&2
      exit 1
    fi
    if [ -f /usr/lib/sysimage/libdnf5/offline/offline-transaction-state.toml ]; then
      echo "note: a prepared offline update exists; it has to be prepared again after this dnf transaction"
    fi
    run dnf install -y plymouth-plugin-script
    [ "$DRY" = 1 ] || { mkdir -p "$STATE"; echo plymouth-plugin-script > "$STATE/installed-packages"; }
  else
    echo "plymouth-install: $PLUGIN_DIR/script.so is missing (dnf install plymouth-plugin-script)" >&2
    exit 1
  fi
fi

# 3. Keyboard layout label: the first XKB layout (or console keymap) in /etc/vconsole.conf,
#    shown the way Plasma's layout indicator names it (the short description from
#    /usr/share/X11/xkb/rules/evdev.xml, upper case: us -> EN, de -> DE).
layout_label() {
  local conf=/etc/vconsole.conf layout='' short=''
  [ -r "$conf" ] || return 0
  layout=$(sed -n 's/^XKBLAYOUT="\{0,1\}\([^",]*\).*/\1/p' "$conf" | head -1)
  if [ -z "$layout" ]; then
    layout=$(sed -n 's/^KEYMAP="\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' "$conf" | head -1)
    layout=${layout%%-*}
  fi
  [ -n "$layout" ] || return 0
  if [ -r /usr/share/X11/xkb/rules/evdev.xml ] && command -v python3 >/dev/null; then
    short=$(python3 - "$layout" <<'EOF' 2>/dev/null || true
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
  if [ "$(plymouth-set-default-theme)" = "$NAME" ]; then
    # Shutdown and reboot use these files; the boot splash uses the copy in the initramfs.
    echo "note: $NAME is the selected theme; the initramfs keeps its own copy until it is rebuilt (re-run with --select)"
  else
    echo "not selected (use --select to make it the boot splash)"
  fi
  exit 0
fi

# 5. Select it and rebuild the running kernel's initramfs, after saving the previous state.
KVER=$(uname -r)
IMG=/boot/initramfs-$KVER.img
BACKUP=$IMG.pre-$NAME
run mkdir -p "$STATE"
current=$(plymouth-set-default-theme)
if [ ! -f "$STATE/previous-theme" ] && [ "$current" != "$NAME" ]; then
  echo "+ record previous theme '$current' in $STATE/previous-theme"
  [ "$DRY" = 1 ] || echo "$current" > "$STATE/previous-theme"
fi
if [ ! -f "$STATE/plymouthd.conf.orig" ] && [ -f /etc/plymouth/plymouthd.conf ]; then
  run cp -a /etc/plymouth/plymouthd.conf "$STATE/plymouthd.conf.orig"
fi
if [ ! -f "$BACKUP" ] && [ -f "$IMG" ]; then
  run cp -a "$IMG" "$BACKUP"
fi
run nice -n 10 plymouth-set-default-theme -R "$NAME"
if [ "$DRY" = 0 ]; then
  # (Read the listing first: "lsinitrd | grep -q" fails under pipefail when grep exits early.)
  listing=$(lsinitrd "$IMG")
  if grep -q "usr/share/plymouth/themes/$NAME/$NAME.script" <<< "$listing" &&
     grep -q "plymouth/script.so" <<< "$listing"; then
    echo "initramfs $IMG contains the $NAME theme and the script plugin"
  else
    echo "plymouth-install: $IMG does not contain the theme; roll back with plymouth-uninstall.sh" >&2
    exit 1
  fi
fi
echo "selected; previous initramfs kept as $BACKUP"
