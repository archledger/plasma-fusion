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
#   --light            apply Plasma Fusion Light instead of Plasma Fusion Dark
#   --auto             switch between Light and Dark with the time of day ("Follow sunset")
#   --reset-layout     always rebuild the top bar, dock and desktop cards
#   --keep-layout      never touch the panels (appearance and settings only)
#   --hot-corner       let the top-left screen corner open Overview (off by default)
#   -h, --help
#
# By default the layout is rebuilt only when the current panels are not the Plasma Fusion
# layout. Running it twice gives the same result. Before changing anything it copies every
# file it may touch, plus the virtual desktops and shortcuts it changes, to
# ~/.local/state/plasma-fusion/backup-<UTC timestamp>/; tools/device/fusion-restore.sh puts
# that back.
#
# What it sets (see docs/parts/lookandfeel.md for the reasons):
#   Global Theme       plasma-apply-lookandfeel -a org.plasmafusion.{dark,light}.desktop
#                      [--resetLayout]; kdeglobals [KDE] DefaultDarkLookAndFeel,
#                      DefaultLightLookAndFeel, AutomaticLookAndFeel
#   Top bar pop-ups    plasmashellrc [PlasmaViews][Panel <top bar id>] floatingApplets 1 (stock
#                      pop-ups float under the bar with rounded corners; read at shell start)
#   Quick settings     Meta+N opens the quick-settings pop-up, only when the widget has no
#                      shortcut yet and nothing else uses Meta+N (the dead entry of a widget
#                      dropped by an earlier layout rebuild is removed first)
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
#   Tooltips           plasmarc [PlasmaToolTips] Delay 600
#   OSD                plasmarc [OSD] Enabled, kbdLayoutChangedEnabled
#   Notifications      plasmanotifyrc [Notifications] PopupPosition TopRight, PopupTimeout 5000
#   KRunner            krunnerrc [General] FreeFloating true (centred, as the dock's Search)
#   Terminal, editor   konsolerc default profile "Plasma Fusion"; katerc/kwriterc colour theme
#                      "Plasma Fusion Dark" (the boards draw a dark terminal and code window in
#                      both variants)
set -euo pipefail

DARK=org.plasmafusion.dark.desktop
LIGHT=org.plasmafusion.light.desktop
SWITCHER=org.plasmafusion.switcher
KWIN_SCRIPTS=(plasmafusion-snap plasmafusion-attach)
DESKTOP_NAMES=(Work Design Media Chat)
TILE_PADDING=6
BLUR_STRENGTH=13
BLUR_NOISE=0
BLUR_SATURATION=140
TOOLTIP_DELAY=600
NOTIFICATION_TIMEOUT=5000
# Global shortcut for the quick-settings pop-up (org.plasmafusion.quicksettings): Qt key code
# of Meta+N and its QKeySequence text. Meta+Alt+S is Plasma's screen-reader toggle and Meta+A
# walks through activities, so the notification key of other desktops is used.
QS_SHORTCUT=$((0x10000000 + 0x4e))
QS_SHORTCUT_TEXT=Meta+N
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

DRY=0 VARIANT=dark AUTO=0 LAYOUT=auto HOT_CORNER=0 INSTALL=
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
    --reset-layout) LAYOUT=reset ;;
    --keep-layout) LAYOUT=keep ;;
    --hot-corner) HOT_CORNER=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[ "$VARIANT" = light ] && LNF=$LIGHT || LNF=$DARK
HERE=$(cd "$(dirname "$0")" && pwd)

CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/plasma-fusion
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

