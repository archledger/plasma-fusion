#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Style the Plasma login greeter (plasma-login-manager 6.7) with Plasma Fusion Dark. Run as root
# after the plasma-fusion package is installed (it reads the system-wide copies in /usr/share).
#
#   greeter-apply.sh [--display-from FILE] [--dry-run] [--check]
#   greeter-apply.sh --output DIR [--data-dir DIR] [--display-from FILE]
#
#   --display-from FILE  also give the greeter this display configuration, normally the
#                   kwinoutputconfig.json of the user whose display scale it should use:
#                   sudo greeter-apply.sh --display-from ~/.config/kwinoutputconfig.json
#                   ("Apply Plasma Settings…" copies it too). The Plasma Fusion sizes are
#                   logical pixels at the session's scale (4/3 on the 1920x1200 test device);
#                   without it the greeter keeps its own scale (often 1: everything smaller)
#   --dry-run       show what would be written; change nothing
#   --check         report whether the greeter uses Plasma Fusion; change nothing
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
# (a block appended to the file while it has no [Greeter] settings, so its comments stay;
# otherwise the keys are written with kwriteconfig6, which rewrites the file as the KCM does).
# The greeter's layout is compiled into plasma-login-greeter; only its styling changes.
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

DRY=0 CHECK=0 OUTPUT='' DATA=/usr/share DISPLAY_FROM=''
usage() { sed -n '/^#   greeter-apply.sh \[/,/^#   -h, --help/p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY=1 ;;
    --check) CHECK=1 ;;
    --output) [ $# -ge 2 ] || { echo "--output needs a directory" >&2; exit 2; }; OUTPUT=$2; shift ;;
    --data-dir) [ $# -ge 2 ] || { echo "--data-dir needs a directory" >&2; exit 2; }; DATA=$(cd "$2" && pwd); shift ;;
    --display-from) [ $# -ge 2 ] || { echo "--display-from needs a file" >&2; exit 2; }; DISPLAY_FROM=$2; shift ;;
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

# ---------- preflight ----------

for tool in kreadconfig6 kwriteconfig6 plasma-apply-colorscheme; do
  command -v "$tool" >/dev/null || die "$tool is missing (plasma-workspace, kf6-kconfig)"
done
DEFAULTS=$DATA/plasma/look-and-feel/$LNF/contents/defaults
[ -f "$DEFAULTS" ] || die "Global Theme $LNF is not installed in $DATA (install the plasma-fusion package)"
IMAGE=$DATA/$BACKGROUND
[ -f "$IMAGE" ] || die "$IMAGE is missing (install the plasma-fusion package)"

# Temporary directories: $own stays the invoking user's (root's), $work (below) belongs to the
# greeter user, who runs the tools that write the greeter's files.
own=$(mktemp -d "${TMPDIR:-/tmp}/plasma-fusion-greeter.XXXXXX")
work=''
trap 'rm -rf "$own" ${work:+"$work"}' EXIT
mkdir -p "$own/home/.config" "$own/run"
chmod 0700 "$own/run"
# Every KDE tool runs offscreen with a clean environment: no session bus or display, a HOME in a
# temporary directory (KConfig wants a writable ~/.config, or it pops up an error dialog) and only
# the system-wide data.
as_root_tool() { env -i PATH=/usr/bin:/bin HOME="$own/home" XDG_CONFIG_HOME="$own/home/.config" \
  XDG_RUNTIME_DIR="$own/run" XDG_CONFIG_DIRS=/etc/xdg QT_QPA_PLATFORM=offscreen LANG=C.UTF-8 "$@"; }

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

# The files of a configuration directory as plasma-login lists them (QDir::Files: no hidden
# files, links to files included), sorted.
conf_dir_files() { # $1 directory
  [ -d "$1" ] || return 0
  find "$1" -mindepth 1 -maxdepth 1 ! -name '.*' -xtype f -print 2>/dev/null | LC_ALL=C sort
}
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
