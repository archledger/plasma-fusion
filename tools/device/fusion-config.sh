#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Configure the running Plasma session for Plasma Fusion: everything the Global Theme itself
# cannot set. Run it inside the user's session (a terminal in the session, or over SSH with the
# session's DBUS_SESSION_BUS_ADDRESS and XDG_RUNTIME_DIR), after the Plasma Fusion packages are
# installed in ~/.local/share (or /usr/share).
#
#   fusion-config.sh [options]
#
#   --install DIR      first copy the built HOME tree DIR (tools/build.sh output, e.g.
#                      stage/home) into this HOME, after the backup: DIR/.local is copied over
#                      ~/.local; DIR/.config files are copied, except that an existing gtk.css
#                      with more than Plasma's colors.css import only gets the Plasma Fusion
#                      import added
#   --dry-run          print every change it would make, change nothing (no backup either)
#   --light            apply Plasma Fusion Light
#   --dark             apply Plasma Fusion Dark
#   --auto             switch between Light and Dark with the time of day ("Follow sunset")
#   --no-auto          stop that switching
#                      (without these a HOME already on Plasma Fusion keeps its variant and its
#                      automatic switching; any other HOME gets Dark without switching)
#   --reset-layout     always rebuild the top bar, dock and desktop cards
#   --keep-layout      never touch the panels (appearance and settings only)
#   --hot-corner       let the top-left screen corner open Overview (off by default)
#   --fonts            set the Plasma Fusion fonts and cursor again (normally only the first
#                      run sets them, so the user's own later choices are kept)
#   --pen              pen defaults (tools/pen/pen-defaults.sh, without installing packages) and
#                      Meta+Shift+W for the pen widget
#   --pen-garage       with --pen: also install and enable plasma-fusion-pen-garage.service (only
#                      after hand check V2 showed that the laptop reports the pen's garage)
#   --screens          run the Global Theme's ensure-topbars.js: a top bar on every screen
#   --shortcuts        apply the Windows-style shortcut set again (normally once per config version)
#   --keep-shortcuts   do not apply the Windows-style shortcut set (Meta+N stays quick settings)
#   -h, --help
#
# By default the layout is rebuilt only when the current panels are not the Plasma Fusion
# layout; an existing Plasma Fusion layout is migrated in place (panels, pins and cards kept).
# Running it twice gives the same result. Before changing anything it copies every
# file it may touch, plus the virtual desktops and shortcuts it changes, to
# ~/.local/state/plasma-fusion/backup-<UTC timestamp>/; tools/device/fusion-restore.sh puts
# that back.
#
# Upgrades (plasmafusionrc [Config] FusionConfigVersion): on a HOME that an earlier Plasma Fusion
# configured, a setting is changed only while it still holds a value an earlier Plasma Fusion wrote
# (or is unset); a value the user chose is kept. The changes and the kept values of an upgrade are
# listed in ~/.local/state/plasma-fusion/config-changes (docs/parts/device.md).
#
# What it sets (see docs/parts/lookandfeel.md for the reasons):
#   Fonts, cursor      first run only (plasmafusionrc [Setup] FontsAndCursor): kdeglobals
#                      [General] font, menuFont, toolBarFont Manrope 9.75, smallestReadableFont
#                      Manrope 9, [WM] activeFont Manrope ExtraBold 10.5; cursor theme
#                      PlasmaFusion-cursors (plasma-apply-cursortheme). The Global Themes carry
#                      neither, so light/dark switches keep the user's own fonts and cursor.
#   Global Theme       plasma-apply-lookandfeel -a org.plasmafusion.{dark,light}.desktop
#                      [--resetLayout]; kdeglobals [KDE] DefaultDarkLookAndFeel,
#                      DefaultLightLookAndFeel, AutomaticLookAndFeel
#   Top bar pop-ups    plasmashellrc [PlasmaViews][Panel <top bar id>] floatingApplets 1 (stock
#                      pop-ups float under the bar with rounded corners; read at shell start)
#   Quick settings     Meta+A opens the quick-settings pop-up (Meta+N with --keep-shortcuts):
#                      set when the widget has no key yet or still the earlier Plasma Fusion one
#                      (the dead entry of a widget dropped by an earlier layout rebuild is removed
#                      first); a key the user chose is kept
#   Workspaces         four virtual desktops Work, Design, Media, Chat in one row
#   Shortcuts          Meta+1..4 switch workspace (added to "Switch to Desktop 1..4", removed
#                      from "activate task manager entry 1..4")
#   Window switcher    kwinrc [TabBox] and [TabBoxAlternative] LayoutName, DesktopMode 0 (the
#                      switcher has its own "This workspace / All workspaces" tabs),
#                      HighlightWindows false
#   Overview           kwinrc [Effect-overview] BorderActivate 9 (hot corner off) or 7
#   Tiling             6 px padding on every screen and workspace; the untouched default
#                      25/50/25 layout gets its right column split top/bottom
#   Blur               kwinrc [Effect-blur] BlurStrength 13, NoiseStrength 0, Saturation 140
#   Title bar          kwinrc [org.kde.kdecoration2] BorderSizeAuto false (theme border size)
#   KWin scripts       kwinrc [Plugins] plasmafusion-snapEnabled, plasmafusion-attachEnabled,
#                      sheetEnabled; [Outline] QmlPath (snap-zone preview of plasmafusion-snap)
#   Lock screen        tools/device/lockscreen-enable.sh (org.plasmafusion.lockshell);
#                      kscreenlockerrc [Greeter] wallpaper PlasmaFusion
#   Tooltips           plasmarc [PlasmaToolTips] Delay 300
#   OSD                plasmarc [OSD] Enabled, kbdLayoutChangedEnabled
#   Notifications      plasmanotifyrc [Notifications] PopupPosition TopRight, PopupTimeout 5000;
#                      [Jobs] PermanentPopups false (file-copy progress pop-ups close after the
#                      timeout; the progress stays in the notification list; research D-desktop)
#   KRunner            krunnerrc [General] FreeFloating true (centred, as the dock's Search)
#   Desktop (in place) an existing Plasma Fusion layout: the "Desktop" containment becomes Folder
#                      View (desktop icons) with the Plasma Fusion keys, portrait card positions,
#                      top bar solid next to maximized windows, tray items hidden, the app menu
#                      only for its own screen, the pen widget added to the top bar
#   Shortcuts (Windows set, once per version) Meta+Space, Meta+S, Alt+Space, Alt+F2 and Search:
#                      the launcher (KRunner's keys move there); Meta+A quick settings; Meta+N the
#                      notification list; Meta+Up / Meta+Down maximize / restore (quick tile top /
#                      bottom move to Meta+Alt+Up/Down); Meta+Tab Overview; Meta+Alt+1..9 dock apps;
#                      every other holder of these keys loses them
#   Window switcher    kwinrc [TabBox] DelayTime 120 (a quick Alt+Tab shows no switcher)
#   KWin tablet        kwinrc [Plugins] plasmafusion-tabletEnabled; plasmafusion_navigationEnabled
#                      (the compiled tablet navigation effect, when its package is installed)
#   On-screen keyboard kwinrc [Wayland] InputMethod empty in laptop posture (quick settings writes it
#                      from then on); plasmakeyboardrc [General] diacriticsPopupEnabled false (no
#                      accent pop-up on a held physical key)
#   Text rendering     greyscale antialiasing, slight hinting: ~/.config/fontconfig/fonts.conf and
#                      kdeglobals [General] Xft* as System Settings > Fonts writes them (GTK too)
#   Session env        ~/.config/plasma-workspace/env/plasma-fusion-session.sh, from the next
#                      login: GTK_USE_PORTAL=1 (GTK file dialogs through the portal: KDE's) and
#                      QSG_DISTANCEFIELD_ANTIALIASING=gray (greyscale Qt Quick text)
#   Power tiers        plasma-fusion-powerfx.service installed, enabled and started
#   App icons          plasma-fusion-app-icons.service installed, enabled and started: every app's
#                      own icon on a Fusion tile in ~/.local/share/icons/PlasmaFusion{,-Dark}
#   LibreOffice        ~/.local/bin/libreoffice -> plasma-fusion-libreoffice (XWayland only while a screen
#                      at 100 % sits next to a scaled one, tdf#141578) and the hidden soffice.desktop
#   Terminal, editor   konsolerc default profile "Plasma Fusion"; katerc/kwriterc colour theme
#                      "Plasma Fusion Dark" (the boards draw a dark terminal and code window in
#                      both variants)
#   Previous look      only while it does not exist yet: the look from before Plasma Fusion (the
#                      newest backup taken under another Global Theme) saved as the Global Theme
#                      "My previous desktop", org.plasmafusion.previous.desktop
#                      (tools/device/previous-theme.py)
#   Login check        tools/device/gate/plasma-fusion-gate.sh as
#                      ~/.local/share/plasma-fusion/gate/plasma-fusion-gate.sh, its env stub
#                      ~/.config/plasma-workspace/env/plasma-fusion-gate.sh and
#                      plasma-fusion-gate-notify.service; then records the installed Plasma
#                      versions and lock-screen files as tested and turns back on what a login
#                      switched off (docs/parts/gate.md)
set -euo pipefail

DARK=org.plasmafusion.dark.desktop
LIGHT=org.plasmafusion.light.desktop
SWITCHER=org.plasmafusion.switcher
KWIN_SCRIPTS=(plasmafusion-snap plasmafusion-attach plasmafusion-tablet)
DESKTOP_NAMES=(Work Design Media Chat)
TILE_PADDING=6
BLUR_STRENGTH=13
BLUR_NOISE=0
BLUR_SATURATION=140
TOOLTIP_DELAY=300
# Alt+Tab shows the switcher only when Alt is held this long (KWin's default is 90 ms).
TABBOX_DELAY=120
# plasmafusionrc [Config] FusionConfigVersion written by this script. 1: every release before it
# (0918220 to d4afee8), which wrote no version.
CONFIG_VERSION=2
# Fonts and cursor (set once, see section 1b). Manrope 13 px for text, menus and toolbars,
# 12 px for the smallest readable text, window titles Manrope ExtraBold 14 px.
UI_FONT=Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0
SMALL_FONT=Manrope,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0
TITLE_FONT=Manrope,10.5,-1,5,800,0,0,0,0,0,0,0,0,0,0,1,,0,0
CURSOR_THEME=PlasmaFusion-cursors
NOTIFICATION_TIMEOUT=5000
# Qt key codes (modifiers | key).
META=$((0x10000000)) ALT=$((0x08000000)) SHIFT=$((0x02000000))
K_SPACE=$((0x20)) K_TAB=$((0x01000001)) K_UP=$((0x01000013)) K_DOWN=$((0x01000015)) K_F2=$((0x01000031))
# Global shortcut for the quick-settings pop-up (org.plasmafusion.quicksettings): Qt key code and
# QKeySequence text. The Windows-style set (owner decision 6) gives it Meta+A and Meta+N opens it on
# the notification list; without that set (--keep-shortcuts) it keeps Meta+N, as before.
QS_OLD_SHORTCUT=$((META + 0x4e))
QS_OLD_SHORTCUT_TEXT=Meta+N
QS_SHORTCUT=$((META + 0x41))
QS_SHORTCUT_TEXT=Meta+A
# Pen menu widget (org.plasmafusion.pen), with --pen.
PEN_WIDGET=org.plasmafusion.pen
# The desktop containment (TABLET2 H1); the layout migration names it when it is installed.
DESKTOP_CONTAINMENT=org.plasmafusion.desktop
PEN_SHORTCUT=$((META + SHIFT + 0x57))
PEN_SHORTCUT_TEXT=Meta+Shift+W
# Meta+N: a kglobalaccel service component (a desktop file in ~/.local/share/kglobalaccel/, the way
# System Settings adds a command shortcut) that asks the quick-settings widget to open on its
# notification list: it writes the widget's [General] openRequest = "notifications:<ms>".
NOTIFY_COMPONENT=org.plasmafusion.notifications.desktop
NOTIFY_SHORTCUT=$((META + 0x4e))
LAUNCHER_ACTION="activate application launcher"
# The on-screen keyboard (plasma-keyboard) as kwinrc [Wayland] InputMethod names it on Fedora;
# section 4 takes the copy in the system data directories (XDG_DATA_DIRS) where there is one.
OSK_DESKTOP=/usr/share/applications/org.kde.plasma.keyboard.desktop
# Window switcher: KWin hands every window to org.plasmafusion.switcher (DesktopMode 0), which
# opens on "This workspace" and filters the list itself; its "All workspaces" tab needs the
# full list. Alt+Tab and Meta+Tab keep KWin's defaults (both "Walk Through Windows").
TABBOX_DESKTOP_MODE=0
TABBOX_ALT_DESKTOP_MODE=0
OUTLINE_QML=kwin/scripts/plasmafusion-snap/contents/outline/outline.qml
LOCKSHELL=org.plasmafusion.lockshell
WALLPAPER=PlasmaFusion
KONSOLE_PROFILE="Plasma Fusion.profile"
EDITOR_THEME="Plasma Fusion Dark"
PREVIOUS_LNF=org.plasmafusion.previous.desktop
GATE_UNIT_NAME=plasma-fusion-gate-notify.service
GATE_STUB_REL=plasma-workspace/env/plasma-fusion-gate.sh
GATE_UNIT_REL=systemd/user/$GATE_UNIT_NAME
GATE_WANTS_REL=systemd/user/xdg-desktop-autostart.target.wants/$GATE_UNIT_NAME
SESSION_WANTS_REL=systemd/user/graphical-session.target.wants
SESSION_ENV_REL=plasma-workspace/env/plasma-fusion-session.sh

DRY=0 VARIANT='' AUTO='' LAYOUT=auto HOT_CORNER=0 FONTS=0 INSTALL=
PEN=0 PEN_GARAGE=0 SCREENS=0 SHORTCUTS=auto
usage() { sed -n '/^#   fusion-config.sh/,/^#   -h/p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case $1 in
    --install)
      [ $# -ge 2 ] || { echo "--install needs a directory" >&2; exit 2; }
      INSTALL=$(cd "$2" && pwd) || exit 2
      shift ;;
    --dry-run) DRY=1 ;;
    --light) VARIANT=light ;;
    --dark) VARIANT=dark ;;
    --auto) AUTO=1 ;;
    --no-auto) AUTO=0 ;;
    --reset-layout) LAYOUT=reset ;;
    --keep-layout) LAYOUT=keep ;;
    --hot-corner) HOT_CORNER=1 ;;
    --fonts) FONTS=1 ;;
    --pen) PEN=1 ;;
    --pen-garage) PEN_GARAGE=1 ;;
    --screens) SCREENS=1 ;;
    --shortcuts) SHORTCUTS=apply ;;
    --keep-shortcuts) SHORTCUTS=keep ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[ "$PEN_GARAGE" = 0 ] || [ "$PEN" = 1 ] || { echo "--pen-garage needs --pen" >&2; exit 2; }
# A later run (a package update) keeps the user's light, dark or automatic choice.
current_lnf=$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage 2>/dev/null || true)
if [ -z "$VARIANT" ]; then
  [ "$current_lnf" = "$LIGHT" ] && VARIANT=light || VARIANT=dark
fi
if [ -z "$AUTO" ]; then
  AUTO=0
  if [ "$current_lnf" = "$DARK" ] || [ "$current_lnf" = "$LIGHT" ]; then
    [ "$(kreadconfig6 --file kdeglobals --group KDE --key AutomaticLookAndFeel 2>/dev/null || true)" = true ] && AUTO=1
  fi