# Run from outside the session (SSH with only the session bus): the Qt tools need the session's
# display, and the configuration cascade its XDG_CONFIG_DIRS (with ~/.config/kdedefaults), so
# take them from the running plasmashell. Without one, Qt tools run offscreen.
OUTSIDE=0
if [ -z "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
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
if [ -n "$INSTALL" ]; then
  [ -f "$INSTALL/.local/share/plasma/look-and-feel/$LNF/metadata.json" ] ||
    die "$INSTALL is not a Plasma Fusion build (no .local/share/plasma/look-and-feel/$LNF)"
else
  package_dir plasma/look-and-feel "$LNF" >/dev/null ||
    die "Global Theme $LNF is not installed (run with --install stage/home, or copy the build first)"
fi

# ---------- backup ----------

BACKUP_FILES=(
  kdeglobals kwinrc kglobalshortcutsrc plasmarc plasmanotifyrc plasmashellrc
  plasma-org.kde.plasma.desktop-appletsrc ksplashrc kcminputrc krunnerrc kscreenlockerrc
  konsolerc katerc kwriterc
  gtk-3.0/settings.ini gtk-4.0/settings.ini xsettingsd/xsettingsd.conf Trolltech.conf
  gtk-3.0/gtk.css gtk-4.0/gtk.css gtk-3.0/plasma-fusion.css gtk-4.0/plasma-fusion.css
  systemd/user/plasma-kwin_wayland.service.d/plasma-fusion-lockscreen.conf
)
# Configuration files the build would install (--install) are saved as well.
if [ -n "$INSTALL" ] && [ -d "$INSTALL/.config" ]; then
  while IFS= read -r -d '' f; do
    f=${f#"$INSTALL/.config/"}
    case " ${BACKUP_FILES[*]} " in *" $f "*) ;; *) BACKUP_FILES+=("$f") ;; esac
  done < <(find "$INSTALL/.config" -type f -print0 | sort -z)
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
  {
    echo "created=$stamp"
    echo "lookandfeel=$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)"
    echo "automatic=$(kreadconfig6 --file kdeglobals --group KDE --key AutomaticLookAndFeel)"
    echo "variant=$VARIANT"
  } >"$BACKUP/info"
  bus_json get-property org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager desktops >"$BACKUP/desktops.json"
  bus get-property org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager rows | awk '{print $2}' >"$BACKUP/rows"
  : >"$BACKUP/shortcuts"
  : >"$BACKUP/created-desktops"
  say "backup: $BACKUP"
}

# ---------- helpers ----------

