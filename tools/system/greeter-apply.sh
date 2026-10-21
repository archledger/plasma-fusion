#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Style the login screen with Plasma Fusion: the Plasma login greeter (plasma-login-manager 6.7)
# with Plasma Fusion Dark, or SDDM with the Plasma Fusion SDDM theme (docs/parts/sddm.md). Run as
# root after the plasma-fusion package is installed (it reads the system-wide copies in /usr/share).
#
#   greeter-apply.sh [--greeter WHICH] [--display-from FILE] [--login-image VARIANT]
#                    [--dry-run] [--check]
#   greeter-apply.sh --output DIR [--data-dir DIR] [--display-from FILE] [--login-image VARIANT]
#
#   --greeter WHICH plasmalogin or sddm; auto (the default) takes the display manager systemd
#                   starts (display-manager.service), else plasma-login-manager while its user
#                   exists, else SDDM. --output always writes plasma-login-manager's files
#   --display-from FILE  also give the greeter this display configuration, normally the
#                   kwinoutputconfig.json of the user whose display scale it should use:
#                   sudo greeter-apply.sh --display-from ~/.config/kwinoutputconfig.json
#                   ("Apply Plasma Settings…" copies it too). The Plasma Fusion sizes are
#                   logical pixels at the session's scale (4/3 on the 1920x1200 test device);
#                   without it the greeter keeps its own scale (often 1: everything smaller);
#                   plasma-login-manager only
#   --login-image VARIANT
#                   login (default, the Login board's blur with its veil), dimmed (the lock
#                   screen's wallpaper, for greeter and lock parity) or blurred (the Login
#                   board's blur without the veil)
#   --dry-run       show what would be written; change nothing
#   --check         report whether the greeter uses Plasma Fusion; change nothing (SDDM: needs no
#                   root, exit 2 when a file it cannot read leaves the answer open; any of the
#                   three wallpapers counts unless --login-image names one)
#   --output DIR    no root: write the greeter's files into DIR/config/ and the daemon
#                   configuration with the wallpaper into DIR/plasmalogin.conf (previews, tests)
#   --data-dir DIR  with --output: where Plasma Fusion is installed (default /usr/share)
#   -h, --help
#
# System Settings > Login Screen > "Apply Plasma Settings…" (kcm_plasmalogin, KAuth helper
# plasmaloginauthhelper.cpp, action org.kde.kcontrol.kcmplasmalogin.sync) copies the user's
# kdeglobals, plasmarc, plasma-localerc, kcminputrc, kwinoutputconfig.json, kxkbrc and
# fontconfig/fonts.conf into the greeter user's ~/.config (plasmalogin, /var/lib/plasmalogin),
# writing as that user, and removes its ~/.cache (the Plasma style cache). The greeter's session
# start (startplasma-login-wayland) then writes the defaults of the Global Theme named by
# kdeglobals [KDE] LookAndFeelPackage into ~/.config/kdedefaults/ and applies the colour scheme
# when its hash changed. The wallpaper is a [Greeter] setting of the daemon's configuration, read
# by plasma-login-wallpaper; the KCM's "Apply" writes it to /etc/plasmalogin.conf. That file is
# read last; before it come /etc/plasmalogin.conf.d/*, /usr/lib/plasmalogin/defaults.conf and
# /usr/lib/plasmalogin/plasmalogin.conf.d/* in this order (PlasmaLoginSettings::getInstance adds
# them with KConfig::addConfigSources, and KConfig lets a later source win). Fedora's
# defaults.conf sets the wallpaper, so a drop-in in /etc/plasmalogin.conf.d/ has no effect.
#
# This script does the same for Plasma Fusion Dark, with the values of the installed Global Theme
# org.plasmafusion.dark.desktop (its contents/defaults) and, since the Global Themes carry no fonts
# or cursor, the fonts and cursor that tools/device/fusion-config.sh sets once, as the greeter user:
#   ~/.config/kdeglobals   colour scheme PlasmaFusionDark (applied with plasma-apply-colorscheme),
#                          fonts (Manrope), icon theme PlasmaFusion-Dark, widget style,
#                          [KDE] LookAndFeelPackage=org.plasmafusion.dark.desktop
#   ~/.config/plasmarc     [Theme] name=plasma-fusion-dark
#   ~/.config/kcminputrc   [Mouse] cursorTheme=PlasmaFusion-cursors
#   ~/.config/kwinoutputconfig.json   with --display-from only: that file
#   ~/.cache               removed (as the KCM does)
# Keys it does not set stay as they are (a previous "Apply Plasma Settings…" keeps its keyboard,
# touchpad and locale settings). As root, in /etc/plasmalogin.conf:
#   [Greeter] WallpaperPlugin=org.kde.image, [Greeter][Wallpaper][org.kde.image][General] Image
#   and PreviewImage = the pre-darkened Dusk Ridge,
#   /usr/share/plasma-fusion/backgrounds/dusk-ridge-dark-login.png
#   --login-image VARIANT picks the wallpaper treatment from the generator's three Dusk Ridge
#   variants: login (default) is the Login board's blur(20px) with its 50 % veil, dimmed is the
#   lock screen's sharp wallpaper with its 22 % veil (greeter and lock screen parity), and blurred
#   is the Login board's blur without the veil. The greeter's clock and layout are compiled into
#   plasma-login-greeter and do not change here.
# (a block appended to the file while it has no [Greeter] settings, so its comments stay;
# otherwise the keys are written with kwriteconfig6, which rewrites the file as the KCM does).
# The greeter's layout is compiled into plasma-login-greeter; only its styling changes.
#
# SDDM draws the whole login screen from its theme, so the SDDM mode selects the Plasma Fusion SDDM
# theme (share/sddm/themes/plasmafusion). SDDM 0.21 reads /usr/lib/sddm/sddm.conf.d/*, then
# /etc/sddm.conf.d/* (each directory sorted), then /etc/sddm.conf, and the last value wins
# (src/common/ConfigReader.cpp). System Settings' Login Screen (SDDM) page writes its choices into
# /etc/sddm.conf.d/kde_settings.conf and removes the same keys from /etc/sddm.conf, which would
# override them (sddm-kcm sddmauthhelper.cpp). This mode makes the same choice there, so the page
# shows Plasma Fusion as the chosen theme and can choose another again:
#   /etc/sddm.conf.d/kde_settings.conf  [Theme] Current=plasmafusion and
#                                       CursorTheme=PlasmaFusion-cursors
#   /etc/sddm.conf                     those two keys removed, where it sets them
#   <theme>/theme.conf.user             [General] background, with --login-image dimmed or blurred
#                                       or when the file exists (SDDM reads it over the theme's
#                                       theme.conf; it is where the page keeps a theme's wallpaper)
# Before anything changes, the values SDDM would then read are worked out in its own order and with
# its own parser; a file read later that would still choose another theme or cursor stops the run.
# On NixOS the system configuration selects the theme instead (programs.plasma-fusion.sddm).
#
# Nothing is restarted: the greeter shows the change the next time it starts (after the next
# logout or reboot). Before changing anything the files it touches are copied to
# /var/lib/plasma-fusion/greeter-backup-<UTC time>/ (its info file says whether the greeter
# already used Plasma Fusion); greeter-restore.sh puts them back.
# shellcheck disable=SC2016 # the sh -c snippets take their arguments as $0, $1, ...
set -euo pipefail

LNF=org.plasmafusion.dark.desktop
GREETER_USER=plasmalogin
CONF=/etc/plasmalogin.conf
WALLPAPER_GROUP=Greeter/Wallpaper/org.kde.image/General
BACKGROUND=plasma-fusion/backgrounds/dusk-ridge-dark-login.png
BACKUP_ROOT=/var/lib/plasma-fusion
CONFIG_FILES=(kdeglobals plasmarc kcminputrc)