fi
[ "$VARIANT" = light ] && LNF=$LIGHT || LNF=$DARK
HERE=$(cd "$(dirname "$0")" && pwd)

CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/plasma-fusion
# Plasma Fusion's helper programs: the user's copy (--install) first, then a system package's
# (/usr/lib/plasma-fusion where the distribution has no /usr/libexec, such as Arch; the system
# profile on NixOS).
HELPER_DIRS=("$HOME/.local/libexec/plasma-fusion" /usr/local/libexec/plasma-fusion /usr/libexec/plasma-fusion /usr/lib/plasma-fusion
  /run/current-system/sw/libexec/plasma-fusion)
helper_path() { # $1 program name: prints the first installed copy
  local d
  for d in "${HELPER_DIRS[@]}"; do
    [ -x "$d/$1" ] && { echo "$d/$1"; return 0; }
  done
  return 1
}
# The keyboard keys tool; found again after --install copied the build (section 4).
KEYS_TOOL=${HELPER_DIRS[0]}/plasma-fusion-keyboard-keys
BACKUP=
CHANGES=0

say() { printf '%s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die() { printf 'fusion-config: %s\n' "$*" >&2; exit 1; }

# ---------- preflight ----------

for tool in kreadconfig6 kwriteconfig6 busctl python3 plasma-apply-lookandfeel; do
  command -v "$tool" >/dev/null || die "$tool is missing"
done
[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ] ||
  die "no session bus: run this inside the Plasma session (or export DBUS_SESSION_BUS_ADDRESS)"
bus() { busctl --user "$@"; }
bus_json() { busctl --user --json=short "$@"; }
has_name() { bus call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameHasOwner s "$1" 2>/dev/null | grep -q true; }
has_name org.kde.KWin || die "KWin is not running on this session bus"
has_name org.kde.kglobalaccel || die "kglobalaccel is not running on this session bus"

# Run from outside the session (SSH with the session bus, with or without WAYLAND_DISPLAY): the
# Qt tools need the session's display, and the configuration cascade its XDG_CONFIG_DIRS (with
# ~/.config/kdedefaults, which startplasma always adds), so take them from the running
# plasmashell. Without the kdedefaults layer every key a Global Theme set would read as unset.
# Without a plasmashell, Qt tools run offscreen.
OUTSIDE=0
if [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] || [[ ":${XDG_CONFIG_DIRS:-}:" != *"/kdedefaults:"* ]]; then
  OUTSIDE=1
  shell_pid=$(bus call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.kde.plasmashell 2>/dev/null | awk '{print $2}')
  if [ -n "$shell_pid" ] && [ -r "/proc/$shell_pid/environ" ]; then
    while IFS= read -r -d '' kv; do
      case ${kv%%=*} in
        WAYLAND_DISPLAY|DISPLAY|XAUTHORITY|XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP|XDG_CONFIG_DIRS|XDG_DATA_DIRS|KDE_FULL_SESSION|KDE_SESSION_VERSION|QT_QPA_PLATFORM)
          export "${kv?}" ;;
      esac
    done <"/proc/$shell_pid/environ"
  fi
  [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] || export QT_QPA_PLATFORM=offscreen
  [[ ":${XDG_CONFIG_DIRS:-}:" == *"/kdedefaults:"* ]] ||
    echo "fusion-config: note: no running plasmashell to take XDG_CONFIG_DIRS from; values from ~/.config/kdedefaults read as unset" >&2
fi

package_dir() { # $1 type dir (plasma/look-and-feel, kwin/scripts...), $2 id
  local d
  # shellcheck disable=SC2086
  for d in "$DATA" ${INSTALL:+"$INSTALL/.local/share"} ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
    for base in ${d//:/ }; do
      [ -e "$base/$1/$2/metadata.json" ] && { echo "$base/$1/$2"; return 0; }
    done
  done
  return 1
}
# Where a data file is, or will be after --install: the user's data directory first, then the
# system's (the plasma-fusion package installs everything below /usr/share).
data_path() { # $1 path relative to a data directory
  local d base
  if [ -e "$DATA/$1" ] || { [ -n "$INSTALL" ] && [ -e "$INSTALL/.local/share/$1" ]; }; then
    echo "$DATA/$1"
    return 0
  fi
  # shellcheck disable=SC2086
  for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
    for base in ${d//:/ }; do
      [ -e "$base/$1" ] && { echo "$base/$1"; return 0; }
    done
  done
  return 1
}
# A path in the system's data directories only (XDG_DATA_DIRS: /usr/share on Fedora, the system
# profile on NixOS), never the user's own. $1 path relative to a data directory
system_data_path() {
  local d dirs
  IFS=: read -r -a dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  for d in "${dirs[@]}"; do
    [[ $d == /* ]] && [ -e "$d/$1" ] && { echo "$d/$1"; return 0; }
  done
  return 1
}
# LibreOffice itself in PATH (/usr/bin on Fedora), not Plasma Fusion's ~/.local/bin guard.
libreoffice_installed() {
  local d dirs
  IFS=: read -r -a dirs <<<"${PATH:-}"
  for d in "${dirs[@]}" /usr/bin; do
    [ -n "$d" ] && [ -x "$d/libreoffice" ] || continue
    [[ $(readlink -f "$d/libreoffice") == */plasma-fusion-libreoffice ]] || return 0
  done
  return 1
}
# Per-user configuration files (GTK stylesheets): from the build with --install, otherwise the
# templates of a system-wide install (/usr/share/plasma-fusion/config).
CONFIG_SRC=
if [ -n "$INSTALL" ]; then
  [ ! -d "$INSTALL/.config" ] || CONFIG_SRC=$INSTALL/.config
else
  CONFIG_SRC=$(data_path plasma-fusion/config) || CONFIG_SRC=
fi
if [ -n "$INSTALL" ]; then
  [ -f "$INSTALL/.local/share/plasma/look-and-feel/$LNF/metadata.json" ] ||
    die "$INSTALL is not a Plasma Fusion build (no .local/share/plasma/look-and-feel/$LNF)"
else
  package_dir plasma/look-and-feel "$LNF" >/dev/null ||
    die "Global Theme $LNF is not installed (run with --install stage/home, or copy the build first)"
fi

# The configuration version this HOME has (0: never configured by Plasma Fusion; 1: an earlier
# release, which wrote no version but left its Global Theme or its fonts marker).
PREV_VERSION=$(kreadconfig6 --file plasmafusionrc --group Config --key FusionConfigVersion 2>/dev/null || true)
if ! [[ $PREV_VERSION =~ ^[0-9]+$ ]]; then
  PREV_VERSION=0
  if [[ $(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage) == org.plasmafusion.* ]] ||
    [ "$(kreadconfig6 --file plasmafusionrc --group Setup --key FontsAndCursor)" = "done" ]; then
    PREV_VERSION=1
  fi
fi
# The Windows-style shortcut set: once per configuration version, unless asked.
case $SHORTCUTS in
  apply) WINDOWS_SET=1 ;;
  keep) WINDOWS_SET=0 ;;
  *) [ "$PREV_VERSION" -lt "$CONFIG_VERSION" ] && WINDOWS_SET=1 || WINDOWS_SET=0 ;;
esac

# ---------- backup ----------

BACKUP_FILES=(
  kdeglobals kwinrc kglobalshortcutsrc plasmarc plasmanotifyrc plasmashellrc
  plasma-org.kde.plasma.desktop-appletsrc ksplashrc kcminputrc krunnerrc kscreenlockerrc
  konsolerc katerc kwriterc plasmafusionrc plasmakeyboardrc powerdevilrc
  gtk-3.0/settings.ini gtk-4.0/settings.ini xsettingsd/xsettingsd.conf Trolltech.conf
  gtk-3.0/gtk.css gtk-4.0/gtk.css gtk-3.0/plasma-fusion.css gtk-4.0/plasma-fusion.css
  systemd/user/plasma-kwin_wayland.service.d/plasma-fusion-lockscreen.conf
  "$GATE_STUB_REL" "$GATE_UNIT_REL" "$GATE_WANTS_REL"
  fontconfig/fonts.conf "$SESSION_ENV_REL"
  systemd/user/plasma-fusion-powerfx.service "$SESSION_WANTS_REL/plasma-fusion-powerfx.service"
  systemd/user/plasma-fusion-pen-garage.service "$SESSION_WANTS_REL/plasma-fusion-pen-garage.service"
  systemd/user/plasma-fusion-app-icons.service "$SESSION_WANTS_REL/plasma-fusion-app-icons.service"
)
# Files below $HOME outside ~/.config (restored or removed the same way).
LO_GUARD_REL=.local/bin/libreoffice
LO_ENTRY_REL=.local/share/applications/soffice.desktop
BACKUP_HOME=(".local/share/kglobalaccel/$NOTIFY_COMPONENT" .local/libexec/plasma-fusion "$LO_GUARD_REL" "$LO_ENTRY_REL")
# Configuration files the build or the system templates would install are saved as well.
if [ -n "$CONFIG_SRC" ]; then
  while IFS= read -r -d '' f; do
    f=${f#"$CONFIG_SRC/"}
    case " ${BACKUP_FILES[*]} " in *" $f "*) ;; *) BACKUP_FILES+=("$f") ;; esac
  done < <(find "$CONFIG_SRC" -type f -print0 | sort -z)
fi
BACKUP_DIRS=(kdedefaults)

make_backup() {
  local stamp f
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  BACKUP=$STATE/backup-$stamp
  mkdir -p "$BACKUP/config"
  : >"$BACKUP/manifest"
  for f in "${BACKUP_FILES[@]}" "${BACKUP_DIRS[@]}"; do
    if [ -e "$CONFIG/$f" ]; then
      mkdir -p "$BACKUP/config/$(dirname "$f")"
      cp -a "$CONFIG/$f" "$BACKUP/config/$f"
      echo "present $f" >>"$BACKUP/manifest"
    else
      echo "absent $f" >>"$BACKUP/manifest"
    fi
  done
  if [ -e "$HOME/.gtkrc-2.0" ]; then cp -a "$HOME/.gtkrc-2.0" "$BACKUP/gtkrc-2.0"; echo "present-home .gtkrc-2.0" >>"$BACKUP/manifest";
  else echo "absent-home .gtkrc-2.0" >>"$BACKUP/manifest"; fi
  for f in "${BACKUP_HOME[@]}"; do
    if [ -e "$HOME/$f" ] || [ -L "$HOME/$f" ]; then
      mkdir -p "$BACKUP/home/$(dirname "$f")"
      cp -a "$HOME/$f" "$BACKUP/home/$f"
      echo "present-file $f" >>"$BACKUP/manifest"
    else
      echo "absent-file $f" >>"$BACKUP/manifest"
    fi
  done
  {
    echo "created=$stamp"
    echo "lookandfeel=$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)"
    echo "automatic=$(kreadconfig6 --file kdeglobals --group KDE --key AutomaticLookAndFeel)"
    echo "variant=$VARIANT"
    echo "config-version=$PREV_VERSION"
  } >"$BACKUP/info"
  bus_json get-property org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager desktops >"$BACKUP/desktops.json"
  bus get-property org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager rows | awk '{print $2}' >"$BACKUP/rows"
  : >"$BACKUP/shortcuts"
  : >"$BACKUP/created-desktops"
  # Values of kwinrc [Wayland] InputMethod and the user services as they were, for fusion-restore.sh,
  # which has to tell KWin and systemd (a restored file alone changes neither).
  : >"$BACKUP/services"
  say "backup: $BACKUP"
}

# ---------- helpers ----------

# Human-readable key names for Qt key codes (printing only).
keyname() {
  python3 - "$@" <<'PY'
import sys
mods = [(0x10000000, "Meta"), (0x04000000, "Ctrl"), (0x08000000, "Alt"), (0x02000000, "Shift")]
special = {0x01000001: "Tab", 0x01000002: "Backtab", 0x60: "`", 0x7e: "~", 0x20: "Space",
           0x01000003: "Backspace", 0x01000012: "Left", 0x01000013: "Up", 0x01000014: "Right",
           0x01000015: "Down", 0x01000016: "PgUp", 0x01000017: "PgDown", 0x01000092: "Search"}
out = []
for arg in sys.argv[1:]:
    k = int(arg)
    parts = [n for m, n in mods if k & m]
    key = k & ~0xFE000000
    if key in special:
        parts.append(special[key])
    elif 0x01000030 <= key <= 0x01000052:
        parts.append("F%d" % (key - 0x01000030 + 1))
    elif 0x20 < key < 0x7f:
        parts.append(chr(key).upper())
    else:
        parts.append(hex(key))
    out.append("+".join(parts))
print(", ".join(out) if out else "none")
PY
}

# Read one config key as the session sees it (user file over kdedefaults and the system files).
# REPLY = the value, or $UNSET when no layer sets it. $1 file, $2 group (nested groups separated by
# "/"), $3 key
UNSET=__plasma_fusion_unset__
# The compiled Plasma Fusion decoration (plasma-fusion-decoration) as KWin would find it.
cpp_decoration_installed() {
  local d dirs
  IFS=: read -r -a dirs <<<"${QT_PLUGIN_PATH:-}"
  for d in "${dirs[@]}" /usr/lib64/qt6/plugins /usr/lib/qt6/plugins /usr/lib/x86_64-linux-gnu/qt6/plugins /run/current-system/sw/lib/qt-6/plugins; do
    [ -n "$d" ] && [ -f "$d/org.kde.kdecoration3/org.plasmafusion.decoration.so" ] && return 0
  done
  return 1
}
read_key() {
  local g groups=() part
  IFS=/ read -r -a g <<<"$2"
  for part in "${g[@]}"; do groups+=(--group "$part"); done
  REPLY=$(kreadconfig6 --file "$1" "${groups[@]}" --key "$3" --default "$UNSET" 2>/dev/null) || REPLY=$UNSET
}
show() { [ "$1" = "$UNSET" ] && printf '<unset>' || printf '%s' "${1:-<empty>}"; }

# Set one config key if it differs. $1 file, $2 group (nested groups separated by "/"),
# $3 key, $4 value
set_key() {
  local cur g groups=() part
  IFS=/ read -r -a g <<<"$2"
  for part in "${g[@]}"; do groups+=(--group "$part"); done
  read_key "$1" "$2" "$3"
  cur=$REPLY
  if [ "$cur" = "$4" ]; then
    note "$1 [${2//\//][}] $3 = $(show "$4") (unchanged)"
    return 0
  fi
  note "$1 [${2//\//][}] $3: $(show "$cur") -> $(show "$4")"
  CHANGES=$((CHANGES + 1))
  [ "$DRY" = 1 ] || kwriteconfig6 --file "$1" "${groups[@]}" --key "$3" --notify -- "$4"
}