# Human-readable key names for Qt key codes (printing only).
keyname() {
  python3 - "$@" <<'PY'
import sys
mods = [(0x10000000, "Meta"), (0x04000000, "Ctrl"), (0x08000000, "Alt"), (0x02000000, "Shift")]
special = {0x01000001: "Tab", 0x01000002: "Backtab", 0x60: "`", 0x7e: "~"}
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

# Set one config key if it differs. $1 file, $2 group (nested groups separated by "/"),
# $3 key, $4 value
set_key() {
  local cur g groups=()
  IFS=/ read -r -a g <<<"$2"
  for part in "${g[@]}"; do groups+=(--group "$part"); done
  cur=$(kreadconfig6 --file "$1" "${groups[@]}" --key "$3" 2>/dev/null || true)
  if [ "$cur" = "$4" ]; then
    note "$1 [${2//\//][}] $3 = $4 (unchanged)"
    return 0
  fi
  note "$1 [${2//\//][}] $3: ${cur:-<unset>} -> $4"
  CHANGES=$((CHANGES + 1))
  [ "$DRY" = 1 ] || kwriteconfig6 --file "$1" "${groups[@]}" --key "$3" --notify "$4"
}

# Current keys of a global shortcut as Qt key codes. $1 component, $2 action
shortcut_get() {
  bus_json call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel shortcut as 4 "$1" "$2" "" "" |
    python3 -c 'import json,sys; print(" ".join(str(k) for k in json.load(sys.stdin)["data"][0]))'
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

restart_plasmashell() {
  local pid env_file=
  if shell_is_systemd_unit; then
    systemctl --user restart plasma-plasmashell.service
  else
    # Started from a terminal in the session, the new shell gets this script's environment.
    # Run from outside the session (SSH), it gets the environment of the shell it replaces.
    if [ "$OUTSIDE" = 1 ]; then
      pid=$(bus call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.kde.plasmashell 2>/dev/null | awk '{print $2}')
      if [ -n "$pid" ] && [ -r "/proc/$pid/environ" ]; then
        env_file=$(mktemp)
        cp "/proc/$pid/environ" "$env_file"
      fi
    fi
    kquitapp6 plasmashell >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do has_name org.kde.plasmashell || break; sleep 0.5; done
    mkdir -p "$STATE"
    if [ -n "$env_file" ]; then
      local vars=()
      mapfile -d '' vars <"$env_file"
      rm -f "$env_file"
      env -i "${vars[@]}" setsid -f plasmashell >>"$STATE/plasmashell.log" 2>&1 </dev/null
    else
      setsid -f plasmashell >>"$STATE/plasmashell.log" 2>&1 </dev/null
    fi
  fi
  for _ in $(seq 1 60); do has_name org.kde.plasmashell && break; sleep 0.5; done
  wait_panels 1 >/dev/null
  sleep 2
}

# Panel thickness is clamped to the Plasma style's minimum while a new panel view loads, which
# can briefly be the style's unprefixed (dock-sized) frame; set it again once the panels exist.
fix_panel_thickness() {
  plasmashell_eval '
var ps = panels(), fixed = [];
for (var i = 0; i < ps.length; i++) {
    var p = ps[i];
    if (p.location === "top" && p.lengthMode === "fill" && p.height !== 34) { p.height = 34; fixed.push("top bar"); }
    if (p.location === "bottom" && p.floating && p.lengthMode === "fit" && p.height !== 88) { p.height = 88; fixed.push("dock"); }
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
  holders=$(bus_json call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel globalShortcutsByKey "(ai)(i)" 1 "$1" 0 2>/dev/null |
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

# Meta+N for the quick-settings pop-up, when the widget has no shortcut of its own yet and no
# other component uses the key (a dead entry of a removed widget is cleared first).
# fusion-restore.sh removes it again (recorded like the other shortcuts, with no previous key).
ensure_quicksettings_shortcut() {
  local found entry id cur free released
  found=$(plasmashell_eval '
var out = [], ps = panels();
for (var i = 0; i < ps.length; i++) {
    var ws = ps[i].widgets("org.plasmafusion.quicksettings");
    for (var j = 0; j < ws.length; j++) out.push(ws[j].id + "=" + ws[j].globalShortcut);
}
print(out.join(" "));' || true)
  [ -n "$found" ] || { note "quick settings: widget not in a panel (no shortcut set)"; return 0; }
  for entry in $found; do
    id=${entry%%=*} cur=${entry#*=}
    if [ -n "$cur" ]; then
      note "quick settings widget $id shortcut = $cur (kept)"
      continue
    fi
    released=1
    release_dead_widget_key "$QS_SHORTCUT" && released=0
    free=$(bus call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel globalShortcutAvailable "(ai)s" 1 "$QS_SHORTCUT" plasmashell 2>/dev/null | awk '{print $2}' || true)
    # A dry run removes nothing, so the key only counts as free after the removal it would do.
    [ "$DRY" = 1 ] && [ "$released" = 0 ] && free=true
    if [ "$free" != true ]; then
      note "quick settings widget $id: $QS_SHORTCUT_TEXT is in use or could not be checked (no shortcut set)"
      continue
    fi
    note "quick settings widget $id shortcut: <none> -> $QS_SHORTCUT_TEXT"
    CHANGES=$((CHANGES + 1))
    [ "$DRY" = 1 ] && continue
    printf '%s\t%s\t%s\n' plasmashell "activate widget $id" "" >>"$BACKUP/shortcuts"
    plasmashell_eval "
var ps = panels();
for (var i = 0; i < ps.length; i++) {
    var w = ps[i].widgetById($id);
    if (w) { w.globalShortcut = \"$QS_SHORTCUT_TEXT\"; }
}" >/dev/null
  done
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
  if [ -d "$src/.config" ]; then
    while IFS= read -r -d '' f; do
      f=${f#"$src/.config/"}
      dest=$CONFIG/$f
      if [ -e "$dest" ] && cmp -s "$src/.config/$f" "$dest"; then
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
        cp "$src/.config/$f" "$dest"
      fi
    done < <(find "$src/.config" -type f -print0 | sort -z)
  fi
  if [ "$DRY" = 0 ]; then
    command -v fc-cache >/dev/null && fc-cache -f >/dev/null 2>&1 || true
    command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
  fi
}

# ---------- 1. Global Theme and layout ----------

[ "$DRY" = 1 ] && say "Dry run: nothing is changed." || make_backup
[ -z "$INSTALL" ] || install_build

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
# Written before the (last) restart, which is what applies it.
if has_name org.kde.plasmashell && fusion_layout_present; then
  if ensure_floating_applets && [ -z "$restart_why" ]; then
    restart_why="apply the top bar's floating pop-ups"
  fi
fi
if [ -n "$restart_why" ]; then
  note "restart plasmashell ($restart_why)"
  [ "$DRY" = 1 ] || restart_plasmashell
fi
if [ "$DRY" = 0 ] && has_name org.kde.plasmashell && fusion_layout_present; then
  note "panel thickness: $(fix_panel_thickness)"
fi
set_key kdeglobals KDE DefaultDarkLookAndFeel "$DARK"
set_key kdeglobals KDE DefaultLightLookAndFeel "$LIGHT"
set_key kdeglobals KDE AutomaticLookAndFeel "$([ "$AUTO" = 1 ] && echo true || echo false)"

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
META=$((0x10000000)) KEY_1=$((0x31))
for n in 1 2 3 4; do
  # The task manager's "activate task manager entry N" owns Meta+N by default; Meta+N switches
  # workspace in Plasma Fusion (Overview board), so the task manager entries lose it and the
  # workspace switch gets it next to its own keys (Ctrl+FN, Meta+FN).
  shortcut_remove plasmashell "activate task manager entry $n" $((META + KEY_1 + n - 1))
  shortcut_add kwin "Switch to Desktop $n" $((META + KEY_1 + n - 1))
done

# ---------- 4. KWin ----------

say "KWin"
set_key kwinrc TabBox LayoutName "$SWITCHER"
set_key kwinrc TabBox DesktopMode "$TABBOX_DESKTOP_MODE"
set_key kwinrc TabBox HighlightWindows false
set_key kwinrc TabBoxAlternative LayoutName "$SWITCHER"
set_key kwinrc TabBoxAlternative DesktopMode "$TABBOX_ALT_DESKTOP_MODE"
set_key kwinrc TabBoxAlternative HighlightWindows false
package_dir kwin/tabbox "$SWITCHER" >/dev/null || package_dir kwin-wayland/tabbox "$SWITCHER" >/dev/null ||
  note "note: window switcher $SWITCHER is not installed yet; KWin uses its default until it is"
# Hot corner: 9 = no screen edge, 7 = top-left corner.
set_key kwinrc Effect-overview BorderActivate "$([ "$HOT_CORNER" = 1 ] && echo 7 || echo 9)"
set_key kwinrc Effect-blur BlurStrength "$BLUR_STRENGTH"
set_key kwinrc Effect-blur NoiseStrength "$BLUR_NOISE"
set_key kwinrc Effect-blur Saturation "$BLUR_SATURATION"
set_key kwinrc org.kde.kdecoration2 BorderSizeAuto false
for script in "${KWIN_SCRIPTS[@]}"; do
  if package_dir kwin/scripts "$script" >/dev/null || package_dir kwin-wayland/scripts "$script" >/dev/null; then
    set_key kwinrc Plugins "${script}Enabled" true
  else
    note "note: KWin script $script is not installed yet; run this again after installing it"
  fi
done
# Modal dialogs slide out of their parent (the attach script places them under its title bar).
set_key kwinrc Plugins sheetEnabled true
# Snap-zone preview drawn by plasmafusion-snap's outline (KWin resolves the path in the data
# directories; it loads it the next time it shows an outline after a restart of KWin).
if [ -f "$DATA/$OUTLINE_QML" ] || { [ -n "$INSTALL" ] && [ -f "$INSTALL/.local/share/$OUTLINE_QML" ]; }; then
  set_key kwinrc Outline QmlPath "$OUTLINE_QML"
else
  note "note: $OUTLINE_QML is not installed yet; KWin keeps its own snap-zone outline"
fi
if [ "$DRY" = 0 ]; then
  bus call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null
  # Loads scripts that are enabled but not running yet.
  bus call org.kde.KWin /Scripting org.kde.kwin.Scripting start >/dev/null 2>&1 || true
  for effect in blur overview; do
    bus call org.kde.KWin /Effects org.kde.kwin.Effects reconfigureEffect s "$effect" >/dev/null 2>&1 || true
  done
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
set_key plasmarc PlasmaToolTips Delay "$TOOLTIP_DELAY"
set_key plasmarc OSD Enabled true
set_key plasmarc OSD kbdLayoutChangedEnabled true
set_key plasmanotifyrc Notifications PopupPosition TopRight
set_key plasmanotifyrc Notifications PopupTimeout "$NOTIFICATION_TIMEOUT"
set_key krunnerrc General FreeFloating true
# Keyboard layout badge (quick settings, lock screen): kxkbrc is left alone on purpose. The
# badge shows the current layout's [Layout] DisplayNames entry when the user set one, else its
# short name in capitals ("US" where the board draws its sample "EN"); writing kxkbrc Use or
# LayoutList would replace the layouts KWin takes from the system (XKB_DEFAULT_LAYOUT).
if has_name org.kde.plasmashell; then
  ensure_quicksettings_shortcut
fi

# ---------- 6. lock screen ----------

say "Lock screen"
if package_dir wallpapers "$WALLPAPER" >/dev/null; then
  set_key kscreenlockerrc Greeter WallpaperPlugin org.kde.image
  set_key kscreenlockerrc Greeter/Wallpaper/org.kde.image/General Image "file://$DATA/wallpapers/$WALLPAPER/"
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
if [ -f "$DATA/konsole/$KONSOLE_PROFILE" ] || { [ -n "$INSTALL" ] && [ -f "$INSTALL/.local/share/konsole/$KONSOLE_PROFILE" ]; }; then
  set_key konsolerc "Desktop Entry" DefaultProfile "$KONSOLE_PROFILE"
else
  note "note: Konsole profile $KONSOLE_PROFILE is not installed"
fi
if [ -f "$DATA/org.kde.syntax-highlighting/themes/$EDITOR_THEME.theme" ] ||
   { [ -n "$INSTALL" ] && [ -f "$INSTALL/.local/share/org.kde.syntax-highlighting/themes/$EDITOR_THEME.theme" ]; }; then
  for rc in katerc kwriterc; do
    # KTextEditor picks only Breeze Light/Dark on its own, so the theme is set explicitly.
    set_key "$rc" "KTextEditor Renderer" "Auto Color Theme Selection" false
    set_key "$rc" "KTextEditor Renderer" "Color Theme" "$EDITOR_THEME"
  done
else
  note "note: editor colour theme $EDITOR_THEME is not installed"
fi

if [ "$DRY" = 1 ]; then
  say "Dry run finished: $CHANGES change(s) would be made."
else
  echo "$CHANGES" >"$BACKUP/changes"
  say "Done: $CHANGES change(s). Restore with: $(dirname "$0")/fusion-restore.sh $BACKUP"
  say "Log out and back in once so the splash screen, fonts and every application pick up the theme."
fi