DRY=0 CHECK=0 OUTPUT='' DATA=/usr/share DISPLAY_FROM='' GREETER=auto IMAGE_CHOSEN=0
# PF_GREETER_ROOT: the tests run the SDDM mode on a directory tree instead of / (never as root,
# who must not write through a tree another user prepared).
SYSROOT=${PF_GREETER_ROOT:-}
usage() { sed -n '/^#   greeter-apply.sh \[/,/^#   -h, --help/p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case $1 in
    --greeter)
      case ${2:-} in
        auto | plasmalogin | sddm) GREETER=$2 ;;
        *) echo "--greeter needs auto, plasmalogin or sddm" >&2; exit 2 ;;
      esac
      shift ;;
    --dry-run) DRY=1 ;;
    --check) CHECK=1 ;;
    --output) [ $# -ge 2 ] || { echo "--output needs a directory" >&2; exit 2; }; OUTPUT=$2; shift ;;
    --data-dir) [ $# -ge 2 ] || { echo "--data-dir needs a directory" >&2; exit 2; }; DATA=$(cd "$2" && pwd); shift ;;
    --display-from) [ $# -ge 2 ] || { echo "--display-from needs a file" >&2; exit 2; }; DISPLAY_FROM=$2; shift ;;
    --login-image)
      [ $# -ge 2 ] || { echo "--login-image needs login, dimmed or blurred" >&2; exit 2; }
      case $2 in
        login) BACKGROUND=plasma-fusion/backgrounds/dusk-ridge-dark-login.png ;;
        dimmed) BACKGROUND=plasma-fusion/backgrounds/dusk-ridge-dark-dimmed.png ;;
        blurred) BACKGROUND=plasma-fusion/backgrounds/dusk-ridge-dark-blurred.png ;;
        *) echo "--login-image needs login, dimmed or blurred" >&2; exit 2 ;;
      esac
      IMAGE_CHOSEN=1
      shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[ -z "$OUTPUT" ] && [ "$DATA" != /usr/share ] && { echo "--data-dir only goes with --output" >&2; exit 2; }

say() { printf '%s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die() { printf 'greeter-apply: %s\n' "$*" >&2; exit 1; }

# The plasma-fusion package as the package database names it (rpm, pacman or dpkg).
installed_package() {
  local p
  p=$(rpm -q plasma-fusion 2>/dev/null) || p=$(pacman -Q plasma-fusion 2>/dev/null) ||
    { p=$(dpkg-query -W -f '${db:Status-Status} ${Package} ${Version}' plasma-fusion 2>/dev/null) &&
      [[ $p == "installed "* ]] && p=${p#installed }; } || p='not installed as a package'
  printf '%s\n' "$p"
}

# Outputs and scales of a kwinoutputconfig.json given on stdin ("eDP-1 x1.3333 ..."); fails when
# it is not one.
display_summary() {
  # Root: isolated Python (-I) in an empty environment, so no module from the current directory or
  # PYTHON* variables is used.
  env -i PATH=/usr/bin:/bin python3 -I -c '
import json, sys
data = json.load(sys.stdin)
outs = [s for s in data if isinstance(s, dict) and s.get("name") == "outputs"] if isinstance(data, list) else []
if not outs:
    sys.exit("not a KWin output configuration (no \"outputs\" section)")
print(" ".join("%s x%s" % (o.get("connectorName", "?"), round(float(o.get("scale", 1)), 4))
               for s in outs for o in s.get("data", [])) or "no outputs")'
}

# The unit display-manager.service links to: the display manager systemd starts (systemctl enable
# makes that alias); empty when there is none. NixOS generates display-manager.service itself (a
# script, no alias); its sddm module writes /etc/sddm.conf.d/00-nixos.conf, only while it is on.
enabled_dm() {
  local unit
  if unit=$(readlink "$SYSROOT/etc/systemd/system/display-manager.service" 2>/dev/null); then
    printf '%s\n' "${unit##*/}"
  elif [ -e "$SYSROOT/etc/NIXOS" ] && [ -e "$SYSROOT/etc/sddm.conf.d/00-nixos.conf" ]; then
    echo sddm.service
  fi
}

if [ "$GREETER" = auto ]; then
  case $([ -n "$OUTPUT" ] || enabled_dm) in
    sddm.service) GREETER=sddm ;;
    plasmalogin.service | plasma-login-manager.service) GREETER=plasmalogin ;;
    *)
      # --output, or neither is the enabled display manager: plasma-login-manager while its user
      # exists (what this script did before it knew SDDM), else SDDM.
      if [ -n "$OUTPUT" ] || getent passwd plasmalogin >/dev/null 2>&1; then
        GREETER=plasmalogin
      elif getent passwd sddm >/dev/null 2>&1; then
        GREETER=sddm
      else
        die "neither plasma-login-manager nor SDDM is installed (or name one with --greeter)"
      fi ;;
  esac
fi
[ -z "$SYSROOT" ] || [ "$GREETER" = sddm ] || die "PF_GREETER_ROOT is only for the SDDM mode's tests"

# Temporary directories: $own stays the invoking user's (root's), $work (plasma-login-manager,
# below) belongs to the greeter user, who runs the tools that write the greeter's files.
own=$(mktemp -d "${TMPDIR:-/tmp}/plasma-fusion-greeter.XXXXXX")
work=''
trap 'rm -rf "$own" ${work:+"$work"}' EXIT
mkdir -p "$own/home/.config" "$own/run"
chmod 0700 "$own/run"
# Every KDE tool runs offscreen with a clean environment: no session bus or display, a HOME in a
# temporary directory (KConfig wants a writable ~/.config, or it pops up an error dialog) and only
# the system-wide data.
# TOOL_PATH: /usr/bin:/bin, with NixOS's system profile in front for its read-only SDDM check.
TOOL_PATH=/usr/bin:/bin
as_root_tool() { env -i PATH="$TOOL_PATH" HOME="$own/home" XDG_CONFIG_HOME="$own/home/.config" \
  XDG_RUNTIME_DIR="$own/run" XDG_CONFIG_DIRS=/etc/xdg QT_QPA_PLATFORM=offscreen LANG=C.UTF-8 "$@"; }

kw() { # $1 file, $2 group (nested with /), $3 key, $4 value or --delete
  local groups=() g part
  IFS=/ read -r -a g <<<"$2"
  for part in "${g[@]}"; do groups+=(--group "$part"); done
  if [ "$4" = --delete ]; then
    as_root_tool kwriteconfig6 --file "$1" "${groups[@]}" --key "$3" --delete
  else
    as_root_tool kwriteconfig6 --file "$1" "${groups[@]}" --key "$3" "$4"
  fi
}
kr() { # $1 file, $2 group (nested with /), $3 key
  local groups=() g part
  IFS=/ read -r -a g <<<"$2"
  for part in "${g[@]}"; do groups+=(--group "$part"); done
  as_root_tool kreadconfig6 --file "$1" "${groups[@]}" --key "$3" 2>/dev/null || true
}

# The files of a configuration directory as plasma-login and SDDM list them (QDir::Files: no
# hidden files, links to files included), sorted.
conf_dir_files() { # $1 directory
  [ -d "$1" ] || return 0
  # -H: a directory that is itself a link is listed too, as QDir lists it
  find -H "$1" -mindepth 1 -maxdepth 1 ! -name '.*' -xtype f -print 2>/dev/null | LC_ALL=C sort
}

# ---------- SDDM ----------

SDDM_THEME=plasmafusion
# The cursors tools/device/fusion-config.sh sets, as for plasma-login-manager below.
SDDM_CURSORS=PlasmaFusion-cursors
SDDM_KEYS=(Current CursorTheme)