# A setting under the upgrade rule (BACKLOG S11): set on a first run; on a HOME an earlier Plasma
# Fusion configured, only while it is unset or still holds a value an earlier release wrote
# (PREVIOUS); a value the user chose is kept. Upgrades list both in config-changes.
# $1 file, $2 group, $3 key, $4 value, $5... previous Plasma Fusion values
managed_key() {
  local file=$1 group=$2 key=$3 new=$4 cur ok=0 p
  shift 4
  read_key "$file" "$group" "$key"
  cur=$REPLY
  if [ "$cur" = "$new" ]; then
    set_key "$file" "$group" "$key" "$new"
    return 0
  fi
  { [ "$PREV_VERSION" = 0 ] || [ "$cur" = "$UNSET" ]; } && ok=1
  for p in "$@"; do [ "$cur" = "$p" ] && ok=1; done
  if [ "$ok" = 1 ]; then
    set_key "$file" "$group" "$key" "$new"
    upgrade_log changed "$file" "$group" "$key" "$cur" "$new"
  else
    note "$file [${group//\//][}] $key = $(show "$cur") (kept: the user's value; Plasma Fusion's is $(show "$new"))"
    upgrade_log kept "$file" "$group" "$key" "$cur" "$new"
  fi
}
UPGRADE_LOG=()
upgrade_log() { # STATUS FILE GROUP KEY OLD NEW (only for an upgrade from an earlier version)
  [ "$PREV_VERSION" -gt 0 ] && [ "$PREV_VERSION" -lt "$CONFIG_VERSION" ] || return 0
  local IFS=$'\t'
  UPGRADE_LOG+=("$*")
}

# kglobalaccel reads a key sequence as a structure of exactly four key codes (KF6 GlobalAccel's
# QKeySequence demarshaller), so every "(ai)" argument below carries four, unused ones 0. With fewer,
# libdbus fails a check while KWin reads the call; where libdbus makes its checks fatal (Ubuntu 26.10)
# KWin aborts, and with it the session (release-test VM, 2026-10-03).

# Current keys of a global shortcut as Qt key codes. $1 component, $2 action
shortcut_get() {
  bus_json call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel shortcut as 4 "$1" "$2" "" "" 2>/dev/null |
    python3 -c 'import json,sys; print(" ".join(str(k) for k in json.load(sys.stdin)["data"][0]))' 2>/dev/null || true
}

# Give a global shortcut exactly the keys listed (none when empty). $1 component, $2 action, $3.. keys
shortcut_set() {
  local comp=$1 action=$2 cur want
  shift 2
  cur=$(shortcut_get "$comp" "$action")
  want="$*"
  # kglobalaccel may list the same keys in another order.
  # shellcheck disable=SC2086
  if [ "$(printf '%s\n' $cur | sort)" = "$(printf '%s\n' $want | sort)" ]; then
    # shellcheck disable=SC2086
    note "shortcut $comp / $action = $(keyname $cur) (unchanged)"
    return 0
  fi
  # shellcheck disable=SC2086
  note "shortcut $comp / $action: $(keyname $cur) -> $(keyname $want)"
  CHANGES=$((CHANGES + 1))
  [ "$DRY" = 1 ] && return 0
  printf '%s\t%s\t%s\n' "$comp" "$action" "$cur" >>"$BACKUP/shortcuts"
  bus call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel setForeignShortcut asai 4 "$comp" "$action" "" "" $# "$@" >/dev/null
}

# Add one key to a global shortcut (keeping its other keys). $1 component, $2 action, $3 key
shortcut_add() {
  local cur k keys=()
  cur=$(shortcut_get "$1" "$2")
  for k in $cur; do [ "$k" = "$3" ] || keys+=("$k"); done
  shortcut_set "$1" "$2" "$3" "${keys[@]}"
}

# Remove one key from a global shortcut (keeping its other keys). $1 component, $2 action, $3 key
shortcut_remove() {
  local cur k keys=()
  cur=$(shortcut_get "$1" "$2")
  for k in $cur; do [ "$k" = "$3" ] || keys+=("$k"); done
  shortcut_set "$1" "$2" "${keys[@]}"
}

plasmashell_eval() { # $1 script; prints the script's print() output
  bus call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$1" 2>/dev/null |
    python3 -c 'import sys,shlex; s=sys.stdin.read().strip(); print(shlex.split(s[2:])[0] if s.startswith("s ") else "")'
}

# The Plasma Fusion layout is in place when plasmashell shows a full-width top panel and a
# floating, fit-content bottom panel (the shape its layout script builds).
fusion_layout_present() {
  has_name org.kde.plasmashell || return 1
  [ "$(plasmashell_eval '
var top = false, dock = false, ps = panels();
for (var i = 0; i < ps.length; i++) {
    if (ps[i].location === "top" && ps[i].lengthMode === "fill") top = true;
    if (ps[i].location === "bottom" && ps[i].floating && ps[i].lengthMode === "fit") dock = true;
}
print(top && dock ? "yes" : "no");')" = yes ]
}

apply_lnf() {
  # krdb and the GTK bridge complain about X11 displays on a Wayland-only session; drop that.
  plasma-apply-lookandfeel "$@" >/dev/null 2> >(grep -v -e "Can't open display" -e "xcb_connect() failed" >&2 || true)
}

wait_panels() { # $1 minimum number of panels; prints how many there are
  local n=0
  for _ in $(seq 1 40); do
    n=$(plasmashell_eval 'print(panels().length)' || true)
    [ "${n:-0}" -ge "$1" ] 2>/dev/null && break
    sleep 0.5
  done
  echo "${n:-0}"
}

# True when plasmashell on this session bus is the one systemd runs as plasma-plasmashell.service
# (a normal Plasma login), so restarting that unit restarts this session's shell and no other.
shell_is_systemd_unit() {
  local pid unit_pid
  pid=$(bus call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.kde.plasmashell 2>/dev/null | awk '{print $2}')
  unit_pid=$(systemctl --user show -p MainPID --value plasma-plasmashell.service 2>/dev/null || true)
  [ -n "$pid" ] && [ "$pid" = "$unit_pid" ]
}

# Stop plasmashell (it writes its layout when it quits), so its files can be edited, and start it
# again. The systemd unit when it is this session's shell; otherwise kquitapp6, and the new shell
# gets this script's environment (from a terminal in the session) or the environment of the shell
# it replaces (run from outside the session, SSH).
# Before plasmashell is stopped: let it finish what the last change started. A shell stopped while its
# render thread still compiles the shaders of a new theme can crash on exit (Mesa's software
# renderer, llvmpipe, in VMs; 2026-10-03). Waits until the shell has used under 6 % of a core for a
# second, at most 20 s; with a GPU driver it returns within a second.
shell_settle() {
  local pid t0 t1 calm=0
  pid=$(bus call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.kde.plasmashell 2>/dev/null | awk '{print $2}')
  [ -n "$pid" ] && [ -r "/proc/$pid/stat" ] || return 0
  # utime + stime (fields 14 and 15; the name in parentheses may hold spaces)
  t0=$(sed 's/.*) //' "/proc/$pid/stat" 2>/dev/null | awk '{print $12 + $13}')
  for _ in $(seq 1 40); do
    sleep 0.5
    t1=$(sed 's/.*) //' "/proc/$pid/stat" 2>/dev/null | awk '{print $12 + $13}')
    [ -n "$t1" ] && [ -n "$t0" ] || return 0
    if [ $((t1 - t0)) -le $(($(getconf CLK_TCK) * 3 / 100)) ]; then
      calm=$((calm + 1))
      [ "$calm" -ge 2 ] && return 0
    else
      calm=0
    fi
    t0=$t1
  done
}
SHELL_VIA_UNIT=0 SHELL_ENV=()
stop_plasmashell() {
  local pid
  SHELL_VIA_UNIT=0 SHELL_ENV=()
  shell_settle
  if shell_is_systemd_unit; then
    SHELL_VIA_UNIT=1
    systemctl --user stop plasma-plasmashell.service
  else
    if [ "$OUTSIDE" = 1 ]; then
      pid=$(bus call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.kde.plasmashell 2>/dev/null | awk '{print $2}')
      [ -z "$pid" ] || [ ! -r "/proc/$pid/environ" ] || mapfile -d '' SHELL_ENV <"/proc/$pid/environ"
    fi
    kquitapp6 plasmashell >/dev/null 2>&1 || true
  fi
  for _ in $(seq 1 40); do has_name org.kde.plasmashell || break; sleep 0.5; done
}
start_plasmashell() {
  if [ "$SHELL_VIA_UNIT" = 1 ]; then
    systemctl --user start plasma-plasmashell.service
  else
    mkdir -p "$STATE"
    if [ ${#SHELL_ENV[@]} -gt 0 ]; then
      env -i "${SHELL_ENV[@]}" setsid -f plasmashell >>"$STATE/plasmashell.log" 2>&1 </dev/null
    else
      setsid -f plasmashell >>"$STATE/plasmashell.log" 2>&1 </dev/null
    fi
  fi
  for _ in $(seq 1 60); do has_name org.kde.plasmashell && break; sleep 0.5; done
  wait_panels 1 >/dev/null
  sleep 2
}
restart_plasmashell() {
  if shell_is_systemd_unit; then
    shell_settle
    systemctl --user restart plasma-plasmashell.service
    for _ in $(seq 1 60); do has_name org.kde.plasmashell && break; sleep 0.5; done
    wait_panels 1 >/dev/null
    sleep 2
  else
    stop_plasmashell
    start_plasmashell
  fi
}

# Panel thickness is clamped to the Plasma style's minimum while a new panel view loads, which
# can briefly be the style's unprefixed (dock-sized) frame; set it again once the panels exist.
# The top bar follows the text size as the layout script sizes it (34 px at the design font,
# docs/parts/text-scale.md). In tablet posture the tablet script owns both sizes: left alone.
fix_panel_thickness() {
  if bus get-property org.kde.KWin /org/kde/KWin org.kde.KWin.TabletModeManager tabletMode 2>/dev/null | grep -q true; then
    echo "tablet posture: left to plasmafusion-tablet"
    return 0
  fi
  plasmashell_eval '
function textScale() {
    var pt = NaN;
    var font = ConfigFile("kdeglobals", "General").readEntry("font");
    if (font !== undefined && font !== null && String(font) !== "") pt = parseFloat(String(font).split(",")[1]);
    var s = pt > 0 ? pt / 9.75 : gridUnit / 18;
    return Math.max(0.85, Math.min(1.6, s));
}
var top = Math.round(34 * textScale());
var ps = panels(), fixed = [];
for (var i = 0; i < ps.length; i++) {
    var p = ps[i];
    if (p.location === "top" && p.lengthMode === "fill" && p.height !== top) { p.height = top; fixed.push("top bar " + top); }
    if (p.location === "bottom" && p.floating && p.lengthMode === "fit" && p.height !== 72) { p.height = 72; fixed.push("dock 72"); }
}
print(fixed.length ? "set " + fixed.join(", ") : "as designed");'
}

# Ids of the full-width top panels (the Plasma Fusion top bar).
top_panel_ids() {
  plasmashell_eval '
var ids = [], ps = panels();
for (var i = 0; i < ps.length; i++) {
    if (ps[i].location === "top" && ps[i].lengthMode === "fill") ids.push(ps[i].id);
}
print(ids.join(" "));' || true
}

# Stock pop-ups of a non-floating panel are attached to it with square corners; with
# plasmashellrc [PlasmaViews][Panel <id>] floatingApplets=1 they float under the bar with every
# corner rounded (Main and QuickSettings boards). Desktop scripting has no property for it and
# plasmashell reads it when it creates the panel view, so it takes effect at the next shell
# start. Returns 0 when a value was changed.
ensure_floating_applets() {
  local id changed=1 before
  for id in $(top_panel_ids); do
    before=$CHANGES
    set_key plasmashellrc "PlasmaViews/Panel $id" floatingApplets 1
    [ "$CHANGES" = "$before" ] || changed=0
  done
  return $changed
}

# A widget that plasmashell drops while rebuilding the layout (plasma-apply-lookandfeel
# --resetLayout, --reset-layout here, or a Global Theme applied with its layout in System
# Settings) keeps its global shortcut in kglobalaccel: the shell unloads the old containments
# without the per-widget clean-up. Such an "activate widget N" entry of a widget that is no
# longer in the layout file does nothing but keeps the key taken, so it is removed. Returns 0
# when an entry was (or, in a dry run, would be) removed. $1 Qt key code
release_dead_widget_key() {
  local appletsrc=$CONFIG/plasma-org.kde.plasma.desktop-appletsrc holders wid released=1
  [ -s "$appletsrc" ] || return 1
  holders=$(bus_json call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel globalShortcutsByKey "(ai)(i)" 4 "$1" 0 0 0 0 2>/dev/null |
    python3 -c '
import json, sys
# KGlobalShortcutInfo: action, action name, component, component name, context, ...
for s in json.load(sys.stdin)["data"][0]:
    if s[2] == "plasmashell" and s[0].startswith("activate widget "):
        print(s[0][len("activate widget "):])' 2>/dev/null || true)
  for wid in $holders; do
    case $wid in '' | *[!0-9]*) continue ;; esac
    grep -Eq "^\[Containments\]\[$wid\]|^\[Containments\]\[[0-9]+\]\[Applets\]\[$wid\]" "$appletsrc" && continue
    note "shortcut plasmashell / activate widget $wid: $(keyname "$1") -> removed (widget $wid is no longer in the layout)"
    CHANGES=$((CHANGES + 1))
    released=0
    [ "$DRY" = 1 ] || bus call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel unregister ss plasmashell "activate widget $wid" >/dev/null || true
  done
  return $released
}

# Every action holding a key, as "component<TAB>action" lines. $1 Qt key code
key_holders() {
  bus_json call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel globalShortcutsByKey "(ai)(i)" 4 "$1" 0 0 0 0 2>/dev/null |
    python3 -c '
import json, sys
# KGlobalShortcutInfo: action, action name, component, component name, context, ...
for s in json.load(sys.stdin)["data"][0]:
    print(s[2] + "\t" + s[0])' 2>/dev/null || true
}

# Give a key to one action only: every other action that holds it loses it (each change is
# recorded in the backup, so fusion-restore.sh gives the keys back). $1 component, $2 action,
# $3 Qt key code
shortcut_claim() {
  local comp action
  while IFS=$'\t' read -r comp action; do
    [ -n "$comp" ] || continue
    [ "$comp" = "$1" ] && [ "$action" = "$2" ] && continue
    shortcut_remove "$comp" "$action" "$3"
  done < <(key_holders "$3")
  shortcut_add "$1" "$2" "$3"
}

# A widget's global shortcut ("activate widget <id>", set through the widget as the shell does;
# one key per widget). Set when the widget has none yet or still has REPLACE (the key an earlier
# Plasma Fusion gave it); a key the user chose is kept. A dead entry of a widget dropped by an
# earlier layout rebuild is cleared first. With CLAIM=claim every other holder of the key loses it
# (the Windows-style set); otherwise the key is only taken when it is free.
# fusion-restore.sh gives the widget its old key back (recorded like the other shortcuts).
# $1 plugin, $2 Qt key code, $3 key text, $4 label, $5 REPLACE key text or "", $6 claim|free
ensure_widget_shortcut() {
  local plugin=$1 code=$2 text=$3 label=$4 replace=${5:-} mode=${6:-free} found entry id cur free released old comp action
  found=$(plasmashell_eval "
var out = [], ps = panels();
for (var i = 0; i < ps.length; i++) {
    var ws = ps[i].widgets(\"$plugin\");
    for (var j = 0; j < ws.length; j++) out.push(ws[j].id + \"=\" + ws[j].globalShortcut);
}
print(out.join(\" \"));" || true)
  [ -n "$found" ] || { note "$label: widget not in a panel (no shortcut set)"; return 0; }
  for entry in $found; do
    id=${entry%%=*} cur=${entry#*=}
    if [ "$cur" = "$text" ]; then
      note "$label widget $id shortcut = $text (unchanged)"
      continue
    fi
    if [ -n "$cur" ] && [ "$cur" != "$replace" ]; then
      note "$label widget $id shortcut = $cur (kept: set by the user)"
      continue
    fi
    released=1
    release_dead_widget_key "$code" && released=0
    if [ "$mode" = claim ]; then
      while IFS=$'\t' read -r comp action; do
        [ -n "$comp" ] || continue
        [ "$comp" = plasmashell ] && [ "$action" = "activate widget $id" ] && continue
        # Dead widget entries were handled above (removed, not recorded as a change to undo).
        [[ $comp == plasmashell && $action == "activate widget "* ]] &&
          ! grep -Eq "^\[Containments\]\[[0-9]+\]\[Applets\]\[${action#activate widget }\]" "$CONFIG/plasma-org.kde.plasma.desktop-appletsrc" && continue
        shortcut_remove "$comp" "$action" "$code"
      done < <(key_holders "$code")
      free=true
    else
      free=$(bus call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel globalShortcutAvailable "(ai)s" 4 "$code" 0 0 0 plasmashell 2>/dev/null | awk '{print $2}' || true)
      # A dry run removes nothing, so the key only counts as free after the removal it would do.
      [ "$DRY" = 1 ] && [ "$released" = 0 ] && free=true
    fi
    if [ "$free" != true ]; then
      note "$label widget $id: $text is in use or could not be checked (no shortcut set)"
      continue
    fi
    note "$label widget $id shortcut: ${cur:-<none>} -> $text"
    CHANGES=$((CHANGES + 1))
    [ "$DRY" = 1 ] && continue
    old=
    [ -z "$cur" ] || old=$(shortcut_get plasmashell "activate widget $id")
    printf '%s\t%s\t%s\n' plasmashell "activate widget $id" "$old" >>"$BACKUP/shortcuts"
    plasmashell_eval "
var ps = panels();
for (var i = 0; i < ps.length; i++) {
    var w = ps[i].widgetById($id);
    if (w) { w.globalShortcut = \"$text\"; }
}" >/dev/null
  done
}

# ---------- in-place migration of an existing Plasma Fusion layout ----------

# Folder View (desktop icons) keys for the desktop (BACKLOG M1; LAYOUT-1 writes the same ones into a
# fresh layout). Only keys the containment does not have yet are written.
FOLDER_KEYS=(url=desktop:/ sortMode=-1 arrangement=1 alignment=0 iconSize=2 popups=false toolTips=false
  selectionMarkers=true useTypeAhead=true)
FOLDER_PREVIEWS=(imagethumbnail jpegthumbnail svgthumbnail gsthumbnail opendocumentthumbnail ffmpegthumbs)
# Tray items hidden in the top bar (round 2; TABLET 4.3: quick settings has its own keyboard button).
TRAY_HIDE=(org.kde.plasma.vault org.kde.plasma.devicenotifier org.kde.kscreen org.kde.plasma.printmanager
  org.kde.plasma.manage-inputmethod)

# Thumbnailers of FOLDER_PREVIEWS that are installed (KIO thumbnail plugins, kf6/thumbcreator).
installed_previews() {
  local p d dirs out=()
  IFS=: read -r -a dirs <<<"${QT_PLUGIN_PATH:-}"
  dirs+=(/usr/lib64/qt6/plugins /usr/lib/qt6/plugins /usr/lib/x86_64-linux-gnu/qt6/plugins /run/current-system/sw/lib/qt-6/plugins)
  for p in "${FOLDER_PREVIEWS[@]}"; do
    for d in "${dirs[@]}"; do
      [ -n "$d" ] && [ -e "$d/kf6/thumbcreator/$p.so" ] && { out+=("$p"); break; }
    done
  done
  local IFS=,
  echo "${out[*]}"
}

# What the shell knows and the files do not: the size of the screen with the desktop cards. Printed as
# "W H", or nothing.
card_screen_size() {
  plasmashell_eval '
var ds = desktops(), best = null;
for (var i = 0; i < ds.length; i++) {
    var n = ds[i].widgets().length;
    if (ds[i].screen >= 0 && (best === null || n > best.widgets().length)) best = ds[i];
}
if (best !== null) { var g = screenGeometry(best.screen); print(Math.round(g.width) + " " + Math.round(g.height)); }' || true
}

# Migrate the layout file while plasmashell is stopped (or print what it would do): everything a
# fresh layout gets from the Global Theme's layout script that an existing one lacks. Panels, pins,
# cards and their places are kept; a value the user changed is kept. $1 "W H" of the card screen
migrate_layout() {
  local out rc=0
  out=$(python3 - "$CONFIG" "$DRY" "${1:-}" "$(installed_previews)" "$(package_dir plasma/plasmoids "$PEN_WIDGET" >/dev/null && echo 1 || echo 0)" \
    "${FOLDER_KEYS[*]}" "${TRAY_HIDE[*]}" "$(package_dir plasma/plasmoids "$DESKTOP_CONTAINMENT" >/dev/null && echo 1 || echo 0)" <<'PY'
import re, subprocess, sys

config, dry, size, previews, pen_installed, folder_keys, tray_hide, desktop_installed = sys.argv[1:9]
dry = dry == "1"
APPLETSRC = "plasma-org.kde.plasma.desktop-appletsrc"

def parse(path):
    """KConfig file -> {group tuple: {key: value}} (keys without their [$flags])."""
    groups, cur = {}, None
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return {}
    for line in text.splitlines():
        t = line.strip()
        if not t or t.startswith("#"):
            continue
        if t.startswith("["):
            cur = tuple(re.findall(r"\[([^\]]*)\]", t))
            cur = tuple(g for g in cur if not g.startswith("$"))
            groups.setdefault(cur, {})
            continue
        if cur is None or "=" not in t:
            continue
        k, v = t.split("=", 1)
        k = re.sub(r"\[.*\]$", "", k.strip())
        groups[cur][k] = v.strip()
    return groups

changes = 0
cmds = []
def note(msg):
    print("  " + msg)
def write(file, groups, key, value, old=None):
    global changes
    changes += 1
    where = "".join("[%s]" % g for g in groups)
    note("%s %s %s: %s -> %s" % (file, where, key, "<unset>" if old is None else old, value))
    args = ["kwriteconfig6", "--file", file]
    for g in groups:
        args += ["--group", g]
    args += ["--key", key, "--", value]
    cmds.append(args)

rc = parse(config + "/" + APPLETSRC)
shellrc = parse(config + "/plasmashellrc")
if not rc:
    note("layout: no %s (nothing to migrate)" % APPLETSRC)
    print("CHANGES 0")
    sys.exit(0)

def applets(cid):
    """Direct applets of a containment: {id: plugin}."""
    out = {}
    for g, kv in rc.items():
        if len(g) == 4 and g[0] == "Containments" and g[1] == cid and g[2] == "Applets" and "plugin" in kv:
            out[g[3]] = kv["plugin"]
    return out

conts = {g[1]: kv for g, kv in rc.items() if len(g) == 2 and g[0] == "Containments"}
CARDS = ("org.plasmafusion.weathercard", "org.plasmafusion.calendarcard", "org.plasmafusion.systemcard",
         "org.kde.plasma.weather", "org.kde.plasma.calendar", "org.kde.plasma.systemmonitor")

# 1. Desktop: the Plasma Fusion desktop (Folder View with the tablet home screen, TABLET2 H1) when it
# is installed, else Folder View. Both read Folder View's keys, so icons, cards and wallpaper stay.
# The "Desktop" containment (no icons) also gets the Fusion keys; a Folder View keeps its own.
target = "org.plasmafusion.desktop" if desktop_installed == "1" else "org.kde.plasma.folder"
desktops = [c for c, kv in conts.items() if kv.get("plugin") in ("org.kde.desktopcontainment", "org.kde.plasma.folder", "org.plasmafusion.desktop")]
for c in sorted(desktops, key=int):
    kv = conts[c]
    plugin = kv.get("plugin")
    if plugin == target:
        note("desktop %s: %s (unchanged)" % (c, plugin))
        continue
    write(APPLETSRC, ["Containments", c], "plugin", target, plugin)
    if plugin != "org.kde.desktopcontainment":
        continue
    general = rc.get(("Containments", c, "General"), {})
    wanted = [kv2.split("=", 1) for kv2 in folder_keys.split()]
    if previews:
        wanted.append(["previewPlugins", previews])
    for k, v in wanted:
        if k in general:
            note("desktop %s [General] %s = %s (kept)" % (c, k, general[k]))
        else:
            write(APPLETSRC, ["Containments", c, "General"], k, v)

# 2. Card positions in portrait (new keys only; the landscape ones stay where they are).
def geoms(value):
    out = []
    for part in (value or "").split(";"):
        m = re.match(r"^Applet-(\d+):(-?\d+),(-?\d+),(\d+),(\d+),(-?\d+)$", part.strip())
        if m:
            out.append([m.group(1)] + [int(x) for x in m.groups()[1:]])
    return out
CELL = 16
for c in sorted(desktops, key=int):
    kv = conts[c]
    cards = {a: p for a, p in applets(c).items() if p in CARDS}
    if not cards:
        continue
    w = h = None
    if size and len(size.split()) == 2:
        w, h = (int(x) for x in size.split())
    else:
        for k in kv:
            m = re.match(r"^ItemGeometries-(\d+)x(\d+)$", k)
            if m and int(m.group(1)) > int(m.group(2)):
                w, h = int(m.group(1)), int(m.group(2))
    if not w or w < h:
        note("desktop %s: screen size unknown or not landscape; card positions for portrait not written" % c)
        continue
    landscape = geoms(kv.get("ItemGeometries-%dx%d" % (w, h)) or kv.get("ItemGeometriesHorizontal"))
    placed = [g for g in landscape if g[0] in cards]
    placed.sort(key=lambda g: (g[2], g[1]))
    pkey = "ItemGeometries-%dx%d" % (h, w)
    if "ItemGeometriesVertical" in kv or pkey in kv or not placed:
        note("desktop %s: portrait card positions %s" % (c, "kept" if placed else "not written (no card positions)"))
        continue
    # Portrait (the landscape height becomes the width): the first two cards side by side under the
    # bar, right-aligned; the rest under the right one (the CPU/memory card hides itself in portrait).
    pw = h
    out = []
    right = placed[1] if len(placed) > 1 else placed[0]
    xr = (pw - CELL - right[3]) // CELL * CELL
    if len(placed) > 1:
        left = placed[0]
        xl = (xr - CELL - left[3]) // CELL * CELL
        out.append((left[0], max(xl, 0), CELL, left[3], left[4]))
        out.append((right[0], xr, CELL, right[3], right[4]))
        y = CELL + max(left[4], right[4]) + CELL
        rest = placed[2:]
    else:
        out.append((right[0], xr, CELL, right[3], right[4]))
        y = CELL + right[4] + CELL
        rest = []
    for g in rest:
        out.append((g[0], (pw - CELL - g[3]) // CELL * CELL, y, g[3], g[4]))
        y += g[4] + CELL
    value = "".join("Applet-%s:%d,%d,%d,%d,0;" % t for t in out)
    write(APPLETSRC, ["Containments", c], pkey, value)
    write(APPLETSRC, ["Containments", c], "ItemGeometriesVertical", value)

# The top bar: a top panel holding a Plasma Fusion top-bar widget.
TOP_WIDGETS = ("org.plasmafusion.quicksettings", "org.plasmafusion.appname", "org.plasmafusion.clockpill")
top = None
# Every Plasma Fusion top bar (one per screen; their trays are set up alike).
tops = []
for c, kv in sorted(conts.items(), key=lambda i: int(i[0]) if i[0].isdigit() else 0):
    if kv.get("plugin") == "org.kde.panel" and kv.get("location") == "3" and set(applets(c).values()) & set(TOP_WIDGETS):
        tops.append(c)
        if top is None:
            top = c

# 3. Top bar solid next to maximized windows (owner decision 5): adaptive (0) instead of the
#    translucent (2) the earlier layout set; another value is the user's.
if top is not None:
    view = shellrc.get(("PlasmaViews", "Panel %s" % top), {})
    cur = view.get("panelOpacity")
    if cur == "2":
        write("plasmashellrc", ["PlasmaViews", "Panel %s" % top], "panelOpacity", "0", cur)
    else:
        note("top bar opacity: %s (kept)" % {None: "adaptive (default)", "0": "adaptive", "1": "opaque"}.get(cur, cur))

# 4. Tray items hidden (no expander arrow), in every top bar's tray; 5. app menus for their own
#    screen only.
for c, kv in conts.items():
    if kv.get("plugin") != "org.kde.panel":
        continue
    for a, plugin in applets(c).items():
        if plugin == "org.kde.plasma.systemtray" and c in tops:
            general = rc.get(("Containments", c, "Applets", a, "General"), {})
            for key in ("hiddenItems", "disabledStatusNotifiers"):
                items = [i for i in general.get(key, "").split(",") if i]
                add = [i for i in tray_hide.split() if i not in items]
                if add:
                    write(APPLETSRC, ["Containments", c, "Applets", a, "General"], key, ",".join(items + add), general.get(key))
                else:
                    note("tray %s %s (unchanged)" % (a, key))
            # Disks & Devices: the quick-settings page replaces the stock item, which is not loaded
            # (known, not extra), as the desktop layout does for a new bar.
            if "org.plasmafusion.quicksettings" in applets(c).values():
                known = [i for i in general.get("knownItems", "").split(",") if i]
                extra = [i for i in general.get("extraItems", "").split(",") if i]
                dn = "org.kde.plasma.devicenotifier"
                if dn not in known:
                    write(APPLETSRC, ["Containments", c, "Applets", a, "General"], "knownItems", ",".join(known + [dn]), general.get("knownItems"))
                if dn in extra:
                    write(APPLETSRC, ["Containments", c, "Applets", a, "General"], "extraItems", ",".join(i for i in extra if i != dn), general.get("extraItems"))
                else:
                    note("tray %s Disks & Devices not loaded (unchanged)" % a)
        if plugin == "org.kde.plasma.appmenu":
            appearance = rc.get(("Containments", c, "Applets", a, "Configuration", "Appearance"), {})
            if "allScreens" in appearance:
                note("app menu %s allScreens = %s (kept)" % (a, appearance["allScreens"]))
            else:
                write(APPLETSRC, ["Containments", c, "Applets", a, "Configuration", "Appearance"], "allScreens", "false")

# 6. The pen widget in the top bar, between the tray and quick settings (hidden in laptop posture).
if top is not None and pen_installed == "1":
    have = applets(top)
    if "org.plasmafusion.pen" in have.values():
        note("pen widget in the top bar (unchanged)")
    else:
        ids = [int(x) for g in rc for x in g if x.isdigit()]
        new = str(max(ids) + 1 if ids else 1)
        write(APPLETSRC, ["Containments", top, "Applets", new], "immutability", "1")
        write(APPLETSRC, ["Containments", top, "Applets", new], "plugin", "org.plasmafusion.pen")
        general = rc.get(("Containments", top, "General"), {})
        order = [i for i in general.get("AppletOrder", "").split(";") if i]
        if not order:
            order = sorted(have, key=int)
        order = [i for i in order if i in have]
        qs = [a for a, p in have.items() if p == "org.plasmafusion.quicksettings"]
        at = order.index(qs[0]) if qs and qs[0] in order else len(order)
        order.insert(at, new)
        write(APPLETSRC, ["Containments", top, "General"], "AppletOrder", ";".join(order), general.get("AppletOrder"))

if not dry:
    for args in cmds:
        r = subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        if r.returncode != 0:
            print("  error: %s: %s" % (" ".join(args[3:]), r.stderr.strip()))
            sys.exit(1)
print("CHANGES %d" % changes)
PY
) || rc=$?
  printf '%s\n' "$out" | grep -v '^CHANGES ' || true
  CHANGES=$((CHANGES + $(printf '%s\n' "$out" | sed -n 's/^CHANGES \([0-9][0-9]*\)$/\1/p' | tail -n 1 | grep . || echo 0)))
  return $rc
}

# True when the layout file still has a part the migration would change.
layout_needs_migration() {
  local out
  out=$(DRY=1 migrate_layout "$1" 2>/dev/null) || return 0
  printf '%s\n' "$out" | grep -q ' -> '
}

# gtk.css that holds nothing but Plasma's own import (kde-gtk-config writes "@import
# 'colors.css';"), comments and blank lines can be replaced; anything else is kept.
gtk_css_is_plain() { # $1 file
  python3 - "$1" <<'PY'
import re, sys
text = re.sub(r"/\*.*?\*/", "", open(sys.argv[1], encoding="utf-8", errors="replace").read(), flags=re.S)
lines = [l.strip() for l in text.splitlines() if l.strip()]
ok = {"@import 'colors.css';", '@import "colors.css";', "@import 'plasma-fusion.css';", '@import "plasma-fusion.css";'}
sys.exit(0 if all(l in ok for l in lines) else 1)
PY
}

# Copy the built HOME tree into this HOME (after the backup).
install_build() {
  local src=$INSTALL f dest
  say "Install from $src"
  note "copy $src/.local/ -> ~/.local/"
  CHANGES=$((CHANGES + 1))
  if [ "$DRY" = 0 ]; then
    if command -v rsync >/dev/null; then
      rsync -a "$src/.local/" "$HOME/.local/"
    else
      mkdir -p "$HOME/.local" && cp -a "$src/.local/." "$HOME/.local/"
    fi
  fi
  [ -z "$CONFIG_SRC" ] || install_config "$CONFIG_SRC"
  if [ "$DRY" = 0 ]; then
    command -v fc-cache >/dev/null && fc-cache -f >/dev/null 2>&1 || true
    command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
  fi
}

# Copy per-user configuration files (GTK stylesheets) into ~/.config. User units are left to
# install_user_service, which takes them with their program from the build or package it installs
# (a system package's template here can be older than the user's build). $1 source directory
install_config() {
  local src=$1 f dest
  while IFS= read -r -d '' f; do
    f=${f#"$src/"}
    case $f in systemd/user/*.service) continue ;; esac
    dest=$CONFIG/$f
    if [ -e "$dest" ] && cmp -s "$src/$f" "$dest"; then
      note "$dest (unchanged)"
      continue
    fi
    if [ "$(basename "$f")" = gtk.css ] && [ -e "$dest" ] && ! gtk_css_is_plain "$dest"; then
      if grep -q "plasma-fusion.css" "$dest"; then
        note "$dest already imports plasma-fusion.css (kept as it is)"
        continue
      fi
      note "$dest has its own rules: add @import 'plasma-fusion.css'; after its colors.css import"
      CHANGES=$((CHANGES + 1))
      [ "$DRY" = 1 ] && continue
      python3 - "$dest" <<'PY'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines(True)
line = "@import 'plasma-fusion.css';\n"
at = next((i + 1 for i, l in enumerate(lines) if "colors.css" in l and "@import" in l), None)
if at is None:
    # Plasma adds its colors.css import on the next colour change; ours goes last either way.
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    lines.append(line)
else:
    lines.insert(at, line)
open(path, "w", encoding="utf-8").writelines(lines)
PY
      continue
    fi
    note "copy $dest"
    CHANGES=$((CHANGES + 1))
    if [ "$DRY" = 0 ]; then
      mkdir -p "$(dirname "$dest")"
      cp "$src/$f" "$dest"
    fi
  done < <(find "$src" -type f -print0 | sort -z)
}

# Write a small text file when its content differs. Returns 0 when it was (or would be) written.
install_text() { # $1 path, $2 content, $3 mode (default 0644)
  local mode=${3:-0644}
  if [ -f "$1" ] && [ "$(cat "$1")" = "$2" ]; then
    if [ "$(stat -c %a "$1")" = "${mode#0}" ]; then
      note "$1 (unchanged)"
      return 1
    fi
    note "chmod $mode $1"
    CHANGES=$((CHANGES + 1))
    [ "$DRY" = 1 ] || chmod "$mode" "$1"
    return 0
  fi
  note "write $1"
  CHANGES=$((CHANGES + 1))
  [ "$DRY" = 1 ] && return 0
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1.tmp" && chmod "$mode" "$1.tmp" && mv -f "$1.tmp" "$1"
}

# True when the systemd user manager on the other end of `systemctl --user` belongs to this
# session (its environment names this session bus), so starting a user service starts it here and
# nowhere else. A private test session has no manager of its own: files only.
session_manager() {
  local addr
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || return 1
  addr=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')
  [ -n "$addr" ] && [ "$addr" = "$DBUS_SESSION_BUS_ADDRESS" ]
}

# Find a file shipped for the per-user setup: in a data directory (the build or the system
# package) below plasma-fusion/DIR, else in the source tree next to these tools. $1 DIR, $2 name
shipped_file() {
  local f d base
  # The build being installed first (in a dry run it is not copied yet), then the data directories.
  # shellcheck disable=SC2086
  for d in ${INSTALL:+"$INSTALL/.local/share"} "$DATA" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
    for base in ${d//:/ }; do
      [ -f "$base/plasma-fusion/$1/$2" ] && { echo "$base/plasma-fusion/$1/$2"; return 0; }
    done
  done
  for f in "$HERE/../../packages/$1/$2" "$HERE/../$1/$2"; do
    [ -f "$f" ] && { (cd "$(dirname "$f")" && echo "$(pwd)/$(basename "$f")"); return 0; }
  done
  return 1
}

# Install, enable and start a user service (WantedBy=graphical-session.target): the unit into
# ~/.config/systemd/user/, the program its ExecStart names below %h/.local/libexec/plasma-fusion/
# from the unit's directory, the wants link written like `systemctl --user enable` does, then
# daemon-reload and start, only in this session's own systemd manager. Recorded in the backup's
# services list. $1 unit name, $2 shipped directory (plasma-fusion/<dir>)
install_user_service() {
  local unit=$1 dir=$2 src exe prog dest=$CONFIG/systemd/user/$1 link=$CONFIG/$SESSION_WANTS_REL/$1 changed=0
  if ! src=$(shipped_file "$dir" "$unit"); then
    note "note: $unit is not installed (no $dir/$unit in the build, the system package or the sources)"
    return 0
  fi
  exe=$(sed -n 's/^ExecStart=[-@:+!]*//p' "$src" | head -n 1 | awk '{print $1}')
  case $exe in
    %h/.local/libexec/plasma-fusion/*)
      prog=${exe#%h/}
      if [ ! -f "$(dirname "$src")/$(basename "$prog")" ]; then
        note "warning: $(dirname "$src")/$(basename "$prog") is missing; $unit is not installed"
        return 0
      fi
      if [ -f "$HOME/$prog" ] && cmp -s "$(dirname "$src")/$(basename "$prog")" "$HOME/$prog"; then
        note "\$HOME/$prog (unchanged)"
      else
        note "install \$HOME/$prog"
        CHANGES=$((CHANGES + 1)) changed=1
        if [ "$DRY" = 0 ]; then
          mkdir -p "$(dirname "$HOME/$prog")"
          cp "$(dirname "$src")/$(basename "$prog")" "$HOME/$prog.tmp" && chmod 0755 "$HOME/$prog.tmp" && mv -f "$HOME/$prog.tmp" "$HOME/$prog"
        fi
      fi ;;
  esac
  install_text "$dest" "$(cat "$src")" && changed=1
  if [ -L "$link" ] && [ "$(readlink "$link")" = "../$unit" ]; then
    note "$link (unchanged)"
  else
    note "enable $unit ($link)"
    CHANGES=$((CHANGES + 1)) changed=1
    if [ "$DRY" = 0 ]; then
      mkdir -p "$(dirname "$link")"
      ln -sfn "../$unit" "$link"
    fi
  fi
  [ "$DRY" = 1 ] && return 0
  printf 'unit\t%s\n' "$unit" >>"$BACKUP/services"
  if session_manager; then
    systemctl --user daemon-reload 2>/dev/null || true
    if [ "$changed" = 1 ] || ! systemctl --user -q is-active "$unit" 2>/dev/null; then
      if systemctl --user restart "$unit" 2>/dev/null; then note "started $unit"; else note "warning: $unit did not start (systemctl --user status $unit)"; fi
    else
      note "$unit running (unchanged)"
    fi
  else
    note "note: no systemd user manager for this session; $unit starts at the next login"
  fi
}

# Text rendering (GAPS D9, ADAPTIVE fix 20): greyscale antialiasing with slight hinting, written
# as System Settings > Fonts writes it (plasma-workspace kcms/fonts: KXftConfig's fontconfig file,
# then kdeglobals [General] Xft*), so Qt, GTK and every fontconfig client draw the same text.
# Fedora's /etc/fonts/conf.d/10-sub-pixel-rgb-for-kde.conf turns subpixel colours on; the user's
# fonts.conf is read later (50-user.conf) and wins. Other rules in the file are kept.
FONTS_CONF_REL=fontconfig/fonts.conf
ensure_fonts_conf() { # prints what changes; returns 0 when the file changes (or would)
  python3 - "$CONFIG/$FONTS_CONF_REL" "$DRY" <<'PY'
import os, sys
import xml.dom.minidom as minidom
path, dry = sys.argv[1], sys.argv[2] == "1"
# KXftConfig's elements: <match target="font"><edit mode="assign" name="..."><TYPE>VALUE</TYPE></edit></match>
WANT = [("rgba", "const", "none"), ("hintstyle", "const", "hintslight"), ("hinting", "bool", "true"),
        ("antialias", "bool", "true")]
header = '<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">\n'
try:
    text = open(path, encoding="utf-8").read()
    doc = minidom.parseString(text)
except FileNotFoundError:
    text = None
    doc = minidom.parseString(header + "<fontconfig></fontconfig>")
except Exception as e:
    print("  warning: %s is not readable as fontconfig XML (%s); left as it is" % (path, e))
    sys.exit(1)
root = doc.documentElement
if root.tagName != "fontconfig":
    print("  warning: %s has no <fontconfig> root; left as it is" % path)
    sys.exit(1)
def simple_edit(match):
    """(name, type, value, edit) of a KXftConfig-style match (one assign edit, no test), else None."""
    if match.getAttribute("target") != "font":
        return None
    kids = [n for n in match.childNodes if n.nodeType == n.ELEMENT_NODE]
    if len(kids) != 1 or kids[0].tagName != "edit" or kids[0].getAttribute("mode") != "assign":
        return None
    vals = [n for n in kids[0].childNodes if n.nodeType == n.ELEMENT_NODE]
    if len(vals) != 1:
        return None
    return kids[0].getAttribute("name"), vals[0].tagName, "".join(t.data for t in vals[0].childNodes if t.nodeType == t.TEXT_NODE).strip(), vals[0]
changed = False
for name, typ, value in WANT:
    found = [m for m in root.getElementsByTagName("match") if m.parentNode is root and (simple_edit(m) or (None,))[0] == name]
    if found:
        n, t, v, node = simple_edit(found[0])
        if (t, v) == (typ, value):
            print("  %s: %s = %s (unchanged)" % (path, name, value))
            continue
        print("  %s: %s %s -> %s" % (path, name, v, value))
        new = doc.createElement(typ)
        new.appendChild(doc.createTextNode(value))
        node.parentNode.replaceChild(new, node)
    else:
        print("  %s: %s -> %s" % (path, name, value))
        m = doc.createElement("match"); m.setAttribute("target", "font")
        e = doc.createElement("edit"); e.setAttribute("mode", "assign"); e.setAttribute("name", name)
        c = doc.createElement(typ); c.appendChild(doc.createTextNode(value))
        e.appendChild(c); m.appendChild(e)
        if text is not None:
            root.appendChild(doc.createTextNode(" "))
        root.appendChild(m)
        if text is not None:
            root.appendChild(doc.createTextNode("\n"))
    changed = True
if changed and not dry:
    body = root.toprettyxml(indent=" ") if text is None else root.toxml()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(header + body + "\n")
    if text is not None:
        os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    os.replace(tmp, path)
sys.exit(0 if changed else 2)
PY
}

# Pen defaults (docs/parts/pen.md): tools/pen/pen-defaults.sh, next to tools/device in the
# sources and in the system package. Its backup is recorded, so fusion-restore.sh can undo it.
pen_defaults_tool() {
  local f
  for f in "$HERE/../pen/pen-defaults.sh" "$(dirname "$HERE")/pen/pen-defaults.sh"; do
    [ -f "$f" ] && { echo "$f"; return 0; }
  done
  return 1
}

# ---------- Windows-style shortcut set (owner decision 6) ----------

# Meta+N: the notification list of quick settings. The desktop file is the kglobalaccel component
# (as System Settings > Shortcuts > Add Command makes one); its command asks the quick-settings
# widget to open on the list through its [General] openRequest key ("notifications:<ms>").
NOTIFY_JS="var q=panels();for(var i=0;i<q.length;i++){var w=q[i].widgets('org.plasmafusion.quicksettings');for(var j=0;j<w.length;j++){w[j].currentConfigGroup=['General'];w[j].writeConfig('openRequest','notifications:'+Date.now());}}"
notify_desktop() {
  cat <<EOF
[Desktop Entry]
Type=Application
Name=Plasma Fusion: Notifications
Comment=Opens quick settings on the notification list (installed by Plasma Fusion's fusion-config.sh, removed by fusion-restore.sh)
Icon=preferences-desktop-notification-bell
Exec=busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$NOTIFY_JS"
StartupNotify=false
EOF
}
# $1 claim (the Windows set) or free (only when nothing holds Meta+N)
ensure_notify_shortcut() {
  local mode=$1 cur free
  # Executable: KDE runs a desktop file outside the system directories only when it has the
  # executable bit ("not owned by root and executable flag not set"), so kglobalaccel would bind
  # Meta+N and then refuse to launch it. System Settings' "Add Command" entries are made the same way.
  install_text "$DATA/kglobalaccel/$NOTIFY_COMPONENT" "$(notify_desktop)" 0755 || true
  if [ "$DRY" = 0 ]; then
    bus call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel doRegister as 4 "$NOTIFY_COMPONENT" _launch \
      "Plasma Fusion: Notifications" "Plasma Fusion: Notifications" >/dev/null 2>&1 ||
      note "warning: kglobalaccel did not take $NOTIFY_COMPONENT"
  fi
  if [ "$mode" = claim ]; then
    shortcut_claim "$NOTIFY_COMPONENT" _launch "$NOTIFY_SHORTCUT"
    return 0
  fi
  cur=$(shortcut_get "$NOTIFY_COMPONENT" _launch)
  if [ -n "$cur" ]; then
    # shellcheck disable=SC2086
    note "shortcut $NOTIFY_COMPONENT / _launch = $(keyname $cur) (kept)"
  elif [ -z "$(key_holders "$NOTIFY_SHORTCUT")" ]; then
    shortcut_set "$NOTIFY_COMPONENT" _launch "$NOTIFY_SHORTCUT"
  else
    note "notification list: Meta+N is in use (no shortcut set)"
  fi
}

# Search: Meta+Space, Meta+S, Alt+Space, Alt+F2 and KRunner's own keys (Search) activate the
# launcher (the shell's "activate application launcher", which opens it on the active screen, as
# the Meta key does); KRunner keeps no key, so nothing starts it.
apply_launcher_keys() {
  local k keys=()
  for k in $((META + K_SPACE)) $((META + 0x53)) $((ALT + K_SPACE)) $((ALT + K_F2)) $(shortcut_get org.kde.krunner.desktop _launch); do
    case " ${keys[*]} " in *" $k "*) ;; *) keys+=("$k") ;; esac
  done
  for k in "${keys[@]}"; do shortcut_claim plasmashell "$LAUNCHER_ACTION" "$k"; done
  shortcut_set org.kde.krunner.desktop _launch
  shortcut_set org.kde.krunner.desktop RunClipboard
}

# Windows and the dock: Meta+Up maximize, Meta+Down restore, quick tile top/bottom on
# Meta+Alt+Up/Down, Meta+Tab Overview, Meta+Alt+1..9 the dock's apps (apply_dock_entry_keys, after
# KWin has loaded the scripts; Meta+5..9 lose them; Meta+1..4 switch workspaces, section 3).
apply_window_keys() {
  local n
  shortcut_claim kwin "Window Maximize" $((META + K_UP))
  shortcut_claim kwin "Window Restore" $((META + K_DOWN))
  shortcut_claim kwin "Window Quick Tile Top" $((META + ALT + K_UP))
  shortcut_claim kwin "Window Quick Tile Bottom" $((META + ALT + K_DOWN))
  shortcut_claim kwin Overview $((META + K_TAB))
  for n in 1 2 3 4 5 6 7 8 9; do
    shortcut_remove plasmashell "activate task manager entry $n" $((META + 0x30 + n))
  done
}

# The dock's apps on Meta+Alt+1..9: the snap KWin script's "Plasma Fusion: Activate Dock Entry N"
# actions, which reach the dock on every Plasma version. Up to Plasma 6.7 plasmashell's "activate
# task manager entry N" did it; Plasma 6.8 gives those actions to the stock task manager only,
# which the dock replaces. The actions exist once KWin runs the script, so this comes after section
# 4 starts the scripts. $1 claim: the Windows-style set; migrate: move only a key an earlier
# Plasma Fusion gave to plasmashell's entry N (a run without the set, after an update).
DOCK_ENTRY="Plasma Fusion: Activate Dock Entry"
dock_entry_actions_registered() {
  bus call org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component shortcutNames 2>/dev/null |
    grep -qF "\"$DOCK_ENTRY 1\""
}
apply_dock_entry_keys() {
  local n key
  if [ "$DRY" = 0 ]; then
    for _ in $(seq 1 20); do dock_entry_actions_registered && break; sleep 0.5; done
    if ! dock_entry_actions_registered; then
      note "dock entry keys: the snap KWin script's actions are not registered (keys not set)"
      return 0
    fi
  fi
  for n in 1 2 3 4 5 6 7 8 9; do
    key=$((META + ALT + 0x30 + n))
    if [ "$1" = migrate ]; then
      key_holders "$key" | grep -qxF "plasmashell"$'\t'"activate task manager entry $n" || continue
    fi
    shortcut_claim kwin "$DOCK_ENTRY $n" "$key"
  done
}

# ---------- 0. the look before Plasma Fusion ----------

# Saved once, from the newest backup taken while another Global Theme was active (on a first run,
# the backup just taken), so "My previous desktop" can be chosen in System Settings.
# fusion-restore.sh stays the full undo; the package stays installed.
save_previous_look() {
  local pick='' b lnf opts=()
  say "Previous look"
  if [ -e "$DATA/plasma/look-and-feel/$PREVIOUS_LNF/metadata.json" ]; then
    note "Global Theme \"My previous desktop\" ($PREVIOUS_LNF) exists (kept)"
    return 0
  fi
  if [ ! -f "$HERE/previous-theme.py" ]; then
    note "note: $HERE/previous-theme.py is missing; \"My previous desktop\" is not saved"
    return 0
  fi
  [ "$DRY" = 1 ] && opts=(--dry-run)
  shopt -s nullglob
  for b in "$STATE"/backup-*/; do
    lnf=$(sed -n 's/^lookandfeel=//p' "$b/info" 2>/dev/null || true)
    case $lnf in org.plasmafusion.*) ;; *) pick=${b%/} ;; esac
  done
  shopt -u nullglob
  lnf=$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)
  if [ -n "$pick" ]; then
    note "save the look of $pick as the Global Theme \"My previous desktop\" ($PREVIOUS_LNF)"
  elif [ "$DRY" = 1 ] && [[ $lnf != org.plasmafusion.* ]]; then
    note "save the current look as the Global Theme \"My previous desktop\" ($PREVIOUS_LNF)"
    opts+=(--config-dir "$CONFIG" --lookandfeel "$lnf")
  else
    note "no backup from before Plasma Fusion: \"My previous desktop\" is not saved"
    return 0
  fi
  [ -z "$pick" ] || opts+=(--backup "$pick")
  CHANGES=$((CHANGES + 1))
  python3 "$HERE/previous-theme.py" --data "$DATA" "${opts[@]}" | sed 's/^/  /' ||
    note "warning: saving \"My previous desktop\" failed (nothing else is affected)"
}

# ---------- 1. Global Theme and layout ----------

[ "$DRY" = 1 ] && say "Dry run: nothing is changed." || make_backup
save_previous_look
if [ -n "$INSTALL" ]; then
  install_build
elif [ -n "$CONFIG_SRC" ]; then
  say "Per-user configuration from $CONFIG_SRC"
  install_config "$CONFIG_SRC"
fi

current_lnf=$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)
reset=0
case $LAYOUT in
  reset) reset=1 ;;
  keep) reset=0 ;;
  auto) fusion_layout_present || reset=1 ;;
esac
shell_running=0
has_name org.kde.plasmashell && shell_running=1
keep_auto=()
[ "$AUTO" = 1 ] && keep_auto=(-k)

# The compiled title bars, when the user (or DEPLOY-1) chose them: a Global Theme apply removes the
# user's own kwinrc [org.kde.kdecoration2] library and theme (the theme's Aurorae value comes back
# through kdedefaults), so they are chosen again after it.
keep_cpp_deco=0
read_key kwinrc org.kde.kdecoration2 library
[ "$REPLY" = org.plasmafusion.decoration ] && cpp_decoration_installed && keep_cpp_deco=1

say "Global Theme"
note "${current_lnf:-<default>} -> $LNF; layout: $([ "$reset" = 1 ] && echo rebuilt || echo kept)"
CHANGES=$((CHANGES + 1))
restart_why=
if [ "$reset" = 0 ]; then
  note "run: plasma-apply-lookandfeel -a $LNF ${keep_auto[*]}"
  [ "$DRY" = 1 ] || apply_lnf -a "$LNF" "${keep_auto[@]}"
  if [ -n "$INSTALL" ] && [ "$shell_running" = 1 ]; then
    # Widgets that were just updated on disk are loaded again only by a new plasmashell.
    restart_why="load the installed widgets"
  fi
elif [ "$shell_running" = 1 ]; then
  # plasmashell reads the Global Theme's desktop type (the widget-only "Desktop") only when it
  # starts, so apply the appearance, restart it, then rebuild the layout.
  note "run: plasma-apply-lookandfeel -a $LNF ${keep_auto[*]}"
  note "restart plasmashell"
  note "run: plasma-apply-lookandfeel -a $LNF --resetLayout ${keep_auto[*]}"
  if [ "$DRY" = 0 ]; then
    apply_lnf -a "$LNF" "${keep_auto[@]}"
    restart_plasmashell
    apply_lnf -a "$LNF" --resetLayout "${keep_auto[@]}"
    sleep 2
    note "panels after rebuild: $(wait_panels 2)"
    sleep 3
  fi
  restart_why="widgets created in a running shell load part of their settings only at start"
else
  # Without a running plasmashell the layout cannot be rebuilt live; removing the layout file
  # makes plasmashell build the Plasma Fusion layout when it next starts.
  note "run: plasma-apply-lookandfeel -a $LNF --resetLayout ${keep_auto[*]}"
  note "plasmashell is not running: remove ~/.config/plasma-org.kde.plasma.desktop-appletsrc so its next start builds the layout"
  if [ "$DRY" = 0 ]; then
    apply_lnf -a "$LNF" --resetLayout "${keep_auto[@]}" || true
    rm -f "$CONFIG/plasma-org.kde.plasma.desktop-appletsrc"
  fi
  note "note: run this again once plasmashell runs, for the top bar's floating pop-ups and the quick-settings shortcut"
fi
if [ "$keep_cpp_deco" = 1 ]; then
  note "title bars: the compiled Plasma Fusion decoration stays chosen"
  set_key kwinrc org.kde.kdecoration2 library org.plasmafusion.decoration
  set_key kwinrc org.kde.kdecoration2 theme ""
fi
# Written before the (last) restart, which is what applies it.
if has_name org.kde.plasmashell && fusion_layout_present; then
  if ensure_floating_applets && [ -z "$restart_why" ]; then
    restart_why="apply the top bar's floating pop-ups"
  fi
fi
# An existing Plasma Fusion layout (kept): migrated in place while plasmashell is stopped, in the
# restart that applies the steps above (one restart for all of it).
migrate=0 card_size=
if [ "$LAYOUT" = auto ] && [ "$reset" = 0 ] && has_name org.kde.plasmashell; then
  card_size=$(card_screen_size)
  layout_needs_migration "$card_size" && migrate=1
fi
if [ "$migrate" = 1 ]; then
  say "Desktop and top bar (existing layout, kept)"
  note "stop plasmashell${restart_why:+ (also to $restart_why)}"
  if [ "$DRY" = 1 ]; then
    migrate_layout "$card_size" || true
  else
    stop_plasmashell
    migrate_layout "$card_size" || note "warning: the layout migration stopped; the layout file is as far as it got (the backup has the original)"
    start_plasmashell
  fi
  note "start plasmashell"
elif [ -n "$restart_why" ]; then
  [ "$LAYOUT" != auto ] || [ "$reset" = 1 ] || note "desktop and top bar: nothing to migrate"
  note "restart plasmashell ($restart_why)"
  [ "$DRY" = 1 ] || restart_plasmashell
fi
if [ "$DRY" = 0 ] && has_name org.kde.plasmashell && fusion_layout_present; then
  note "panel thickness: $(fix_panel_thickness)"
fi
set_key kdeglobals KDE DefaultDarkLookAndFeel "$DARK"
set_key kdeglobals KDE DefaultLightLookAndFeel "$LIGHT"
set_key kdeglobals KDE AutomaticLookAndFeel "$([ "$AUTO" = 1 ] && echo true || echo false)"

# ---------- 1b. fonts and cursor ----------

# Set once. The Global Themes carry no fonts and no cursor: every theme apply (the automatic
# light/dark switch and the quick-settings Dark tile too) writes a theme's values to
# ~/.config/kdedefaults and deletes the user's own keys for them, so fonts in the theme would
# undo the user's font size at every switch. Later runs leave the user's choices alone.
# KConfig does not write a value that ~/.config/kdedefaults already gives (an older Plasma
# Fusion theme left Manrope there); that is fine, set_key then reports it unchanged.
say "Fonts and cursor"
if [ "$FONTS" = 1 ] || [ "$(kreadconfig6 --file plasmafusionrc --group Setup --key FontsAndCursor)" != "done" ]; then
  set_key kdeglobals General font "$UI_FONT"
  set_key kdeglobals General menuFont "$UI_FONT"
  set_key kdeglobals General toolBarFont "$UI_FONT"
  set_key kdeglobals General smallestReadableFont "$SMALL_FONT"
  set_key kdeglobals WM activeFont "$TITLE_FONT"
  cur_cursor=$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme)
  if ! data_path "icons/$CURSOR_THEME/index.theme" >/dev/null; then
    note "note: cursor theme $CURSOR_THEME is not installed; the cursor stays ${cur_cursor:-<default>}"
  elif [ "$cur_cursor" = "$CURSOR_THEME" ]; then
    note "kcminputrc [Mouse] cursorTheme = $CURSOR_THEME (unchanged)"
  else
    # plasma-apply-cursortheme writes kcminputrc and switches the running session's cursor.
    note "cursor: ${cur_cursor:-<default>} -> $CURSOR_THEME (plasma-apply-cursortheme)"
    CHANGES=$((CHANGES + 1))
    if [ "$DRY" = 0 ] && ! plasma-apply-cursortheme "$CURSOR_THEME" >/dev/null 2>&1; then
      kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme --notify "$CURSOR_THEME"
      note "note: plasma-apply-cursortheme failed; kcminputrc set, the cursor changes at the next login"
    fi
  fi
  set_key plasmafusionrc Setup FontsAndCursor "done"
  [ "$DRY" = 1 ] || dbus-send --session --type=signal /KDEPlatformTheme org.kde.KDEPlatformTheme.refreshFonts 2>/dev/null || true
  # The layout above was sized with the font from before (its text scale): size the bars again.
  if [ "$DRY" = 0 ] && has_name org.kde.plasmashell && fusion_layout_present; then
    note "panel thickness with the new font: $(fix_panel_thickness)"
  fi
else
  note "set by an earlier run (plasmafusionrc [Setup] FontsAndCursor=done): the current fonts and cursor stay; --fonts sets them again"
fi

# ---------- 2. virtual desktops ----------

say "Workspaces"
desktops_json=$(bus_json get-property org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager desktops)
count=$(printf '%s' "$desktops_json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))')
for i in "${!DESKTOP_NAMES[@]}"; do
  name=${DESKTOP_NAMES[$i]}
  if [ "$i" -ge "$count" ]; then
    note "create workspace $((i + 1)) \"$name\""
    CHANGES=$((CHANGES + 1))
    if [ "$DRY" = 0 ]; then
      bus call org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager createDesktop us "$i" "$name"
    fi
    continue
  fi
  read -r id cur < <(printf '%s' "$desktops_json" | python3 -c '
import json,sys
d = json.load(sys.stdin)["data"][int(sys.argv[1])]
print(d[1], d[2])' "$i")
  if [ "$cur" = "$name" ]; then
    note "workspace $((i + 1)) \"$name\" (unchanged)"
  else
    note "rename workspace $((i + 1)): \"$cur\" -> \"$name\""
    CHANGES=$((CHANGES + 1))
    [ "$DRY" = 1 ] || bus call org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager setDesktopName ss "$id" "$name"
  fi
done
if [ "$DRY" = 0 ]; then
  # Remember which workspaces this run created, so fusion-restore.sh can remove them again.
  bus_json get-property org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager desktops |
    python3 -c '
import json,sys
before = {d[1] for d in json.load(open(sys.argv[1]))["data"]}
for d in json.load(sys.stdin)["data"]:
    if d[1] not in before:
        print(d[1])' "$BACKUP/desktops.json" >"$BACKUP/created-desktops"
fi
rows=$(bus get-property org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager rows | awk '{print $2}')
if [ "$rows" != 1 ]; then
  note "workspace rows: $rows -> 1"
  CHANGES=$((CHANGES + 1))
  [ "$DRY" = 1 ] || bus set-property org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager rows u 1
else
  note "workspace rows = 1 (unchanged)"
fi

# ---------- 3. shortcuts ----------

say "Shortcuts"
KEY_1=$((0x31))
for n in 1 2 3 4; do
  # The task manager's "activate task manager entry N" owns Meta+N by default; Meta+N switches
  # workspace in Plasma Fusion (Overview board), so the task manager entries lose it and the
  # workspace switch gets it next to its own keys (Ctrl+FN, Meta+FN).
  shortcut_remove plasmashell "activate task manager entry $n" $((META + KEY_1 + n - 1))
  shortcut_add kwin "Switch to Desktop $n" $((META + KEY_1 + n - 1))
done
if [ "$WINDOWS_SET" = 1 ]; then
  note "Windows-style set (owner decision 6); the keys it takes from other actions are in the backup"
  apply_launcher_keys
  apply_window_keys
elif [ "$SHORTCUTS" = keep ]; then
  note "Windows-style set not applied (--keep-shortcuts)"
else
  note "Windows-style set applied by an earlier run of this version (--shortcuts applies it again)"
fi

# ---------- 4. KWin ----------

say "KWin"
# thumbnail_grid: what the login check writes while another Global Theme is chosen (gate.md).
managed_key kwinrc TabBox LayoutName "$SWITCHER" "$SWITCHER" thumbnail_grid
managed_key kwinrc TabBox DesktopMode "$TABBOX_DESKTOP_MODE" "$TABBOX_DESKTOP_MODE"
managed_key kwinrc TabBox HighlightWindows false false
managed_key kwinrc TabBox DelayTime "$TABBOX_DELAY"
managed_key kwinrc TabBoxAlternative LayoutName "$SWITCHER" "$SWITCHER" thumbnail_grid
managed_key kwinrc TabBoxAlternative DesktopMode "$TABBOX_ALT_DESKTOP_MODE" "$TABBOX_ALT_DESKTOP_MODE"
managed_key kwinrc TabBoxAlternative HighlightWindows false false
package_dir kwin/tabbox "$SWITCHER" >/dev/null || package_dir kwin-wayland/tabbox "$SWITCHER" >/dev/null ||
  note "note: window switcher $SWITCHER is not installed yet; KWin uses its default until it is"
# Hot corner: 9 = no screen edge, 7 = top-left corner.
set_key kwinrc Effect-overview BorderActivate "$([ "$HOT_CORNER" = 1 ] && echo 7 || echo 9)"
managed_key kwinrc Effect-blur BlurStrength "$BLUR_STRENGTH" "$BLUR_STRENGTH"
managed_key kwinrc Effect-blur NoiseStrength "$BLUR_NOISE" "$BLUR_NOISE"
managed_key kwinrc Effect-blur Saturation "$BLUR_SATURATION" "$BLUR_SATURATION"
managed_key kwinrc org.kde.kdecoration2 BorderSizeAuto false false
for script in "${KWIN_SCRIPTS[@]}"; do
  if package_dir kwin/scripts "$script" >/dev/null || package_dir kwin-wayland/scripts "$script" >/dev/null; then
    managed_key kwinrc Plugins "${script}Enabled" true true
  else
    note "note: KWin script $script is not installed yet; run this again after installing it"
  fi
done
# Modal dialogs slide out of their parent (the attach script places them under its title bar).
managed_key kwinrc Plugins sheetEnabled true true
# Tablet navigation (TABLET2 N1): the compiled effect of the plasma-fusion-navigation package. It
# acts only in tablet posture; the login check switches it off after a KWin or Qt update, and the
# plugin stays idle under a KWin it was not built for. KWin's reconfigure does not load a newly
# enabled effect: it is loaded below.
NAV_EFFECT=0
if package_dir kwin/effects plasmafusion_navigation >/dev/null; then
  if grep -q '^navigation[[:space:]]' "$STATE/gate/off" 2>/dev/null; then
    # The login check switched it off after a Plasma update, not the user: its own step below
    # (section "Login check") turns it back on; the effect is loaded there.
    note "kwinrc [Plugins] plasmafusion_navigationEnabled: switched off by the login check (turned back on below)"
  else
    managed_key kwinrc Plugins plasmafusion_navigationEnabled true true
  fi
  NAV_EFFECT=1
else
  note "note: the tablet navigation effect is not installed (plasma-fusion-navigation); tablet posture keeps KWin's edges"
fi
# Snap-zone preview drawn by plasmafusion-snap's outline (KWin resolves the path in the data
# directories; it loads it the next time it shows an outline after a restart of KWin).
if data_path "$OUTLINE_QML" >/dev/null; then
  managed_key kwinrc Outline QmlPath "$OUTLINE_QML" "$OUTLINE_QML"
else
  note "note: $OUTLINE_QML is not installed yet; KWin keeps its own snap-zone outline"
fi
# On-screen keyboard (TABLET T6): off in laptop posture; from then on quick settings switches it with
# the posture. In tablet posture it stays as it is. Another input method the user chose is kept.
if bus get-property org.kde.KWin /org/kde/KWin org.kde.KWin.TabletModeManager tabletMode 2>/dev/null | grep -q true; then
  note "kwinrc [Wayland] InputMethod: tablet posture, left on (quick settings switches it)"
else
  osk=$(system_data_path applications/org.kde.plasma.keyboard.desktop) || osk=$OSK_DESKTOP
  managed_key kwinrc Wayland InputMethod "" "$osk" "$OSK_DESKTOP"
fi
# plasma-keyboard (6.7 and later) shows an accent pop-up when a physical key is held 600 ms while
# it runs, which turns a held key into a pop-up and broke password entry for users
# (discussion.fedoraproject.org/t/194845). Off (TABLET2 P0); the on-screen keys keep their own
# long-press accents.
managed_key plasmakeyboardrc General diacriticsPopupEnabled false
# Esc, Tab and arrow keys on the on-screen keyboard (research E-phone 4.3 MUST; docs/parts/keyboard.md):
# layouts built from plasma-keyboard's installed ones in ~/.local/share/plasma/keyboard/layouts, built
# again at login when plasma-keyboard changes; "plasma-fusion-keyboard-keys remove" turns them off for
# good (this run then keeps them off).
KEYS_TOOL=$(helper_path plasma-fusion-keyboard-keys) || KEYS_TOOL=${HELPER_DIRS[0]}/plasma-fusion-keyboard-keys
if system_data_path plasma/keyboard/layouts >/dev/null && [ -x "$KEYS_TOOL" ]; then
  if [ "$DRY" = 1 ]; then
    note "$("$KEYS_TOOL" refresh --dry-run 2>&1 || true) $("$KEYS_TOOL" status 2>&1)"
  else
    "$KEYS_TOOL" refresh >/dev/null 2>&1 || note "warning: the on-screen keyboard's terminal keys could not be built"
    note "$("$KEYS_TOOL" status 2>&1)"
  fi
else
  note "on-screen keyboard keys: plasma-keyboard or $KEYS_TOOL not installed"
fi
if [ "$DRY" = 0 ]; then
  bus call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null
  # Loads scripts that are enabled but not running yet.
  bus call org.kde.KWin /Scripting org.kde.kwin.Scripting start >/dev/null 2>&1 || true
  for effect in blur overview; do
    bus call org.kde.KWin /Effects org.kde.kwin.Effects reconfigureEffect s "$effect" >/dev/null 2>&1 || true
  done
  if [ "$NAV_EFFECT" = 1 ] && [ "$(kreadconfig6 --file kwinrc --group Plugins --key plasmafusion_navigationEnabled)" = true ]; then
    bus call org.kde.KWin /Effects org.kde.kwin.Effects loadEffect s plasmafusion_navigation >/dev/null 2>&1 || true
  fi
fi
if [ "$WINDOWS_SET" = 1 ]; then
  apply_dock_entry_keys claim
elif [ "$SHORTCUTS" != keep ]; then
  apply_dock_entry_keys migrate
fi

# Tiling: padding on every screen and workspace, set live through a one-shot KWin script
# (the layouts are stored per workspace and screen UUID, so a static kwinrc cannot seed them).
note "tiling: padding $TILE_PADDING px on every screen and workspace; default 25/50/25 layout gets a split right column"
if [ "$DRY" = 0 ]; then
  tile_js=$(mktemp --suffix=.js)
  cat >"$tile_js" <<JS
const padding = $TILE_PADDING;
const near = (a, b) => Math.abs(a - b) < 0.01;
for (const output of workspace.screens) {
    for (const desktop of workspace.desktops) {
        const root = workspace.rootTile(output, desktop);
        if (!root) {
            continue;
        }
        root.padding = padding;
        const t = root.tiles;
        if (t.length === 3 && t.every(c => c.tiles.length === 0)
                && near(t[0].relativeGeometry.width, 0.25) && near(t[1].relativeGeometry.width, 0.5)) {
            t[2].split(2); // KWin.Tile.Vertical: top and bottom halves
        }
    }
}
JS
  bus call org.kde.KWin /Scripting org.kde.kwin.Scripting unloadScript s plasmafusion-oneshot >/dev/null 2>&1 || true
  sid=$(bus call org.kde.KWin /Scripting org.kde.kwin.Scripting loadScript ss "$tile_js" plasmafusion-oneshot | awk '{print $2}')
  if [ "${sid:--1}" -ge 0 ] 2>/dev/null; then
    bus call org.kde.KWin "/Scripting/Script$sid" org.kde.kwin.Script run >/dev/null 2>&1 ||
      bus call org.kde.KWin /Scripting org.kde.kwin.Scripting start >/dev/null
    sleep 1
    bus call org.kde.KWin /Scripting org.kde.kwin.Scripting unloadScript s plasmafusion-oneshot >/dev/null 2>&1 || true
  else
    note "warning: could not load the tiling script"
  fi
  rm -f "$tile_js"
fi

# ---------- 5. shell ----------

say "Shell"
managed_key plasmarc PlasmaToolTips Delay "$TOOLTIP_DELAY" 600
managed_key plasmarc OSD Enabled true true
managed_key plasmarc OSD kbdLayoutChangedEnabled true true
managed_key plasmanotifyrc Notifications PopupPosition TopRight TopRight
managed_key plasmanotifyrc Notifications PopupTimeout "$NOTIFICATION_TIMEOUT" "$NOTIFICATION_TIMEOUT"
# File-copy and other job pop-ups close after the timeout instead of staying until the job ends
# (research D-desktop, complaint 15); their progress stays in the notification history.
managed_key plasmanotifyrc Jobs PermanentPopups false
managed_key krunnerrc General FreeFloating true true
# Keyboard layout badge (quick settings, lock screen): kxkbrc is left alone on purpose. The
# badge shows the current layout's [Layout] DisplayNames entry when the user set one, else its
# short name in capitals ("US" where the board draws its sample "EN"); writing kxkbrc Use or
# LayoutList would replace the layouts KWin takes from the system (XKB_DEFAULT_LAYOUT).
# Quick settings: Meta+A (the Windows-style set; Meta+N then opens its notification list) or Meta+N.
if has_name org.kde.plasmashell; then
  if [ "$WINDOWS_SET" = 1 ]; then
    ensure_widget_shortcut org.plasmafusion.quicksettings "$QS_SHORTCUT" "$QS_SHORTCUT_TEXT" "quick settings" "$QS_OLD_SHORTCUT_TEXT" claim
    ensure_notify_shortcut claim
  elif [ "$SHORTCUTS" = keep ]; then
    ensure_widget_shortcut org.plasmafusion.quicksettings "$QS_OLD_SHORTCUT" "$QS_OLD_SHORTCUT_TEXT" "quick settings" "" free
  else
    # A widget made by a later layout rebuild gets its key again, when nothing else took it.
    ensure_widget_shortcut org.plasmafusion.quicksettings "$QS_SHORTCUT" "$QS_SHORTCUT_TEXT" "quick settings" "" free
    ensure_notify_shortcut free
  fi
else
  note "quick settings: plasmashell is not running (no shortcut set)"
fi

# ---------- 6. lock screen ----------

say "Lock screen"
if wallpaper_meta=$(data_path "wallpapers/$WALLPAPER/metadata.json"); then
  managed_key kscreenlockerrc Greeter WallpaperPlugin org.kde.image org.kde.image
  managed_key kscreenlockerrc Greeter/Wallpaper/org.kde.image/General Image "file://$(dirname "$wallpaper_meta")/" \
    "file://$DATA/wallpapers/$WALLPAPER/" "file:///usr/share/wallpapers/$WALLPAPER/"
else
  note "note: wallpaper $WALLPAPER is not installed; the lock screen keeps its wallpaper"
fi
if [ -x "$HERE/lockscreen-enable.sh" ] && package_dir plasma/shells "$LOCKSHELL" >/dev/null; then
  if [ "$(bash "$HERE/lockscreen-enable.sh" --check 2>/dev/null | sed -n 's/^enabled: *//p' | cut -d' ' -f1)" = yes ]; then
    note "Plasma Fusion lock screen $LOCKSHELL enabled (unchanged)"
  else
    note "enable the Plasma Fusion lock screen $LOCKSHELL (lockscreen-enable.sh; from the next login)"
    CHANGES=$((CHANGES + 1))
    if [ "$DRY" = 0 ]; then
      bash "$HERE/lockscreen-enable.sh" | sed 's/^/  /'
    fi
  fi
else
  note "note: lock screen $LOCKSHELL (or lockscreen-enable.sh) is not installed; Plasma's own lock screen stays"
fi

# ---------- 7. terminal and editor ----------

say "Terminal and editor"
if data_path "konsole/$KONSOLE_PROFILE" >/dev/null; then
  managed_key konsolerc "Desktop Entry" DefaultProfile "$KONSOLE_PROFILE" "$KONSOLE_PROFILE"
else
  note "note: Konsole profile $KONSOLE_PROFILE is not installed"
fi
if data_path "org.kde.syntax-highlighting/themes/$EDITOR_THEME.theme" >/dev/null; then
  for rc in katerc kwriterc; do
    # KTextEditor picks only Breeze Light/Dark on its own, so the theme is set explicitly.
    managed_key "$rc" "KTextEditor Renderer" "Auto Color Theme Selection" false false
    managed_key "$rc" "KTextEditor Renderer" "Color Theme" "$EDITOR_THEME" "$EDITOR_THEME"
  done
else
  note "note: editor colour theme $EDITOR_THEME is not installed"
fi

# ---------- 7b. text rendering ----------

say "Text rendering"
fonts_rc=0
ensure_fonts_conf || fonts_rc=$?
case $fonts_rc in
  0) CHANGES=$((CHANGES + 1)) ;;
  2) ;;
  *) note "warning: ~/.config/$FONTS_CONF_REL was left as it is; Qt and GTK keep their text rendering" ;;
esac
# What the Fonts page writes next to the file (krdb and the Fonts page itself read these).
managed_key kdeglobals General XftAntialias true
managed_key kdeglobals General XftHintStyle hintslight
managed_key kdeglobals General XftSubPixel none
if [ "$DRY" = 0 ] && [ "$fonts_rc" = 0 ]; then
  command -v fc-cache >/dev/null && fc-cache >/dev/null 2>&1 || true
  dbus-send --session --type=signal /KDEPlatformTheme org.kde.KDEPlatformTheme.refreshFonts 2>/dev/null || true
  note "applications started from now on draw greyscale text; running ones after a restart (plasmashell restarts below or at the next login)"
fi

# ---------- 7c. session environment ----------

# Two variables for the whole session, from the next login: startplasma sources this file before
# KWin and plasmashell start and hands the variables to systemd and D-Bus activation.
# - GTK_USE_PORTAL=1: GTK 3 programs (and Firefox) open the KDE file dialog through the desktop
#   portal (GAPS G12; GTK 4 does by itself).
# - QSG_DISTANCEFIELD_ANTIALIASING=gray: Qt Quick draws text of the default type (distance fields,
#   every plain Text item, Plasma Fusion's own among them) with subpixel colours unless told
#   otherwise; fontconfig does not reach that path (qtdeclarative qsgdefaultcontext.cpp). Greyscale,
#   like fonts.conf gives Qt Widgets, Plasma's native text and GTK (GAPS D9, ADAPTIVE fix 20).
say "Session environment"
session_env() {
  cat <<'EOF'
# Plasma Fusion session environment. Installed by tools/device/fusion-config.sh, removed by
# tools/device/fusion-restore.sh. startplasma sources it at login; it only sets variables.
# GTK applications open the KDE file dialog (through the desktop portal).
export GTK_USE_PORTAL=1
# Qt Quick text drawn with distance fields uses greyscale antialiasing (no colour fringes).
export QSG_DISTANCEFIELD_ANTIALIASING=gray
EOF
}
install_text "$CONFIG/$SESSION_ENV_REL" "$(session_env)" && note "from the next login" || true

# ---------- 7d. power tiers ----------

say "Power tiers"
install_user_service plasma-fusion-powerfx.service powerfx

# ---------- 7d1. familiar app icons ----------

# Every installed app's own icon on a Plasma Fusion tile (docs/parts/app-icons.md), drawn into
# ~/.local/share/icons/PlasmaFusion{,-Dark} and kept up to date by the service as apps change.
# plasmafusionrc [Icons] AppIcons=designs keeps the designed tiles (the service then removes them).
say "App icons"
install_user_service plasma-fusion-app-icons.service appicons

# ---------- 7d2. per-app compatibility (HIDPI-1) ----------

# LibreOffice's scale guard: ~/.local/bin/libreoffice, first in the session's PATH, links to
# plasma-fusion-libreoffice, which starts LibreOffice through XWayland only while a screen at 100 %
# sits next to a scaled one (LibreOffice's Qt backends draw twice too big there, tdf#141578), and
# the hidden soffice.desktop names those XWayland windows. Only with LibreOffice installed; a
# ~/.local/bin/libreoffice that is not Plasma Fusion's is left alone.
# shellcheck disable=SC2088 # "~/" is printed, not expanded
if libreoffice_installed; then
  say "LibreOffice scale guard"
  lo_guard=$(helper_path plasma-fusion-libreoffice) || lo_guard=
  lo_link=$HOME/$LO_GUARD_REL
  if [ -z "$lo_guard" ]; then
    note "note: plasma-fusion-libreoffice is not installed yet; run this again after installing it"
  elif [ -e "$lo_link" ] && ! { [ -L "$lo_link" ] && [[ $(readlink "$lo_link") == */plasma-fusion-libreoffice ]]; }; then
    note "note: ~/$LO_GUARD_REL is not Plasma Fusion's; the scale guard is left out"
  elif [ "$(readlink "$lo_link" 2>/dev/null)" = "$lo_guard" ]; then
    note "~/$LO_GUARD_REL -> $lo_guard (unchanged)"
  else
    note "~/$LO_GUARD_REL -> $lo_guard"
    CHANGES=$((CHANGES + 1))
    [ "$DRY" = 1 ] || { mkdir -p "${lo_link%/*}" && ln -sfn "$lo_guard" "$lo_link"; }
  fi
  if lo_entry=$(data_path plasma-fusion/compat/soffice.desktop); then
    if cmp -s "$lo_entry" "$HOME/$LO_ENTRY_REL"; then
      note "~/$LO_ENTRY_REL (unchanged)"
    else
      note "~/$LO_ENTRY_REL from $lo_entry"
      CHANGES=$((CHANGES + 1))
      [ "$DRY" = 1 ] || install -D -m 0644 "$lo_entry" "$HOME/$LO_ENTRY_REL"
    fi
  fi
fi

# ---------- 7e. pen (--pen) ----------

if [ "$PEN" = 1 ]; then
  say "Pen"
  if pen_tool=$(pen_defaults_tool); then
    pen_args=(--no-install)
    [ "$DRY" = 1 ] && pen_args+=(--dry-run)
    if pen_out=$(bash "$pen_tool" "${pen_args[@]}" 2>&1); then
      printf '%s\n' "$pen_out" | sed 's/^/  /'
      pen_backup=$(printf '%s\n' "$pen_out" | sed -n 's/^backup: //p' | tail -n 1)
      [ "$DRY" = 1 ] || [ -z "$pen_backup" ] || printf '%s\n' "$pen_backup" >"$BACKUP/pen-backup"
      printf '%s\n' "$pen_out" | grep -q -- '->' && CHANGES=$((CHANGES + 1))
    else
      printf '%s\n' "$pen_out" | sed 's/^/  /'
      note "warning: pen-defaults.sh failed; the pen settings are as it left them"
    fi
    command -v xournalpp >/dev/null || note "note: Xournal++ is not installed (the notes and whiteboard tiles need it): sudo dnf install xournalpp"
  else
    note "note: tools/pen/pen-defaults.sh is missing; pen defaults not set"
  fi
  if has_name org.kde.plasmashell; then
    ensure_widget_shortcut "$PEN_WIDGET" "$PEN_SHORTCUT" "$PEN_SHORTCUT_TEXT" "pen menu" "" free
  fi
  if [ "$PEN_GARAGE" = 1 ]; then
    install_user_service plasma-fusion-pen-garage.service pen
    [ -f "$CONFIG/systemd/user/plasma-fusion-pen-garage.service" ] || [ "$DRY" = 1 ] ||
      note "note: the garage service is not installed; the pen menu does not mention the garage"
    if [ -f "$CONFIG/systemd/user/plasma-fusion-pen-garage.service" ] || [ "$DRY" = 1 ]; then
      set_key plasmafusionrc Pen GarageService true
    fi
  fi
fi

# ---------- 7f. screens (--screens) ----------

if [ "$SCREENS" = 1 ]; then
  say "Screens"
  if topbars_js=$(package_dir plasma/look-and-feel "$LNF")/contents/layouts/ensure-topbars.js && [ -f "$topbars_js" ]; then
    if ! has_name org.kde.plasmashell; then
      note "note: plasmashell is not running; top bars on other screens not checked"
    elif [ "$DRY" = 1 ]; then
      note "would run $topbars_js in plasmashell (a top bar on every screen)"
    else
      note "run $topbars_js in plasmashell"
      CHANGES=$((CHANGES + 1))
      plasmashell_eval "$(cat "$topbars_js")" | sed 's/^/  /' || note "warning: ensure-topbars.js failed"
    fi
  else
    note "note: ensure-topbars.js is not installed (Global Theme $LNF); top bars on other screens not checked"
  fi
fi

# ---------- 8. login check ----------

# tools/device/gate/plasma-fusion-gate.sh runs at every login from an env stub (startplasma sources
# ~/.config/plasma-workspace/env/*.sh before KWin starts). It falls back to Plasma's own lock screen
# and the Aurorae title bars after a Plasma update until this script records the new versions, and
# switches the Fusion-only parts off while another Global Theme is chosen. See docs/parts/gate.md.
GATE_SRC=$HERE/gate/plasma-fusion-gate.sh
# The Plasma series this Plasma Fusion version was tested with: next to the tools in a package,
# packaging/ in a checkout. deploy records no other series as tested.
GATE_TESTED=
for f in "$HERE/../../tested-plasma.txt" "$HERE/../../packaging/tested-plasma.txt"; do
  [ -f "$f" ] && { GATE_TESTED=$(cd "$(dirname "$f")" && pwd)/tested-plasma.txt; break; }
done
# This Plasma Fusion version (a package's version file, a checkout's VERSION): recorded per user,
# so that the login check can say when a package update has settings to apply.
PF_VERSION=
for f in "$HERE/../../version" "$HERE/../../VERSION"; do
  [ -f "$f" ] && { PF_VERSION=$(tr -d '[:space:]' <"$f"); break; }
done
GATE_ENGINE=$DATA/plasma-fusion/gate/plasma-fusion-gate.sh
sh_quote() { local q="'\\''"; printf "'%s'" "${1//\'/$q}"; }
# bash for the stub and the unit: /bin/bash, or through /usr/bin/env where there is none (NixOS).
gate_bash() { if [ -x /bin/bash ]; then echo /bin/bash; else echo "/usr/bin/env bash"; fi; }
gate_stub() {
  cat <<EOF
# Plasma Fusion login check. Installed by tools/device/fusion-config.sh, removed by
# tools/device/fusion-restore.sh (docs/parts/gate.md in the Plasma Fusion sources).
# startplasma sources every *.sh here in one /bin/sh and waits for it before KWin and plasmashell
# start: the check runs as its own process with a time limit, its output and exit status are
# dropped, and this file sets no variable or shell option and never exits.
[ -r $(sh_quote "$GATE_ENGINE") ] &&
  timeout -k 1 4 $(gate_bash) $(sh_quote "$GATE_ENGINE") login </dev/null >/dev/null 2>&1 || :
# The on-screen keyboard's terminal keys follow plasma-keyboard updates (docs/parts/keyboard.md); the
# tool runs only when a package database (rpm, pacman, dpkg, the Nix profiles) changed since its
# record (a few ms otherwise).
[ -x $(sh_quote "$KEYS_TOOL") ] &&
  { [ ! -e $(sh_quote "$STATE/keyboard-keys") ] ||
    [ /usr/lib/sysimage/rpm/rpmdb.sqlite -nt $(sh_quote "$STATE/keyboard-keys") ] ||
    [ /var/lib/rpm/rpmdb.sqlite -nt $(sh_quote "$STATE/keyboard-keys") ] ||
    [ /var/lib/pacman/local -nt $(sh_quote "$STATE/keyboard-keys") ] ||
    [ /var/lib/dpkg/status -nt $(sh_quote "$STATE/keyboard-keys") ] ||
    [ /nix/var/nix/profiles -nt $(sh_quote "$STATE/keyboard-keys") ]; } &&
  timeout -k 1 3 $(sh_quote "$KEYS_TOOL") refresh </dev/null >/dev/null 2>&1 || :
EOF
}
gate_unit() {
  cat <<EOF
# Plasma Fusion login check: shows the notification the check queued at login, once the desktop
# is up (ordered like systemd's own XDG autostart units). Installed by tools/device/fusion-config.sh,
# removed by tools/device/fusion-restore.sh.
[Unit]
Description=Plasma Fusion login check notification
After=graphical-session.target plasma-workspace.target
PartOf=graphical-session.target
ConditionPathExists=${STATE//%/%%}/gate/notify

[Service]
Type=exec
ExecStart=$(gate_bash) "${GATE_ENGINE//%/%%}" notify
Slice=app.slice
TimeoutStopSec=5s
NoNewPrivileges=yes
MemoryMax=64M

[Install]
WantedBy=xdg-desktop-autostart.target
EOF
}

say "Login check"
if [ ! -f "$GATE_SRC" ]; then
  note "note: $GATE_SRC is missing; the login check is not installed"
else
  unit_changed=0
  if [ -f "$GATE_ENGINE" ] && cmp -s "$GATE_SRC" "$GATE_ENGINE"; then
    note "$GATE_ENGINE (unchanged)"
  else
    note "install $GATE_ENGINE"
    CHANGES=$((CHANGES + 1))
    if [ "$DRY" = 0 ]; then
      mkdir -p "$(dirname "$GATE_ENGINE")"
      cp "$GATE_SRC" "$GATE_ENGINE.tmp" && chmod 0755 "$GATE_ENGINE.tmp" && mv -f "$GATE_ENGINE.tmp" "$GATE_ENGINE"
    fi
  fi
  install_text "$CONFIG/$GATE_STUB_REL" "$(gate_stub)" || true
  install_text "$CONFIG/$GATE_UNIT_REL" "$(gate_unit)" && unit_changed=1
  if [ -L "$CONFIG/$GATE_WANTS_REL" ] && [ "$(readlink "$CONFIG/$GATE_WANTS_REL")" = "../$GATE_UNIT_NAME" ]; then
    note "$CONFIG/$GATE_WANTS_REL (unchanged)"
  else
    note "enable $GATE_UNIT_NAME ($CONFIG/$GATE_WANTS_REL)"
    CHANGES=$((CHANGES + 1))
    unit_changed=1
    if [ "$DRY" = 0 ]; then
      mkdir -p "$(dirname "$CONFIG/$GATE_WANTS_REL")"
      ln -sfn "../$GATE_UNIT_NAME" "$CONFIG/$GATE_WANTS_REL"
    fi
  fi
  if [ "$unit_changed" = 1 ] && [ "$DRY" = 0 ]; then
    systemctl --user daemon-reload 2>/dev/null ||
      note "note: systemctl --user daemon-reload failed; the unit is read at the next login"
  fi
  # This run is the test of the installed Plasma: record it, and turn back on what a login switched
  # off (the compiled decoration; the lock screen came back in section 6).
  if [ "$DRY" = 1 ]; then
    PF_GATE_TOOL=$HERE/fusion-config.sh PF_GATE_TESTED=$GATE_TESTED bash "$GATE_SRC" deploy --dry-run || note "warning: the login check could not read the installed versions"
  elif PF_GATE_TOOL=$HERE/fusion-config.sh PF_GATE_TESTED=$GATE_TESTED bash "$GATE_ENGINE" deploy; then
    bus call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null 2>&1 || true
    # A navigation effect the login check had switched off is on again: KWin's reconfigure does not
    # load a newly enabled effect (PLASMA-68 upgrade test: enabled, not loaded until the next login).
    if [ "$NAV_EFFECT" = 1 ] && [ "$(kreadconfig6 --file kwinrc --group Plugins --key plasmafusion_navigationEnabled)" = true ]; then
      bus call org.kde.KWin /Effects org.kde.kwin.Effects loadEffect s plasmafusion_navigation >/dev/null 2>&1 || true
    fi
  else
    note "warning: the login check could not record the installed versions; the next login uses the safe fallback"
  fi
fi

# ---------- 9. configuration version ----------

say "Configuration version"
set_key plasmafusionrc Config FusionConfigVersion "$CONFIG_VERSION"
if [ ${#UPGRADE_LOG[@]} -gt 0 ]; then
  note "upgrade $PREV_VERSION -> $CONFIG_VERSION: $(printf '%s\n' "${UPGRADE_LOG[@]}" | grep -c '^changed') setting(s) changed, $(printf '%s\n' "${UPGRADE_LOG[@]}" | grep -c '^kept') user value(s) kept ($STATE/config-changes)"
  if [ "$DRY" = 0 ]; then
    # For the settings page ("What changed"): one line per setting, tab separated:
    # status (changed|kept) file group key old new; old "__plasma_fusion_unset__" = not set.
    { printf '# Plasma Fusion configuration upgrade %s -> %s, %s, backup %s\n' "$PREV_VERSION" "$CONFIG_VERSION" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BACKUP"
      printf '%s\n' "${UPGRADE_LOG[@]}"; } >"$STATE/config-changes.tmp" && mv -f "$STATE/config-changes.tmp" "$STATE/config-changes"
  fi
fi

if [ "$DRY" = 1 ]; then
  say "Dry run finished: $CHANGES change(s) would be made."
else
  echo "$CHANGES" >"$BACKUP/changes"
  # The version these settings came from (plasma-fusion status; the login check's update notice).
  [ -z "$PF_VERSION" ] || { mkdir -p "$STATE" && printf '%s\n' "$PF_VERSION" >"$STATE/setup-version"; }
  say "Done: $CHANGES change(s). Restore with: $(dirname "$0")/fusion-restore.sh $BACKUP"
  say "Log out and back in once so the splash screen, fonts and every application pick up the theme."
fi