# SDDM's parser (ConfigBase::loadInternal) over one configuration file: everything from the first
# # on is a comment, a line with = assigns, one in brackets starts a section ("General" before the
# first), the last assignment wins. get prints the value of [SECTION] KEY and fails when the file
# does not set it; drop prints the file without the lines that set it (the rest byte for byte).
sddm_conf() { # $1 get or drop, $2 file, $3 section, $4 key
  [ -f "$2" ] && [ -r "$2" ] || return 1
  awk -v mode="$1" -v want_s="$3" -v want_k="$4" '
    function trim(s) { sub(/^[ \t\r\f\v]+/, "", s); sub(/[ \t\r\f\v]+$/, "", s); return s }
    BEGIN { s = "General"; found = 0 }
    {
      line = $0
      if ((c = index(line, "#")) > 0) line = substr(line, 1, c - 1)
      line = trim(line)
      if ((e = index(line, "=")) > 0) {
        if (s == want_s && trim(substr(line, 1, e - 1)) == want_k) {
          v = trim(substr(line, e + 1)); found = 1
          if (mode == "drop") next
        }
      } else if (line ~ /^\[.*\]$/) s = substr(line, 2, length(line) - 2)
      if (mode == "drop") print
    }
    END { if (mode == "get" && found) print v; exit mode == "get" && !found }' "$2"
}
# SDDM's configuration files in the order it reads them (ConfigBase::load). Its QDir::LocaleAware
# sort orders the lower-case ASCII names distributions use as bytes do. Arguments: files about to
# be written into /etc/sddm.conf.d, listed in their place before they exist.
sddm_files() {
  local p
  conf_dir_files "$SYSROOT/usr/lib/sddm/sddm.conf.d"
  { conf_dir_files "$SYSROOT/etc/sddm.conf.d"
    for p in "$@"; do
      [ "${p%/*}" != "$SYSROOT/etc/sddm.conf.d" ] || [ -e "$p" ] || printf '%s\n' "$p"
    done; } | LC_ALL=C sort
  printf '%s\n' "$SYSROOT/etc/sddm.conf"
}
# The value SDDM uses for [SECTION] KEY in REPLY, the file that sets it in REPLY_FILE (both empty
# when no file does: SDDM's built-in default). Pairs FILE NEW read NEW in FILE's place: the result
# of writing NEW there.
sddm_effective() { # $1 section, $2 key, [FILE NEW]...
  local f v section=$1 key=$2
  local -A swap=()
  shift 2
  while [ $# -ge 2 ]; do swap[$1]=$2; shift 2; done
  REPLY='' REPLY_FILE=''
  while IFS= read -r f; do
    if v=$(sddm_conf get "${swap[$f]:-$f}" "$section" "$key"); then REPLY=$v REPLY_FILE=$f; fi
  done < <(sddm_files "${!swap[@]}")
}
# The configuration directories that cannot be listed and the files that exist but cannot be read
# (an unprivileged --check): what they set is unknown.
sddm_unreadable() {
  local f
  for f in "$SYSROOT/usr/lib/sddm/sddm.conf.d" "$SYSROOT/etc/sddm.conf.d"; do
    if [ -d "$f" ] && { [ ! -r "$f" ] || [ ! -x "$f" ]; }; then printf '%s\n' "${f#"$SYSROOT"}"; fi
  done
  while IFS= read -r f; do
    [ ! -e "$f" ] || [ -r "$f" ] || printf '%s\n' "${f#"$SYSROOT"}"
  done < <(sddm_files)
}
# Whether SDDM's listing (QDir::LocaleAware, in the daemon's locale) may order drop-ins $1 and $2
# (default kde_settings.conf) otherwise than byte order does. glibc's collations ignore punctuation
# at first, ICU's weigh it before digits, both put case and letters beyond ASCII elsewhere than
# bytes do; all agree with byte order where the names first differ in a lower-case ASCII letter or
# a digit on both sides, or where one name begins with the whole other.
sddm_order_depends_on_locale() { # $1 file name, [$2 file name]
  local a=$1 b=${2:-kde_settings.conf} i=0 x y
  while [ "$i" -lt "${#a}" ] && [ "$i" -lt "${#b}" ]; do
    x=${a:i:1} y=${b:i:1}
    if [ "$x" != "$y" ]; then
      case $x$y in
        [abcdefghijklmnopqrstuvwxyz0123456789][abcdefghijklmnopqrstuvwxyz0123456789]) return 1 ;;
        *) return 0 ;;
      esac
    fi
    i=$((i + 1))
  done
  return 1
}
# The drop-ins besides kde_settings.conf that set the theme or the cursors and whose order against
# it depends on the locale: whether they win cannot be told here.
sddm_unordered() {
  local f k
  while IFS= read -r f; do
    [ "${f##*/}" != kde_settings.conf ] && sddm_order_depends_on_locale "${f##*/}" || continue
    for k in "${SDDM_KEYS[@]}"; do
      if sddm_conf get "$f" Theme "$k" >/dev/null; then printf '%s\n' "${f#"$SYSROOT"}"; break; fi
    done
  done < <(conf_dir_files "$SYSROOT/etc/sddm.conf.d")
}
# Drop-ins that set [Theme] KEY to another value than the file SDDM takes it from (sddm_effective,
# with the same FILE NEW pairs) and that sit in that file's directory in an order against it that
# depends on the locale: under SDDM's sort either may be read last, so the value SDDM uses cannot be
# told here. Prints the pairs. Pairs with /etc's kde_settings.conf are sddm_unordered's.
sddm_contested() { # $1 key, [FILE NEW]...
  local key=$1 f v win won
  local -A swap=()
  shift
  sddm_effective Theme "$key" "$@"
  win=$REPLY_FILE won=$REPLY
  [ -n "$win" ] && [ "$win" != "$SYSROOT/etc/sddm.conf" ] || return 0
  [ "$win" != "$SYSROOT/etc/sddm.conf.d/kde_settings.conf" ] || return 0
  while [ $# -ge 2 ]; do swap[$1]=$2; shift 2; done
  while IFS= read -r f; do
    [ "$f" != "$win" ] && [ "${f%/*}" = "${win%/*}" ] || continue
    [ "$f" != "$SYSROOT/etc/sddm.conf.d/kde_settings.conf" ] || continue
    v=$(sddm_conf get "${swap[$f]:-$f}" Theme "$key") && [ "$v" != "$won" ] || continue
    sddm_order_depends_on_locale "${f##*/}" "${win##*/}" || continue
    printf '%s and %s\n' "${f#"$SYSROOT"}" "${win#"$SYSROOT"}"
  done < <(sddm_files "${!swap[@]}")
}
# Drop-ins of one directory that set different [Theme] ThemeDir values in an order that depends on
# the locale: which theme tree SDDM uses cannot be told here (greeter-apply.sh would check the
# theme, and write its theme.conf.user, in another tree than SDDM's). Prints the pairs.
sddm_themedir_unordered() {
  local d f v i j
  local -a names values
  for d in "$SYSROOT/usr/lib/sddm/sddm.conf.d" "$SYSROOT/etc/sddm.conf.d"; do
    names=() values=()
    while IFS= read -r f; do
      if v=$(sddm_conf get "$f" Theme ThemeDir); then names+=("$f") values+=("$v"); fi
    done < <(conf_dir_files "$d")
    for ((i = 0; i < ${#names[@]}; i++)); do
      for ((j = i + 1; j < ${#names[@]}; j++)); do
        [ "${values[i]}" != "${values[j]}" ] &&
          sddm_order_depends_on_locale "${names[i]##*/}" "${names[j]##*/}" || continue
        printf '%s and %s\n' "${names[i]#"$SYSROOT"}" "${names[j]#"$SYSROOT"}"
      done
    done
  done
}
# The first file or directory of theme tree $1 that SDDM's greeter user cannot read (or search): the
# greeter runs as that user, not as root (Greeter.cpp: setUser("sddm")), and falls back to SDDM's
# own theme without it. As root the check runs as user sddm; otherwise as the caller.
sddm_unreadable_theme() { # $1 theme directory
  local g up
  local -a mine=() can=() r=() rx=()
  if [ "$(id -u)" != 0 ] || [ -n "$SYSROOT" ] || ! getent passwd sddm >/dev/null; then
    find "$1" \( ! -readable -o -type d ! -executable \) -print -quit 2>/dev/null || printf '%s\n' "$1"
  elif command -v setpriv >/dev/null; then
    # (a directory above the tree that user cannot pass makes find fail: the tree is reported)
    setpriv --reuid=sddm --regid="$(id -g sddm)" --init-groups --no-new-privs -- \
      find "$1" \( ! -readable -o -type d ! -executable \) -print -quit 2>/dev/null || printf '%s\n' "$1"
  else
    # No setpriv (util-linux; a minimal Fedora has util-linux-core only): the mode bits as the
    # kernel reads them for that user - the owner's where it owns the file, else the group's where
    # one of its groups does, else the others' (ACLs are not read this way).
    for g in $(id -G sddm); do
      [ "${#mine[@]}" = 0 ] || mine+=(-o)
      mine+=(-group "$g")
    done
    for g in x r rx; do
      can=(\( -user sddm -perm "-u=$g" \) -o \( ! -user sddm \( "${mine[@]}" \) -perm "-g=$g" \)
        -o \( ! -user sddm ! \( "${mine[@]}" \) -perm "-o=$g" \))
      case $g in
        x)
          # Every directory above the tree must let that user through
          up=$1
          while [ "$up" != / ]; do
            up=$(dirname -- "$up")
            [ -z "$(find "$up" -maxdepth 0 ! \( "${can[@]}" \) -print 2>/dev/null)" ] || { printf '%s\n' "$up"; return; }
          done ;;
        r) r=("${can[@]}") ;;
        rx) rx=("${can[@]}") ;;
      esac
    done
    find "$1" \( -type d ! \( "${rx[@]}" \) -o ! -type d ! \( "${r[@]}" \) \) -print -quit 2>/dev/null ||
      printf '%s\n' "$1"
  fi
}
show_diff() { # $1 a file, $2 its new contents
  note "--- ${1#"$SYSROOT"}"
  { if [ -f "$1" ]; then cat -- "$1"; fi; } |
    diff -u --label "current ${1#"$SYSROOT"}" --label "new ${1#"$SYSROOT"}" - "$2" | sed 's/^/    /' || true
}

sddm_main() {
  local dir=$SYSROOT/etc/sddm.conf.d conf=$SYSROOT/etc/sddm.conf
  local kde=$SYSROOT/etc/sddm.conf.d/kde_settings.conf themedir theme greeter user_conf
  local default_bg user_bg bg dm k want before=other ok mark src builtin share nixos=0 open v
  local themedir_bad theme_unread=''
  local conf_new='' user_new='' swaps=()
  [ -z "$OUTPUT" ] || die "--output writes plasma-login-manager's files; preview the SDDM theme with sddm-greeter-qt6 --test-mode (docs/parts/sddm.md)"
  [ -z "$DISPLAY_FROM" ] || die "--display-from is for plasma-login-manager (for SDDM: System Settings > Login Screen (SDDM) > Apply Plasma Settings…)"
  # NixOS generates /etc: only the read-only check, against the system profile's paths.
  if [ -e "$SYSROOT/etc/NIXOS" ]; then
    nixos=1
    # KConfig's tools live in the system profile there (root's, like /usr/bin elsewhere)
    TOOL_PATH=$SYSROOT/run/current-system/sw/bin:$TOOL_PATH
  fi
  [ "$nixos" = 0 ] || [ "$CHECK" = 1 ] ||
    die "NixOS generates /etc: set programs.plasma-fusion.sddm = true in the system configuration instead (docs/parts/nixos.md)"
  if [ -n "$SYSROOT" ]; then
    [ "$(id -u)" != 0 ] || die "PF_GREETER_ROOT is for the tests and never used as root"
  elif [ "$CHECK" = 0 ]; then
    [ "$(id -u)" = 0 ] || die "run as root (--check needs no root)"
  fi
  for tool in kreadconfig6 kwriteconfig6; do
    command -v "$tool" >/dev/null || die "$tool is missing (kf6-kconfig)"
  done
  if [ "$CHECK" = 0 ]; then
    while IFS= read -r f; do
      die "$f set different [Theme] ThemeDir values, and which one SDDM reads last depends on its locale (QDir::LocaleAware); keep one or give them lower-case ASCII names. Nothing was changed."
    done < <(sddm_themedir_unordered)
  fi
  sddm_effective Theme ThemeDir
  themedir=${REPLY:-/usr/share/sddm/themes}
  # ThemeDir as SDDM uses it: an empty value set in a file is not the default (SDDM then looks for
  # the theme relative to its working directory and falls back to its built-in one), and a relative
  # value is resolved from the daemon's working directory, not this shell's (Display.cpp: QDir of
  # the value). Neither can be checked or written here.
  themedir_bad=''
  if [ -n "$REPLY_FILE" ] && [ -z "$REPLY" ]; then
    themedir_bad="ThemeDir is empty in ${REPLY_FILE#"$SYSROOT"}"
  elif [ "${themedir#/}" = "$themedir" ]; then
    themedir_bad="ThemeDir=$themedir in ${REPLY_FILE#"$SYSROOT"} is relative (SDDM resolves it from its own working directory)"
  fi
  theme=$SYSROOT$themedir/$SDDM_THEME
  user_conf=$theme/theme.conf.user
  greeter=$SYSROOT/usr/bin/sddm-greeter-qt6
  share=$DATA
  if [ "$nixos" = 1 ]; then
    greeter=$SYSROOT/run/current-system/sw/bin/sddm-greeter-qt6
    share=/run/current-system/sw/share
  fi
  IMAGE=$share/$BACKGROUND
  default_bg=$(kr "$theme/theme.conf" General background)
  user_bg=$(kr "$user_conf" General background)
  bg=${user_bg:-$default_bg}
  dm=$(enabled_dm)

  if [ "$CHECK" = 1 ]; then
    ok=yes open=no
    row() { # $1 label, $2 current, $3 wanted, $4 where it comes from
      mark=ok
      [ "$2" = "$3" ] || { mark=differs; ok=no; }
      printf '  %-14s %-58s %s\n' "$1" "${2:-<unset>} ($4)" "$mark"
    }
    say "SDDM (enabled display manager: ${dm:-none}):"
    builtin="SDDM's built-in default"
    sddm_effective Theme Current
    src=${REPLY_FILE#"$SYSROOT"}
    row theme "$REPLY" "$SDDM_THEME" "${src:-$builtin}"
    # The theme tree read as SDDM's greeter user (root's check) or as this user (anyone else's:
    # what this user cannot read, that user may or may not)
    [ -n "$themedir_bad" ] || [ ! -d "$theme" ] || theme_unread=$(sddm_unreadable_theme "$theme")
    if [ -n "$themedir_bad" ]; then
      row "theme files" "not found" installed "$themedir_bad"
    elif [ -n "$theme_unread" ] && [ "$(id -u)" = 0 ]; then
      row "theme files" "unreadable for sddm" installed "${theme_unread#"$SYSROOT"}"
    elif [ -n "$theme_unread" ]; then
      row "theme files" "unreadable here" installed "${theme_unread#"$SYSROOT"}"
    elif [ ! -f "$theme/metadata.desktop" ]; then
      row "theme files" missing installed "${theme#"$SYSROOT"}"
    else
      row "theme files" installed installed "${theme#"$SYSROOT"}"
    fi
    row "Qt 6 greeter" "$([ -x "$greeter" ] && echo installed || echo missing)" installed "${greeter#"$SYSROOT"}"
    sddm_effective Theme CursorTheme
    src=${REPLY_FILE#"$SYSROOT"}
    row cursors "$REPLY" "$SDDM_CURSORS" "${src:-$builtin}"
    # Any of the three wallpapers greeter-apply.sh offers, unless --login-image names one.
    want=$IMAGE
    if [ "$IMAGE_CHOSEN" = 0 ]; then
      for v in login dimmed blurred; do
        [ "$bg" != "$share/plasma-fusion/backgrounds/dusk-ridge-dark-$v.png" ] || want=$bg
      done
    fi
    row wallpaper "$bg" "$want" "$([ -n "$user_bg" ] && echo theme.conf.user || echo theme.conf)"
    while IFS= read -r f; do
      say "  cannot read $f: what it sets is unknown (run --check as root)"; open=yes
    done < <(sddm_unreadable)
    # A theme file this user cannot read (0640 for SDDM's group, or for nobody): whether the greeter
    # can, and the wallpaper the theme's options set, is unknown here
    if [ -n "$theme_unread" ] && [ "$(id -u)" != 0 ]; then
      say "  cannot read ${theme_unread#"$SYSROOT"}: whether SDDM's greeter user can, and the theme's wallpaper setting, are unknown (run --check as root)"
      open=yes
    fi
    while IFS= read -r f; do
      say "  $f sets the theme or cursors; whether SDDM reads it before or after kde_settings.conf depends on its locale"
      open=yes
    done < <(sddm_unordered)
    while IFS= read -r f; do
      say "  $f set different theme directories; which one SDDM reads last depends on its locale"
      open=yes
    done < <(sddm_themedir_unordered)
    for k in "${SDDM_KEYS[@]}"; do
      while IFS= read -r f; do
        say "  $f set different [Theme] $k values; which one SDDM reads last depends on its locale"
        open=yes
      done < <(sddm_contested "$k")
    done
    [ "$dm" = sddm.service ] || say "  note: SDDM shows this only while it is the display manager"
    if [ "$open" = yes ]; then say "Plasma Fusion greeter: unknown"; exit 2; fi
    say "Plasma Fusion greeter: $ok"
    [ "$ok" = yes ]
    exit
  fi

  [ -z "$themedir_bad" ] ||
    die "$themedir_bad: SDDM would not find the theme there; name an absolute directory or remove the line. Nothing was changed."
  [ -f "$theme/metadata.desktop" ] || die "the Plasma Fusion SDDM theme is not in $themedir (install the plasma-fusion package)"
  f=$(sddm_unreadable_theme "$theme")
  [ -z "$f" ] || die "${f#"$SYSROOT"} cannot be read by SDDM's greeter user (sddm), which loads the theme; make the theme tree readable (the package installs it 0755/0644). Nothing was changed."
  [ -x "$greeter" ] || die "${greeter#"$SYSROOT"} is missing: the theme needs SDDM's Qt 6 greeter (QtVersion=6); without it SDDM shows its own theme"
  [ -f "$SYSROOT$DATA/icons/$SDDM_CURSORS/index.theme" ] || die "cursor theme $SDDM_CURSORS is not installed in $DATA"
  [ -f "$SYSROOT$IMAGE" ] || die "$IMAGE is missing (install the plasma-fusion package)"
  # Root reads and writes theme.conf.user in the theme's directory: only in one nobody else can
  # write to (so nobody can plant a file or a link there), and never through a link.
  if [ -z "$SYSROOT" ]; then
    [ "$(stat -c %u "$theme")" = 0 ] && [ $((0$(stat -c %a "$theme") & 022)) = 0 ] ||
      die "$theme is writable by others than root; SDDM themes belong to root"
  fi
  # Never through a link: renaming the new file over it would replace a link managed elsewhere, and
  # root would copy whatever it points to.
  for f in "$kde" "$conf" "$user_conf"; do
    [ ! -L "$f" ] || die "${f#"$SYSROOT"} is a link; change the theme where it points, or make it a file"
  done
  # Whether the greeter already used Plasma Fusion: any value this run writes already in effect -
  # the theme, the cursors (an earlier run's, kept when the theme was changed by hand since) or one
  # of its wallpapers in theme.conf.user. Restore goes back past such a run to an older backup.
  sddm_effective Theme Current
  [ "$REPLY" != "$SDDM_THEME" ] || before=plasma-fusion
  sddm_effective Theme CursorTheme
  [ "$REPLY" != "$SDDM_CURSORS" ] || before=plasma-fusion
  case $user_bg in "$share/plasma-fusion/backgrounds/"*) before=plasma-fusion ;; esac

  # The new files, made in $own. kde_settings.conf and theme.conf.user with kwriteconfig6: KConfig
  # is what System Settings' page writes them with as well.
  if [ -f "$kde" ]; then cp -- "$kde" "$own/kde_settings.conf"; else : >"$own/kde_settings.conf"; fi
  kw "$own/kde_settings.conf" Theme Current "$SDDM_THEME"
  kw "$own/kde_settings.conf" Theme CursorTheme "$SDDM_CURSORS"
  swaps=("$kde" "$own/kde_settings.conf")
  if [ -f "$conf" ]; then
    # Only the lines SDDM reads as those keys go, so the file keeps its comments (System Settings'
    # page rewrites it with KConfig, which drops them).
    cp -- "$conf" "$own/sddm.conf"
    for k in "${SDDM_KEYS[@]}"; do
      sddm_conf drop "$own/sddm.conf" Theme "$k" >"$own/sddm.conf.new"
      mv -f -- "$own/sddm.conf.new" "$own/sddm.conf"
    done
    cmp -s "$conf" "$own/sddm.conf" || { conf_new=$own/sddm.conf; swaps+=("$conf" "$conf_new"); }
  fi
  # The wallpaper: the theme's own unless another one is wanted or a theme.conf.user exists (it can
  # hold another background, from the page or from an earlier run).
  if [ -f "$user_conf" ] || [ "$IMAGE" != "$default_bg" ]; then
    if [ -f "$user_conf" ]; then cp -- "$user_conf" "$own/theme.conf.user"; else : >"$own/theme.conf.user"; fi
    kw "$own/theme.conf.user" General background "$IMAGE"
    cmp -s "$user_conf" "$own/theme.conf.user" 2>/dev/null || user_new=$own/theme.conf.user
  fi
  # A read-only theme tree (an immutable /usr) cannot take theme.conf.user: stop before /etc changes
  [ -z "$user_new" ] || [ -w "$theme" ] ||
    die "${theme#"$SYSROOT"} cannot be written (a read-only /usr?), so --login-image cannot be set there; run without it for the theme's own wallpaper. Nothing was changed."
  while IFS= read -r f; do
    die "$f sets the theme or cursors, and whether SDDM reads it before or after kde_settings.conf depends on its locale (QDir::LocaleAware); remove those keys there or give it a lower-case ASCII name. Nothing was changed."
  done < <(sddm_unordered)
  for k in "${SDDM_KEYS[@]}"; do
    case $k in Current) want=$SDDM_THEME ;; *) want=$SDDM_CURSORS ;; esac
    sddm_effective Theme "$k" "${swaps[@]}"
    [ "$REPLY" = "$want" ] ||
      die "${REPLY_FILE#"$SYSROOT"} would still set [Theme] $k=$REPLY (SDDM reads it after ${kde#"$SYSROOT"}); change it there and run this again. Nothing was changed."
    while IFS= read -r f; do
      die "$f set different [Theme] $k values, and which one SDDM reads last depends on its locale (QDir::LocaleAware); keep one or give them lower-case ASCII names. Nothing was changed."
    done < <(sddm_contested "$k" "${swaps[@]}")
  done

  say "Plasma Fusion for SDDM (the theme in ${theme#"$SYSROOT"}):"
  note "${kde#"$SYSROOT"}: [Theme] Current=$SDDM_THEME, CursorTheme=$SDDM_CURSORS"
  [ -z "$conf_new" ] || note "${conf#"$SYSROOT"}: the same keys removed (SDDM reads it last)"
  note "wallpaper: $IMAGE"
  [ "$dm" = sddm.service ] || note "note: ${dm:-no display manager} is enabled; SDDM shows this once it is the display manager"
  if cmp -s "$own/kde_settings.conf" "$kde" && [ -z "$conf_new" ] && [ -z "$user_new" ]; then
    say "SDDM uses Plasma Fusion already; nothing was changed."
    exit 0
  fi
  if [ "$DRY" = 1 ]; then
    say "Dry run: nothing is changed."
    show_diff "$kde" "$own/kde_settings.conf"
    [ -z "$conf_new" ] || show_diff "$conf" "$conf_new"
    [ -z "$user_new" ] || show_diff "$user_conf" "$user_new"
    exit 0
  fi

  # The backup: every file this mode writes, present or absent (greeter-restore.sh reads it; the
  # info file says greeter=sddm).
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  BACKUP=$SYSROOT$BACKUP_ROOT/greeter-backup-$stamp
  install -d -m 0700 "$SYSROOT$BACKUP_ROOT"
  mkdir -m 0700 "$BACKUP" || die "$BACKUP exists already; run again"
  install -d -m 0700 "$BACKUP/etc/sddm.conf.d" "$BACKUP/sddm-theme"
  : >"$BACKUP/manifest"
  save() { # $1 a file, $2 its name in the backup
    if [ -f "$1" ]; then cp -a -- "$1" "$BACKUP/$2"; echo "present $2"; else echo "absent $2"; fi >>"$BACKUP/manifest"
  }
  save "$kde" etc/sddm.conf.d/kde_settings.conf
  save "$conf" etc/sddm.conf
  save "$user_conf" sddm-theme/theme.conf.user
  {
    echo "created=$stamp"
    echo "greeter=sddm"
    echo "package=$(installed_package)"
    echo "theme=$SDDM_THEME"
    echo "theme_dir=${theme#"$SYSROOT"}"
    echo "cursors=$SDDM_CURSORS"
    echo "image=$IMAGE"
    echo "before=$before"
  } >"$BACKUP/info"
  say "backup: $BACKUP"

  # Each file next to its target first, then renamed: SDDM never reads a half-written one. What was
  # written goes into the backup too, so that greeter-restore.sh can tell whether it changed since.
  put() { # $1 new contents, $2 the file, $3 its name in the backup, $4 mode (default 0644)
    # What will be written goes into the backup first: interrupted after the rename, the restore
    # still knows the file is this run's.
    cp -- "$1" "$BACKUP/$3.applied"
    install -m "${4:-0644}" -- "$1" "$2.plasma-fusion-new"
    if [ -z "$SYSROOT" ]; then
      # A file whose mode is kept keeps its owner and group too (/etc/sddm.conf at root:sddm 0640
      # stays readable for that group); the two the page and the greeter read are root's.
      if [ -n "${4:-}" ]; then
        chown --reference="$2" -- "$2.plasma-fusion-new"
      else
        chown root:root -- "$2.plasma-fusion-new"
      fi
    fi
    mv -f -- "$2.plasma-fusion-new" "$2"
    note "wrote ${2#"$SYSROOT"}"
  }
  # theme.conf.user first: should it fail after all, /etc is still as it was
  [ -z "$user_new" ] || put "$user_new" "$user_conf" sddm-theme/theme.conf.user
  if cmp -s "$own/kde_settings.conf" "$kde"; then
    note "${kde#"$SYSROOT"} already chooses Plasma Fusion (unchanged)"
  else
    [ -d "$dir" ] || install -d -m 0755 "$dir"
    put "$own/kde_settings.conf" "$kde" etc/sddm.conf.d/kde_settings.conf
  fi
  # /etc/sddm.conf keeps its mode, owner and group; the other two must be readable by the page (run
  # as the user) and by SDDM's greeter user.
  [ -z "$conf_new" ] || put "$conf_new" "$conf" etc/sddm.conf "$(stat -c %a "$conf")"
  if [ -z "$SYSROOT" ] && command -v restorecon >/dev/null && command -v selinuxenabled >/dev/null && selinuxenabled; then
    for f in "$kde" "$conf" "$user_conf"; do [ ! -e "$f" ] || restorecon "$f" || true; done
  fi

  say "Done. The login screen shows Plasma Fusion the next time SDDM's greeter starts"
  say "(after the next logout or reboot; nothing was restarted)."
  say "Undo this run: $(dirname "$0")/greeter-restore.sh $BACKUP"
  say "Back to the look from before Plasma Fusion: $(dirname "$0")/greeter-restore.sh"
  exit 0
}
# Not as part of a || or && list: bash ignores set -e in a function called there.
if [ "$GREETER" = sddm ]; then sddm_main; fi

# ---------- preflight ----------

for tool in kreadconfig6 kwriteconfig6 plasma-apply-colorscheme; do
  command -v "$tool" >/dev/null || die "$tool is missing (plasma-workspace, kf6-kconfig)"
done
DEFAULTS=$DATA/plasma/look-and-feel/$LNF/contents/defaults
[ -f "$DEFAULTS" ] || die "Global Theme $LNF is not installed in $DATA (install the plasma-fusion package)"
IMAGE=$DATA/$BACKGROUND
[ -f "$IMAGE" ] || die "$IMAGE is missing (install the plasma-fusion package)"

lnf() { # $1 file group, $2 group, $3 key: a value of the Global Theme's defaults
  as_root_tool kreadconfig6 --file "$DEFAULTS" --group "$1" --group "$2" --key "$3"
}
SCHEME=$(lnf kdeglobals General ColorScheme)
PLASMA_STYLE=$(lnf plasmarc Theme name)
ICONS=$(lnf kdeglobals Icons Theme)
WIDGET_STYLE=$(lnf kdeglobals KDE widgetStyle)
# Fonts and cursor: the same values as tools/device/fusion-config.sh (UI_FONT, SMALL_FONT,
# CURSOR_THEME). The Global Themes no longer carry them, so that light/dark switches keep a user's
# own choices (docs/parts/lookandfeel.md).
CURSORS=PlasmaFusion-cursors
FONT_KEYS=(font menuFont toolBarFont smallestReadableFont)
declare -A FONT=(
  [font]="Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
  [menuFont]="Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
  [toolBarFont]="Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
  [smallestReadableFont]="Manrope,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
)
[ -f "$DATA/color-schemes/$SCHEME.colors" ] || die "colour scheme $SCHEME is not installed in $DATA"
[ -f "$DATA/plasma/desktoptheme/$PLASMA_STYLE/metadata.json" ] || die "Plasma style $PLASMA_STYLE is not installed in $DATA"
[ -f "$DATA/icons/$ICONS/index.theme" ] || die "icon theme $ICONS is not installed in $DATA"
[ -f "$DATA/icons/$CURSORS/index.theme" ] || die "cursor theme $CURSORS is not installed in $DATA"
ls "$DATA"/fonts/plasma-fusion/Manrope-*.ttf >/dev/null 2>&1 || die "the Manrope fonts are not installed in $DATA/fonts/plasma-fusion"

if [ -n "$OUTPUT" ]; then
  GHOME=
  as_greeter() { "${tool_env[@]}" "$@"; }
else
  [ "$(id -u)" = 0 ] || die "run as root (or use --output DIR)"
  command -v setpriv >/dev/null || die "setpriv (util-linux) is missing"
  entry=$(getent passwd "$GREETER_USER") || die "user $GREETER_USER does not exist (is plasma-login-manager installed?)"
  GHOME=$(printf '%s' "$entry" | cut -d: -f6)
  GGROUP=$(id -gn "$GREETER_USER")
  [ -d "$GHOME" ] || die "$GREETER_USER's home $GHOME does not exist"
  # Everything inside the greeter's home is read and written as the greeter user, as the KCM's
  # helper does (no root access through links the greeter user could plant).
  as_greeter() { setpriv --reuid="$GREETER_USER" --regid="$GGROUP" --init-groups --no-new-privs -- "${tool_env[@]}" "$@"; }
fi

# The display configuration to copy. Root never opens a user's file itself: it is read by the
# file's owner (a link is refused), then checked to be KWin's output configuration.
if [ -n "$DISPLAY_FROM" ]; then
  [ ! -L "$DISPLAY_FROM" ] || die "$DISPLAY_FROM is a link; name the file itself"
  [ -f "$DISPLAY_FROM" ] || die "$DISPLAY_FROM is not a file"
  [ "$(stat -c %s "$DISPLAY_FROM")" -le 1048576 ] || die "$DISPLAY_FROM is larger than 1 MiB"
  if [ "$(id -u)" = 0 ] && [ "$(stat -c %u "$DISPLAY_FROM")" != 0 ]; then
    setpriv --reuid="$(stat -c %u "$DISPLAY_FROM")" --regid="$(stat -c %g "$DISPLAY_FROM")" --clear-groups \
      --no-new-privs -- cat -- "$DISPLAY_FROM" >"$own/kwinoutputconfig.json" || die "cannot read $DISPLAY_FROM"
  else
    cat -- "$DISPLAY_FROM" >"$own/kwinoutputconfig.json" || die "cannot read $DISPLAY_FROM"
  fi
  DISPLAY_NEW=$(display_summary <"$own/kwinoutputconfig.json") || die "$DISPLAY_FROM: not a KWin output configuration"
  CONFIG_FILES+=(kwinoutputconfig.json)
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/plasma-fusion-greeter.XXXXXX")
if [ -z "$OUTPUT" ]; then
  chown "$GREETER_USER:$GGROUP" "$work"
fi
chmod 0700 "$work"
# The same clean environment for everything run as the greeter user.
tool_env=(env -i PATH=/usr/bin:/bin HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config"
  XDG_RUNTIME_DIR="$work/run" XDG_CONFIG_DIRS=/etc/xdg XDG_DATA_DIRS="$DATA:/usr/local/share:/usr/share"
  QT_QPA_PLATFORM=offscreen LANG=C.UTF-8)
as_greeter mkdir -p "$work/home/.config" "$work/run"
as_greeter chmod 0700 "$work/run"

# The value the greeter sees: the daemon's configuration files in the order plasma-login reads
# them, the last one that sets the key wins.
effective() { # $1 group, $2 key
  local f v value=
  while IFS= read -r f; do
    [ -r "$f" ] || continue
    v=$(kr "$f" "$1" "$2")
    [ -z "$v" ] || value=$v
  done < <(conf_dir_files /etc/plasmalogin.conf.d
           echo /usr/lib/plasmalogin/defaults.conf
           conf_dir_files /usr/lib/plasmalogin/plasmalogin.conf.d
           echo "$CONF")
  printf '%s' "$value"
}


greeter_block() {
  cat <<EOF

# Plasma Fusion: login screen wallpaper (greeter-apply.sh; undo: greeter-restore.sh). Set in this
# file because it is read last: /usr/lib/plasmalogin/defaults.conf sets the wallpaper too and
# wins over /etc/plasmalogin.conf.d/. PreviewImage as well, because the image wallpaper shows
# PreviewImage instead of Image when it is set.
[Greeter]
WallpaperPlugin=org.kde.image

[Greeter][Wallpaper][org.kde.image][General]
Image=file://$IMAGE
PreviewImage=file://$IMAGE
EOF
}

# The new daemon configuration. $1 current file (may be missing), $2 output file
new_conf() {
  if [ -f "$1" ]; then cp "$1" "$2"; else : >"$2"; fi
  if grep -q '^\[Greeter\]' "$2"; then
    kw "$2" Greeter WallpaperPlugin org.kde.image
    kw "$2" "$WALLPAPER_GROUP" Image "file://$IMAGE"
    kw "$2" "$WALLPAPER_GROUP" PreviewImage "file://$IMAGE"
  else
    greeter_block >>"$2"
  fi
}

# ---------- check ----------

if [ "$CHECK" = 1 ]; then
  [ -z "$OUTPUT" ] || die "--check reads the installed greeter; do not combine it with --output"
  read_greeter() { as_greeter kreadconfig6 --file "$GHOME/.config/$1" --group "$2" --key "$3" 2>/dev/null || true; }
  ok=yes
  report() { # $1 label, $2 current, $3 wanted
    local mark=ok
    [ "$2" = "$3" ] || { mark=differs; ok=no; }
    printf '  %-20s %-40s %s\n' "$1" "${2:-<unset>}" "$mark"
  }
  say "Greeter user $GREETER_USER ($GHOME/.config):"
  report "colour scheme" "$(read_greeter kdeglobals General ColorScheme)" "$SCHEME"
  report "Global Theme" "$(read_greeter kdeglobals KDE LookAndFeelPackage)" "$LNF"
  report "Plasma style" "$(read_greeter plasmarc Theme name)" "$PLASMA_STYLE"
  report "icons" "$(read_greeter kdeglobals Icons Theme)" "$ICONS"
  report "cursors" "$(read_greeter kcminputrc Mouse cursorTheme)" "$CURSORS"
  report "font" "$(read_greeter kdeglobals General font | cut -d, -f1-2)" "$(printf '%s' "${FONT[font]}" | cut -d, -f1-2)"
  pkg=$(as_greeter cat "$GHOME/.config/kdedefaults/package" 2>/dev/null || true)
  say "  kdedefaults package: ${pkg:-<none>} (rewritten from the Global Theme at the next greeter start when it differs)"
  shown=$(as_greeter cat "$GHOME/.config/kwinoutputconfig.json" 2>/dev/null | display_summary 2>/dev/null || true)
  say "  display: ${shown:-<no kwinoutputconfig.json yet>} (the Plasma Fusion sizes are meant for the session's scale; see --display-from)"
  report "wallpaper plugin" "$(effective Greeter WallpaperPlugin)" org.kde.image
  report "wallpaper image" "$(effective "$WALLPAPER_GROUP" Image)" "file://$IMAGE"
  report "wallpaper preview" "$(effective "$WALLPAPER_GROUP" PreviewImage)" "file://$IMAGE"
  [ ! -e /etc/plasmalogin.conf.d/plasma-fusion.conf ] ||
    say "  note: /etc/plasmalogin.conf.d/plasma-fusion.conf (an earlier version of this script) has no effect; greeter-restore.sh removes it"
  say "Plasma Fusion greeter: $ok"
  [ "$ok" = yes ]
  exit
fi

# ---------- generate ----------

say "Plasma Fusion Dark for the login greeter (from $DEFAULTS):"
note "colour scheme $SCHEME, Plasma style $PLASMA_STYLE, icons $ICONS, cursors $CURSORS, widget style $WIDGET_STYLE"
note "fonts: $(for k in "${FONT_KEYS[@]}"; do printf '%s=%s ' "$k" "$(printf '%s' "${FONT[$k]}" | cut -d, -f1-2)"; done)"
note "wallpaper: $IMAGE"
[ -z "$DISPLAY_FROM" ] || note "display configuration from $DISPLAY_FROM: $DISPLAY_NEW"

# Start from the greeter's current files, so keys this script does not set are kept.
if [ -z "$OUTPUT" ]; then
  as_greeter sh -c '
    from=$1 to=$2; shift 2
    for f in "$@"; do
      if [ -f "$from/$f" ] && [ ! -L "$from/$f" ]; then cp "$from/$f" "$to/$f"; fi
    done' sh "$GHOME/.config" "$work/home/.config" "${CONFIG_FILES[@]}"
fi

cfg=$work/home/.config
# Whether the greeter uses Plasma Fusion already (recorded in the backup: greeter-restore.sh
# goes back to the newest backup from before Plasma Fusion).
BEFORE=other
if [ -z "$OUTPUT" ] &&
   [ "$(as_greeter kreadconfig6 --file "$cfg/kdeglobals" --group KDE --key LookAndFeelPackage 2>/dev/null || true)" = "$LNF" ]; then
  BEFORE=plasma-fusion
fi
write() { # $1 file, $2 group (nested with /), $3 key, $4 value
  local groups=() g
  IFS=/ read -r -a g <<<"$2"
  for part in "${g[@]}"; do groups+=(--group "$part"); done
  as_greeter kwriteconfig6 --file "$cfg/$1" "${groups[@]}" --key "$3" "$4"
}

# Colours: the same applicator System Settings uses (colour groups, [WM], ColorSchemeHash).
# Removing the scheme name first makes it apply even when the name is already set. An accent
# colour from an earlier "Apply Plasma Settings…" would tint the scheme (and the greeter has no
# wallpaper accent): removed, so the greeter shows the Plasma Fusion colours as designed.
for key in ColorScheme AccentColor accentColorFromWallpaper; do
  as_greeter kwriteconfig6 --file "$cfg/kdeglobals" --group General --key "$key" --delete
done
applied=$(as_greeter plasma-apply-colorscheme "$SCHEME" 2>&1) ||
  die "plasma-apply-colorscheme $SCHEME failed: $applied"
as_greeter kreadconfig6 --file "$cfg/kdeglobals" --group Colors:Window --key BackgroundNormal | grep -q . ||
  die "plasma-apply-colorscheme did not write the colours: $applied"
write kdeglobals KDE LookAndFeelPackage "$LNF"
write kdeglobals KDE widgetStyle "$WIDGET_STYLE"
for k in "${FONT_KEYS[@]}"; do write kdeglobals General "$k" "${FONT[$k]}"; done
write kdeglobals Icons Theme "$ICONS"
write plasmarc Theme name "$PLASMA_STYLE"
write kcminputrc Mouse cursorTheme "$CURSORS"
if [ -n "$DISPLAY_FROM" ]; then
  as_greeter sh -c 'cat >"$0"' "$cfg/kwinoutputconfig.json" <"$own/kwinoutputconfig.json"
fi
new_conf "$CONF" "$own/plasmalogin.conf"

if [ -n "$OUTPUT" ]; then
  mkdir -p "$OUTPUT/config"
  for f in "${CONFIG_FILES[@]}"; do install -m 0644 "$cfg/$f" "$OUTPUT/config/$f"; done
  install -m 0644 "$own/plasmalogin.conf" "$OUTPUT/plasmalogin.conf"
  say "Wrote $OUTPUT/config/{$(IFS=,; echo "${CONFIG_FILES[*]}")} and $OUTPUT/plasmalogin.conf"
  exit 0
fi

if [ "$DRY" = 1 ]; then
  say "Dry run: nothing is changed. Changes to $GHOME/.config:"
  for f in "${CONFIG_FILES[@]}"; do
    note "--- $f"
    as_greeter sh -c 'if [ -f "$0" ] && [ ! -L "$0" ]; then cat "$0"; fi' "$GHOME/.config/$f" |
      diff -u --label "current $f" --label "new $f" - "$cfg/$f" | sed 's/^/    /' || true
  done
  note "remove $GHOME/.cache"
  note "--- $CONF"
  { if [ -f "$CONF" ]; then cat "$CONF"; fi; } |
    diff -u --label "current $CONF" --label "new $CONF" - "$own/plasmalogin.conf" | sed 's/^/    /' || true
  exit 0
fi

# ---------- backup ----------

stamp=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP=$BACKUP_ROOT/greeter-backup-$stamp
install -d -m 0700 "$BACKUP_ROOT"
# A new directory for every run (two runs in the same second must not share one).
mkdir -m 0700 "$BACKUP" || die "$BACKUP exists already; run again"
install -d -m 0700 "$BACKUP/config" "$BACKUP/etc"
: >"$BACKUP/manifest"
# The greeter's whole ~/.config (small), streamed out by the greeter user.
if as_greeter test -d "$GHOME/.config"; then
  as_greeter tar -C "$GHOME/.config" -cf - . | tar -C "$BACKUP/config" -xpf -
fi
for f in "${CONFIG_FILES[@]}" kdedefaults; do
  if [ -e "$BACKUP/config/$f" ] || [ -L "$BACKUP/config/$f" ]; then
    echo "present config/$f" >>"$BACKUP/manifest"
  else
    echo "absent config/$f" >>"$BACKUP/manifest"
  fi
done
if [ -f "$CONF" ]; then
  cp -a "$CONF" "$BACKUP/etc/plasmalogin.conf"
  echo "present etc/plasmalogin.conf" >>"$BACKUP/manifest"
else
  echo "absent etc/plasmalogin.conf" >>"$BACKUP/manifest"
fi
{
  echo "created=$stamp"
  echo "greeter_home=$GHOME"
  echo "package=$(installed_package)"
  echo "lookandfeel=$LNF"
  echo "image=$IMAGE"
  echo "before=$BEFORE"
  [ -z "$DISPLAY_FROM" ] || echo "display_from=$DISPLAY_FROM ($DISPLAY_NEW)"
} >"$BACKUP/info"
say "backup: $BACKUP"

# ---------- install ----------

as_greeter mkdir -p "$GHOME/.config"
for f in "${CONFIG_FILES[@]}"; do
  # Write next to the target, then rename: the greeter never sees a half-written file.
  as_greeter sh -c 'cp "$0" "$1.plasma-fusion-new" && chmod 0644 "$1.plasma-fusion-new" && mv -f "$1.plasma-fusion-new" "$1"' \
    "$cfg/$f" "$GHOME/.config/$f"
  note "wrote $GHOME/.config/$f"
done
as_greeter rm -rf "$GHOME/.cache"
note "removed $GHOME/.cache (the greeter rebuilds it)"

if cmp -s "$own/plasmalogin.conf" "$CONF"; then
  note "$CONF already sets the wallpaper (unchanged)"
else
  install -m 0644 -o root -g root "$own/plasmalogin.conf" "$CONF.plasma-fusion-new"
  mv -f "$CONF.plasma-fusion-new" "$CONF"
  # What was written, so that greeter-restore.sh can tell whether the file changed since.
  cp "$own/plasmalogin.conf" "$BACKUP/etc/plasmalogin.conf.applied"
  note "wrote the wallpaper to $CONF"
fi

if command -v restorecon >/dev/null && command -v selinuxenabled >/dev/null && selinuxenabled; then
  restorecon -R "$GHOME/.config" "$CONF" || true
fi
for key in WallpaperPlugin Image PreviewImage; do
  group=$WALLPAPER_GROUP; [ "$key" = WallpaperPlugin ] && group=Greeter
  value=$(effective "$group" "$key")
  case $key in WallpaperPlugin) want=org.kde.image ;; *) want=file://$IMAGE ;; esac
  [ "$value" = "$want" ] || note "warning: the greeter reads $key=$value, not $want"
done
[ ! -e /etc/plasmalogin.conf.d/plasma-fusion.conf ] ||
  note "note: /etc/plasmalogin.conf.d/plasma-fusion.conf (an earlier version of this script) has no effect; greeter-restore.sh with its backup removes it"

say "Done. The login screen shows Plasma Fusion Dark the next time the greeter starts"
say "(after the next logout or reboot; nothing was restarted)."
say "Undo this run: $(dirname "$0")/greeter-restore.sh $BACKUP"
say "Back to the look from before Plasma Fusion: $(dirname "$0")/greeter-restore.sh"
