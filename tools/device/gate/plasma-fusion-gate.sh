#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasma Fusion login check ("the gate"): keeps the Plasma Fusion parts that depend on Plasma
# internals from breaking a login after a Plasma update, and switches the Fusion-only parts off
# while another Global Theme is chosen. See docs/parts/gate.md.
#
#   plasma-fusion-gate.sh [login]             what every login runs (through the env stub)
#   plasma-fusion-gate.sh check               print what a login would change; change nothing
#   plasma-fusion-gate.sh deploy [--dry-run]  record the installed Plasma as tested and turn back on
#                                             what a login switched off (fusion-config.sh runs it)
#   plasma-fusion-gate.sh notify              show the queued notification (notify unit)
#   plasma-fusion-gate.sh status              print the record, the switched-off parts, the log tail
#
# Installed by tools/device/fusion-config.sh as ~/.local/share/plasma-fusion/gate/plasma-fusion-gate.sh
# with the stub ~/.config/plasma-workspace/env/plasma-fusion-gate.sh, which startplasma sources
# before it starts KWin, plasmashell and the Plasma systemd units (startplasma then reloads the
# systemd user manager, so a drop-in moved aside here already counts for this login).
#
# 1. Plasma updates. While the Plasma Fusion lock screen (the kwin_wayland drop-in of
#    lockscreen-enable.sh), the compiled decoration (kwinrc [org.kde.kdecoration2]
#    library=org.plasmafusion.decoration), the tablet navigation effect (kwinrc [Plugins]
#    plasmafusion_navigationEnabled, built against KWin's internal classes) or the Plasma Fusion
#    desktop (a desktop containment plugin=org.plasmafusion.desktop in the layout file, a fork of
#    plasma-desktop's Folder View QML) is on, the installed
#    versions of PACKAGES (from the package database: rpm, pacman, dpkg or the Nix store; cached by
#    the database's size and time) and the lock-screen package files (sha256) are compared with what
#    fusion-config.sh recorded as tested. On a difference, without a readable record, or when no
#    package database reports the versions, the drop-in is moved aside (stock lock screen), the
#    decoration becomes the Plasma Fusion Aurorae theme of the current variant (-Left and its button
#    lists for ButtonStyle=LeftCircles), the navigation effect is switched off, the desktop becomes
#    Plasma's Folder View (org.kde.plasma.folder: the same keys, so icons and cards stay) and one
#    notification
#    is queued for after the desktop is up. The next login with matching versions, or the next
#    fusion-config.sh run, turns them back on.
# 2. Switching back. While the Global Theme (kdeglobals [KDE] LookAndFeelPackage) is not Plasma
#    Fusion Dark or Light, the lock-screen drop-in, the plasmafusion-snap, plasmafusion-attach and
#    plasmafusion-tablet KWin scripts, the navigation effect, kwinrc [Outline] QmlPath, the Fusion
#    window switcher, the
#    on-screen keyboard policy's kwinrc [Wayland] InputMethod value (so Fedora's default keyboard
#    returns) and the plasma-fusion-powerfx and plasma-fusion-pen-garage user services (their
#    graphical-session.target.wants links; startplasma reloads systemd after this check, so they do
#    not start at this login) and the Plasma Fusion desktop (Folder View instead) are switched off,
#    once: a part the user turns on again is left on. A
#    Plasma Fusion theme turns them back on at the next login.
# 3. A missing decoration plugin or desktop package. While the compiled decoration is named (by the
#    user or by the Global Theme's defaults) but not installed, the title bars become the matching
#    Plasma Fusion Aurorae theme at login, without a notification; while a desktop names
#    org.plasmafusion.desktop and that package is missing, it becomes Folder View. Both switch back
#    at the first login after the plugin or package is installed again.
#
# Every change is recorded first (~/.local/state/plasma-fusion/gate/off) and undone only while the
# value is still the one written here. With matching versions and a Fusion theme nothing changes.
# At login it runs no GUI program, makes no D-Bus or systemd call and always exits 0 (the stub also
# limits its run time). Log: ~/.local/state/plasma-fusion/gate.log.
#
# Test hooks (never set in a real session): PF_GATE_FAKE_VERSIONS="kwin=6.8.0 kscreenlocker=6.8.0"
# replaces installed versions in memory (never cached); PF_GATE_RPM names the rpm program;
# PF_GATE_ROOT is put in front of the package databases' paths and the Nix system profile.

# The package databases, in this order: the first that knows one of its packages answers (a foreign
# package manager installed next to the system's has none of them). Each names the packages its own
# way, in the same order. Versions are upstream only: a distribution rebuild (-2.fc44, pkgrel,
# Debian revision, epoch) keeps the interfaces Fusion uses.
#   rpm     rpm -q (Fedora)
#   pacman  pacman -Q (Arch)
#   dpkg    source packages (Debian): the binary names change between releases
#   nix     the store path names in the closure of the NixOS system profile
DBS=(rpm pacman dpkg nix)
declare -A DB_PACKAGES=(
  [rpm]="plasma-workspace plasma-desktop kwin kscreenlocker libplasma kdecoration qt6-qtbase qt6-qtdeclarative"
  [pacman]="plasma-workspace plasma-desktop kwin kscreenlocker libplasma kdecoration qt6-base qt6-declarative"
  [dpkg]="plasma-workspace plasma-desktop kwin kscreenlocker libplasma kdecoration qt6-base qt6-declarative"
  [nix]="plasma-workspace plasma-desktop kwin kscreenlocker libplasma kdecoration qtbase qtdeclarative"
)
declare -A DB_NAME=([rpm]=rpm [pacman]=pacman [dpkg]=dpkg [nix]=Nix)
# rpm's query format; with the package names it keys the cache (the other databases use their name).
QUERY_FORMAT='%{NAME}=%{VERSION}\n'
# Every binary package with its state and source package (the binary names differ between releases).
# shellcheck disable=SC2016 # dpkg-query's own ${field} syntax
DPKG_FORMAT='${db:Status-Status} ${source:Package}=${source:Version}\n'
SYSROOT=${PF_GATE_ROOT:-}
NIX_SW=$SYSROOT/run/current-system/sw
# The database the versions come from; rpm until one answers (records and caches without a db=
# line come from rpm, the only database before).
DB=rpm
read -r -a PACKAGES <<<"${DB_PACKAGES[rpm]}"
FORMAT=1
DARK=org.plasmafusion.dark.desktop
LIGHT=org.plasmafusion.light.desktop
LOCKSHELL=org.plasmafusion.lockshell
CPP_DECO=org.plasmafusion.decoration
AURORAE=org.kde.kwin.aurorae.v2
BREEZE_DECO=org.kde.breeze
SWITCHER=org.plasmafusion.switcher
KWIN_SWITCHER=thumbnail_grid
# The Plasma Fusion desktop and what it falls back to (the plasmashell layout file's containments).
DESKTOP=org.plasmafusion.desktop
FOLDER=org.kde.plasma.folder
APPLETSRC=plasma-org.kde.plasma.desktop-appletsrc
PARTS=(lockscreen decoration navigation desktop snap attach outline switcher tablet inputmethod powerfx pengarage)
# The on-screen keyboard values the Fusion keyboard policy writes (quick settings, fusion-config.sh):
# empty (keyboard off in laptop posture) and plasma-keyboard's desktop file in a system data
# directory (/usr/share/applications on Fedora). Any other input method is the user's.
OSK=org.kde.plasma.keyboard.desktop
# User services enabled by fusion-config.sh (WantedBy=graphical-session.target): part -> unit.
declare -A UNIT=([powerfx]=plasma-fusion-powerfx.service [pengarage]=plasma-fusion-pen-garage.service)
WANTS_REL=systemd/user/graphical-session.target.wants
# Package names in records, the cache and rpm output. POSIX classes, not ranges: in some locales
# (tr_TR, et_EE...) [A-Za-z] does not match every ASCII letter, and the login runs in the user's.
NAME_RE='^[[:alnum:]._+-]+$'

MODE=${1:-login}
DRY=0
[ "$MODE" = check ] && DRY=1
[ "${2:-}" = --dry-run ] && DRY=1
[ -n "${HOME:-}" ] || exit 0

CONFIG=${XDG_CONFIG_HOME:-$HOME/.config}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
ROOT=${XDG_STATE_HOME:-$HOME/.local/state}/plasma-fusion
GATE=$ROOT/gate
LOG=$ROOT/gate.log
DROPIN_DIR=$CONFIG/systemd/user/plasma-kwin_wayland.service.d
DROPIN=$DROPIN_DIR/plasma-fusion-lockscreen.conf
SAVED_DROPIN=$GATE/saved/plasma-fusion-lockscreen.conf
T0=${EPOCHREALTIME/[.,]/}

LINES=()
say() { LINES+=("$*"); }

# ---------- configuration files ----------

# Every key the check reads, from the user file, ~/.config/kdedefaults (a Global Theme's layer) and
# the system directories, in one awk run. INI[layer|file|group|key] is the key's state: "=value",
# "[$flags]=value" for a key with KConfig flags such as [$e], or "-" for a key marked deleted
# ([$d]) or removed here.
declare -A INI=()
LAYERS=(u d)
declare -A LAYER_DIR=([u]="$CONFIG" [d]="$CONFIG/kdedefaults")
WANT='KDE|LookAndFeelPackage
KDE|AutomaticLookAndFeel
KDE|DefaultLightLookAndFeel
KDE|DefaultDarkLookAndFeel
General|ColorScheme
Colors:Window|BackgroundNormal
Decoration|ButtonStyle
org.kde.kdecoration2|library
org.kde.kdecoration2|theme
org.kde.kdecoration2|ButtonsOnLeft
org.kde.kdecoration2|ButtonsOnRight
Plugins|plasmafusion-snapEnabled
Plugins|plasmafusion-attachEnabled
Plugins|plasmafusion-tabletEnabled
Plugins|plasmafusion_navigationEnabled
Wayland|InputMethod
Outline|QmlPath
TabBox|LayoutName
TabBox|DesktopMode
TabBox|HighlightWindows
TabBoxAlternative|LayoutName
TabBoxAlternative|DesktopMode
TabBoxAlternative|HighlightWindows'
# KConfig syntax: [Group] headers (group flags such as [$i] dropped), key=value with the key and
# value trimmed, key[$flags]=value, key[$d] (deleted), key[locale]=value (ignored), # comments.
INI_AWK='
BEGIN { n = split(want, w, "\n"); for (i = 1; i <= n; i++) if (w[i] != "") wanted[w[i]] = 1 }
function emit(k, s) { if ((grp "|" k) in wanted) print L "\t" grp "|" k "\t" s }
FNR == 1 { grp = "" }
{
  line = $0
  sub(/\r$/, "", line); sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
  if (line == "" || substr(line, 1, 1) == "#") next
  if (substr(line, 1, 1) == "[") {
    g = line
    while (g ~ /\[\$[a-zA-Z]*\]$/) sub(/\[\$[a-zA-Z]*\]$/, "", g)
    grp = substr(g, 2, length(g) - 2)
    next
  }
  eq = index(line, "=")
  if (eq == 0) {
    if (line ~ /\[\$[a-zA-Z]*d[a-zA-Z]*\]$/) { k = line; sub(/\[.*$/, "", k); emit(k, "-") }
    next
  }
  k = substr(line, 1, eq - 1); v = substr(line, eq + 1)
  sub(/[ \t]+$/, "", k); sub(/^[ \t]+/, "", v)
  if (k ~ /\]$/) {
    opt = k; sub(/^[^[]*\[/, "", opt); sub(/\]$/, "", opt)
    if (substr(opt, 1, 1) != "$") next
    sub(/\[.*$/, "", k)
    if (opt ~ /d/) { emit(k, "-"); next }
    emit(k, "[" opt "]=" v)
    next
  }
  emit(k, "=" v)
}'

# The top-level containment groups of the user's layout file ("Containments][N", as the awk below
# names a [Containments][N] header); their plugin keys are read with the others.
DESK_GROUPS=()
load_ini() {
  local d dirs n=0 seen=: f l args=() lbl spec st g want=$WANT
  if [ -f "$CONFIG/$APPLETSRC" ]; then
    while IFS= read -r g; do
      g=${g%$'\r'}
      [[ $g =~ ^\[Containments\]\[[[:digit:]]+\]$ ]] || continue
      g=${g#[}
      DESK_GROUPS+=("${g%]}")
      want+=$'\n'"${g%]}|plugin"
    done < <(LC_ALL=C grep -E '^\[Containments\]\[[0-9]+\]' "$CONFIG/$APPLETSRC" 2>/dev/null)
  fi
  IFS=: read -r -a dirs <<<"${XDG_CONFIG_DIRS:-/etc/xdg}"
  for d in "${dirs[@]}"; do
    d=${d%/}
    [ -n "$d" ] && [ "$d" != "$CONFIG/kdedefaults" ] && [ "$d" != "$CONFIG" ] || continue
    case $seen in *":$d:"*) continue ;; esac
    seen+="$d:"
    LAYERS+=("s$n")
    LAYER_DIR[s$n]=$d
    n=$((n + 1))
  done
  for l in "${LAYERS[@]}"; do
    for f in kdeglobals kwinrc plasmafusionrc; do
      [ -r "${LAYER_DIR[$l]}/$f" ] && [ -f "${LAYER_DIR[$l]}/$f" ] && args+=("L=$l|$f" "${LAYER_DIR[$l]}/$f")
    done
  done
  [ ${#DESK_GROUPS[@]} -eq 0 ] || args+=("L=u|$APPLETSRC" "$CONFIG/$APPLETSRC")
  [ ${#args[@]} -gt 0 ] || return 0
  while IFS=$'\t' read -r lbl spec st; do
    INI["$lbl|$spec"]=$st
  done < <(LC_ALL=C awk -v want="$want" "$INI_AWK" "${args[@]}" 2>/dev/null)
}

# ustate FILE GROUP KEY: REPLY = the user file's state ("-": absent or deleted).
ustate() { REPLY=${INI["u|$1|$2|$3"]:--}; }
# lower FILE GROUP KEY: REPLY = the value the layers below the user file give (return 1: none).
lower() {
  local l s
  for l in "${LAYERS[@]:1}"; do
    s=${INI["$l|$1|$2|$3"]-}
    case $s in '') ;; -) REPLY=; return 1 ;; *) REPLY=${s#*=}; return 0 ;; esac
  done
  REPLY=
  return 1
}
# eff FILE GROUP KEY: REPLY = the effective value (return 1: unset).
eff() {
  local s=${INI["u|$1|$2|$3"]-}
  case $s in '') ;; -) REPLY=; return 1 ;; *) REPLY=${s#*=}; return 0 ;; esac
  lower "$@"
}

# Writes edit only the user's file, in place: one awk run per file, written next to it and renamed
# over it (permissions kept). Set: every line of the key in the group goes, "key=value" follows the
# group's last entry (or a new group at the end). Remove: every line of the key in the group goes,
# key[$d] included, so ~/.config/kdedefaults shows through again (kwriteconfig6 with a relative
# --file would write key[$d] and mask it; it also costs 15-20 ms per key at login). Values are
# written as stored, so a recorded value comes back byte for byte (KConfig escapes included).
WRITES=()
queue_write() { WRITES+=("$1" "$2" "$3" "$4"); } # FILE GROUP KEY STATE ("=value" or "-")
INI_EDIT_AWK='
function header(t) { while (t ~ /\[\$[a-zA-Z]*\]$/) sub(/\[\$[a-zA-Z]*\]$/, "", t); return substr(t, 2, length(t) - 2) }
function keyof(t,   k, eq, opt) {
  eq = index(t, "=")
  k = eq ? substr(t, 1, eq - 1) : t
  sub(/[ \t]+$/, "", k)
  if (k ~ /\]$/) { opt = k; sub(/^[^[]*\[/, "", opt); if (substr(opt, 1, 1) != "$") return ""; sub(/\[.*$/, "", k); return k }
  return eq ? k : ""
}
function trim(t) { sub(/\r$/, "", t); sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); return t }
BEGIN {
  # From the environment, not -v: awk would turn the backslashes of KConfig escapes (\s, \\) into
  # escape sequences.
  n = split(ENVIRON["PF_GATE_OPS"], O, "\n")
  for (i = 1; i <= n; i++) {
    if (O[i] == "") continue
    split(O[i], p, "\t")
    touch[p[1] "\t" p[2]] = 1
    if (p[3] != "-") { setv[p[1]] = setv[p[1]] p[2] p[3] "\n"; order[++m] = p[1] }
  }
}
NR == FNR {
  t = trim($0)
  if (substr(t, 1, 1) == "[") { cur = header(t); last[cur] = FNR }
  else if (t != "" && substr(t, 1, 1) != "#") last[cur] = FNR
  next
}
{
  t = trim($0)
  skip = 0
  if (substr(t, 1, 1) == "[") cur = header(t)
  else if (t != "" && substr(t, 1, 1) != "#" && ((cur "\t" keyof(t)) in touch)) skip = 1
  if (!skip) print
  # After the last entry of the group, also when that entry is the replaced key itself.
  if ((cur in setv) && last[cur] == FNR && !(cur in done)) { printf "%s", setv[cur]; done[cur] = 1 }
}
END { for (i = 1; i <= m; i++) { g = order[i]; if (!(g in done)) { printf "\n[%s]\n%s", g, setv[g]; done[g] = 1 } } }'
ini_edit() { # FILE OPS... (each "group<TAB>key<TAB>state")
  local f=$CONFIG/$1 src ops o sets=0
  shift
  printf -v ops '%s\n' "$@"
  [ -L "$f" ] && f=$(readlink -f "$f")
  src=$f
  if [ ! -f "$src" ]; then
    # Nothing to remove from a missing file; only a value to set creates it.
    for o in "$@"; do [ "${o##*$'\t'}" = - ] || sets=1; done
    [ "$sets" = 1 ] || return 0
    src=/dev/null
  fi
  PF_GATE_OPS=$ops LC_ALL=C awk "$INI_EDIT_AWK" "$src" "$src" >"$f.pf-gate.tmp" 2>/dev/null || { rm -f "$f.pf-gate.tmp"; return 1; }
  [ "$src" = /dev/null ] || chmod --reference="$src" "$f.pf-gate.tmp" 2>/dev/null
  mv -f "$f.pf-gate.tmp" "$f"
}

# ---------- records ----------

# One line per change: part reason kind file group key before written before-effective (tab
# separated, "-" for none; states are "=value" or "-"). kind "key" is a config key, "dropin" the
# lock-screen drop-in, "link" a user service's wants link (file: its path below ~/.config, before:
# its target), "kept" marks a part the user turned on again.
RECS=()
RECS_CHANGED=0
valid_part() {
  case $1 in lockscreen | decoration | navigation | desktop | snap | attach | outline | switcher | tablet | inputmethod | powerfx | pengarage) return 0 ;; esac
  return 1
}
load_recs() {
  local line f bad=0
  [ -f "$GATE/off" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in '#'* | '') continue ;; esac
    IFS=$'\t' read -r -a f <<<"$line"
    if [ ${#f[@]} -eq 9 ] && valid_part "${f[0]}" && [[ ${f[2]} =~ ^(key|dropin|link|kept)$ ]] &&
      { [ "${f[2]}" != link ] || [ "${f[3]}" = "$WANTS_REL/${UNIT[${f[0]}]-}" ]; }; then
      RECS+=("$line")
    else
      bad=$((bad + 1))
    fi
  done <"$GATE/off"
  [ "$bad" = 0 ] || { say "ignored $bad unreadable line(s) in $GATE/off"; RECS_CHANGED=1; }
}
rec_add() { local IFS=$'\t'; RECS+=("$*"); RECS_CHANGED=1; }
rec_has() { # PART [KIND]
  local r f
  for r in "${RECS[@]}"; do
    [[ $r == "$1"$'\t'* ]] || continue
    [ -z "${2:-}" ] && return 0
    IFS=$'\t' read -r -a f <<<"$r"
    [ "${f[2]}" = "$2" ] && return 0
  done
  return 1
}
rec_has_key() { # PART FILE GROUP KEY
  local r f
  for r in "${RECS[@]}"; do
    [[ $r == "$1"$'\t'* ]] || continue
    IFS=$'\t' read -r -a f <<<"$r"
    [ "${f[2]}" = key ] && [ "${f[3]}" = "$2" ] && [ "${f[4]}" = "$3" ] && [ "${f[5]}" = "$4" ] && return 0
  done
  return 1
}
rec_drop() { # PART
  local keep=() r
  for r in "${RECS[@]}"; do [[ $r == "$1"$'\t'* ]] || keep+=("$r"); done
  RECS=("${keep[@]}")
  RECS_CHANGED=1
}
save_recs() {
  [ "$RECS_CHANGED" = 1 ] && [ "$DRY" = 0 ] || return 0
  [ -d "$GATE" ] || mkdir -p "$GATE" 2>/dev/null
  if [ ${#RECS[@]} -eq 0 ]; then
    rm -f "$GATE/off"
  else
    { printf '# Plasma Fusion login check: what it switched off (part reason kind file group key before written before-effective)\n'
      printf '%s\n' "${RECS[@]}"; } >"$GATE/off.tmp" && mv -f "$GATE/off.tmp" "$GATE/off"
  fi
  RECS_CHANGED=0
}

# set_rec PART REASON FILE GROUP KEY STATE [BEFORE-EFFECTIVE]: record the user value once, then
# queue writing STATE.
set_rec() {
  ustate "$3" "$4" "$5"
  rec_has_key "$1" "$3" "$4" "$5" || rec_add "$1" "$2" key "$3" "$4" "$5" "$REPLY" "$6" "${7:--}"
  [ "$REPLY" = "$6" ] || queue_write "$3" "$4" "$5" "$6"
}

# ---------- the parts ----------

lockshell_dir() {
  local d dirs
  if [ -f "$DATA/plasma/shells/$LOCKSHELL/metadata.json" ]; then REPLY=$DATA/plasma/shells/$LOCKSHELL; return 0; fi
  IFS=: read -r -a dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  for d in "${dirs[@]}"; do
    [ -n "$d" ] && [ -f "$d/plasma/shells/$LOCKSHELL/metadata.json" ] && { REPLY=$d/plasma/shells/$LOCKSHELL; return 0; }
  done
  REPLY=
  return 1
}
# sha256 over the package's files and their relative names (the same on every machine).
lockshell_hash() {
  REPLY=$(cd "$1" 2>/dev/null && find . \( -type f -o -type l \) -print0 2>/dev/null |
    LC_ALL=C sort -z | xargs -0r sha256sum 2>/dev/null | sha256sum)
  REPLY=${REPLY%% *}
}
aurorae_installed() { # THEME
  local d dirs
  [ -d "$DATA/aurorae/themes/$1" ] && return 0
  IFS=: read -r -a dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  for d in "${dirs[@]}"; do [ -n "$d" ] && [ -d "$d/aurorae/themes/$1" ] && return 0; done
  return 1
}
# PF_GATE_SYSTEM_PLUGINS (tests only) replaces the system plugin directories.
cpp_deco_installed() {
  local d dirs sys
  IFS=: read -r -a dirs <<<"${QT_PLUGIN_PATH:-}"
  IFS=: read -r -a sys <<<"${PF_GATE_SYSTEM_PLUGINS-/usr/lib64/qt6/plugins:/usr/lib/qt6/plugins:/usr/lib/x86_64-linux-gnu/qt6/plugins:/run/current-system/sw/lib/qt-6/plugins}"
  for d in "${dirs[@]}" "${sys[@]}"; do
    [ -n "$d" ] && [ -f "$d/org.kde.kdecoration3/$CPP_DECO.so" ] && return 0
  done
  return 1
}

desktop_installed() {
  local d dirs
  [ -f "$DATA/plasma/plasmoids/$DESKTOP/metadata.json" ] && return 0
  IFS=: read -r -a dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  for d in "${dirs[@]}"; do [ -n "$d" ] && [ -f "$d/plasma/plasmoids/$DESKTOP/metadata.json" ] && return 0; done
  return 1
}

part_on() {
  local g
  case $1 in
    lockscreen) [ -f "$DROPIN" ] ;;
    decoration) eff kwinrc org.kde.kdecoration2 library && [ "$REPLY" = "$CPP_DECO" ] ;;
    snap) eff kwinrc Plugins plasmafusion-snapEnabled && [ "$REPLY" = true ] ;;
    attach) eff kwinrc Plugins plasmafusion-attachEnabled && [ "$REPLY" = true ] ;;
    outline) eff kwinrc Outline QmlPath && [[ $REPLY == *plasmafusion* ]] ;;
    switcher)
      { eff kwinrc TabBox LayoutName && [ "$REPLY" = "$SWITCHER" ]; } ||
        { eff kwinrc TabBoxAlternative LayoutName && [ "$REPLY" = "$SWITCHER" ]; } ;;
    tablet) eff kwinrc Plugins plasmafusion-tabletEnabled && [ "$REPLY" = true ] ;;
    navigation) eff kwinrc Plugins plasmafusion_navigationEnabled && [ "$REPLY" = true ] ;;
    desktop)
      for g in "${DESK_GROUPS[@]}"; do ustate "$APPLETSRC" "$g" plugin && [ "$REPLY" = "=$DESKTOP" ] && return 0; done
      return 1 ;;
    # Only the values the Fusion keyboard policy writes; the user file only (the system's value is
    # Fedora's default).
    inputmethod) ustate kwinrc Wayland InputMethod && case $REPLY in = | =/*/applications/"$OSK") return 0 ;; esac; return 1 ;;
    powerfx | pengarage) [ -L "$CONFIG/$WANTS_REL/${UNIT[$1]}" ] || [ -e "$CONFIG/$WANTS_REL/${UNIT[$1]}" ] ;;
    *) return 1 ;;
  esac
}

variant() { # REPLY = Dark or Light
  local r g b
  eff kdeglobals KDE LookAndFeelPackage
  case $REPLY in "$LIGHT") REPLY=Light; return ;; "$DARK") REPLY=Dark; return ;; esac
  eff kdeglobals General ColorScheme
  case $REPLY in *Light*) REPLY=Light; return ;; *Dark*) REPLY=Dark; return ;; esac
  if eff kdeglobals Colors:Window BackgroundNormal && IFS=, read -r r g b <<<"$REPLY" &&
    [[ $r =~ ^[[:digit:]]+$ && $g =~ ^[[:digit:]]+$ && $b =~ ^[[:digit:]]+$ ]] && [ $(((r * 299 + g * 587 + b * 114) / 1000)) -gt 127 ]; then
    REPLY=Light
  else
    REPLY=Dark
  fi
}

FILEOPS=()
DID=()
off_lockscreen() { # REASON
  rec_has lockscreen dropin || rec_add lockscreen "$1" dropin - - - =present - -
  FILEOPS+=(dropin-off)
  DID+=("lock screen: Plasma's own (drop-in moved to $SAVED_DROPIN)")
}
off_decoration() {
  local v left='' lib theme before_lib before_theme deflib='' deftheme=''
  variant; v=$REPLY
  eff plasmafusionrc Decoration ButtonStyle && [ "$REPLY" = LeftCircles ] && left=-Left
  lower kwinrc org.kde.kdecoration2 library && deflib=$REPLY
  lower kwinrc org.kde.kdecoration2 theme && deftheme=$REPLY
  if [ -z "$left" ] && [ "$deflib" = "$AURORAE" ] && [[ $deftheme =~ ^__aurorae__svg__PlasmaFusion(Dark|Light)$ ]] &&
    aurorae_installed "${deftheme#__aurorae__svg__}"; then
    # The Global Theme (kdedefaults) already names the Aurorae theme: drop the user's keys, so the
    # title bars follow it when startplasma or Follow sunset switches between light and dark.
    lib=- theme=$deftheme
  elif aurorae_installed "PlasmaFusion$v$left"; then
    lib=$AURORAE theme=__aurorae__svg__PlasmaFusion$v$left
  else
    lib=$BREEZE_DECO theme=Breeze left=
  fi
  eff kwinrc org.kde.kdecoration2 library && before_lib="=$REPLY" || before_lib=-
  eff kwinrc org.kde.kdecoration2 theme && before_theme="=$REPLY" || before_theme=-
  if [ "$lib" = - ]; then
    set_rec decoration "$1" kwinrc org.kde.kdecoration2 library - "$before_lib"
    set_rec decoration "$1" kwinrc org.kde.kdecoration2 theme - "$before_theme"
  else
    set_rec decoration "$1" kwinrc org.kde.kdecoration2 library "=$lib" "$before_lib"
    set_rec decoration "$1" kwinrc org.kde.kdecoration2 theme "=$theme" "$before_theme"
  fi
  if [ -n "$left" ]; then
    # The -Left Aurorae themes draw the circles from these lists (as the settings module does).
    set_rec decoration "$1" kwinrc org.kde.kdecoration2 ButtonsOnLeft =XIA
    set_rec decoration "$1" kwinrc org.kde.kdecoration2 ButtonsOnRight =_
  fi
  DID+=("decoration: $CPP_DECO -> $theme")
}
off_tablet() {
  # Written as false, not removed: the script's EnabledByDefault is not this check's to know.
  set_rec tablet "$1" kwinrc Plugins plasmafusion-tabletEnabled =false
  DID+=("KWin script plasmafusion-tablet off")
}
off_navigation() {
  set_rec navigation "$1" kwinrc Plugins plasmafusion_navigationEnabled =false
  DID+=("navigation effect plasmafusion_navigation off")
}
off_desktop() {
  local g
  for g in "${DESK_GROUPS[@]}"; do
    ustate "$APPLETSRC" "$g" plugin && [ "$REPLY" = "=$DESKTOP" ] && set_rec desktop "$1" "$APPLETSRC" "$g" plugin "=$FOLDER"
  done
  DID+=("desktop: Folder View instead of $DESKTOP")
}
off_inputmethod() {
  set_rec inputmethod "$1" kwinrc Wayland InputMethod -
  DID+=("on-screen keyboard: the system's default")
}
off_link() { # PART REASON
  local rel=$WANTS_REL/${UNIT[$1]} target
  target=$(readlink "$CONFIG/$rel" 2>/dev/null) || target=-
  [ -n "$target" ] || target=-
  rec_has "$1" link || rec_add "$1" "$2" link "$rel" - - "$target" - -
  FILEOPS+=("link-off:$1")
  DID+=("user service ${UNIT[$1]} not started (link moved to $GATE/saved/)")
}
off_powerfx() { off_link powerfx "$1"; }
off_pengarage() { off_link pengarage "$1"; }
off_snap() { set_rec snap "$1" kwinrc Plugins plasmafusion-snapEnabled -; DID+=("KWin script plasmafusion-snap off"); }
off_attach() { set_rec attach "$1" kwinrc Plugins plasmafusion-attachEnabled -; DID+=("KWin script plasmafusion-attach off"); }
off_outline() { set_rec outline "$1" kwinrc Outline QmlPath -; DID+=("snap-zone outline: KWin's own"); }
off_switcher() {
  local g
  for g in TabBox TabBoxAlternative; do
    eff kwinrc "$g" LayoutName && [ "$REPLY" = "$SWITCHER" ] || continue
    # A Global Theme without a switcher of its own leaves Fusion's in kdedefaults: override it.
    if lower kwinrc "$g" LayoutName && [ "$REPLY" = "$SWITCHER" ]; then
      set_rec switcher "$1" kwinrc "$g" LayoutName "=$KWIN_SWITCHER"
    else
      set_rec switcher "$1" kwinrc "$g" LayoutName -
    fi
    # fusion-config.sh's values for the Fusion switcher, back to KWin's defaults.
    ustate kwinrc "$g" DesktopMode
    [ "$REPLY" = =0 ] && set_rec switcher "$1" kwinrc "$g" DesktopMode -
    ustate kwinrc "$g" HighlightWindows
    [ "$REPLY" = =false ] && set_rec switcher "$1" kwinrc "$g" HighlightWindows -
  done
  DID+=("window switcher: KWin's own")
}

# Put recorded keys back while they still hold what was written here. RELAXED (decoration): the
# library and theme come back whenever the title bars are still a Plasma Fusion Aurorae theme,
# because every Global Theme apply (also the automatic light/dark switch) rewrites them.
restore_keys() { # PART [relaxed]
  local r f cur lib theme ok=1
  if [ "${2:-}" = relaxed ]; then
    eff kwinrc org.kde.kdecoration2 library; lib=$REPLY
    eff kwinrc org.kde.kdecoration2 theme; theme=$REPLY
    ok=0
    case $lib in "$AURORAE" | org.kde.kwin.aurorae) [[ $theme == __aurorae__svg__PlasmaFusion* ]] && ok=1 ;; esac
    if [ "$ok" = 0 ]; then
      # Or the user file still holds the fallback written here (Breeze when the Aurorae themes were
      # missing). Not for a removed key: a Global Theme apply removes it too (Breeze chosen).
      for r in "${RECS[@]}"; do
        IFS=$'\t' read -r -a f <<<"$r"
        [ "${f[0]}" = "$1" ] && [ "${f[5]}" = library ] && [ "${f[7]}" != - ] && ustate kwinrc org.kde.kdecoration2 library &&
          [ "$REPLY" = "${f[7]}" ] && ok=1
      done
    fi
    if [ "$ok" = 0 ]; then
      say "  decoration: left as $lib ${theme:+($theme)}, changed since it was switched"
    elif ! cpp_deco_installed; then
      say "  decoration: $CPP_DECO is not installed; the title bars stay $theme"
      ok=0
    fi
  fi
  for r in "${RECS[@]}"; do
    IFS=$'\t' read -r -a f <<<"$r"
    [ "${f[0]}" = "$1" ] && [ "${f[2]}" = key ] || continue
    ustate "${f[3]}" "${f[4]}" "${f[5]}"
    cur=$REPLY
    if [ "${2:-}" = relaxed ] && [[ ${f[5]} =~ ^(library|theme)$ ]]; then
      [ "$ok" = 1 ] || continue
      # Back to the effective value from before: leave it to kdedefaults when that gives it.
      if [[ ${f[8]} == =* ]] && ! { lower "${f[3]}" "${f[4]}" "${f[5]}" && [ "=$REPLY" = "${f[8]}" ]; }; then
        [ "$cur" = "${f[8]}" ] || queue_write "${f[3]}" "${f[4]}" "${f[5]}" "${f[8]}"
      else
        [ "$cur" = - ] || queue_write "${f[3]}" "${f[4]}" "${f[5]}" -
      fi
    elif [ "$cur" = "${f[7]}" ]; then
      [ "$cur" = "${f[6]}" ] || queue_write "${f[3]}" "${f[4]}" "${f[5]}" "${f[6]}"
    else
      say "  $1: ${f[3]} [${f[4]}] ${f[5]} left as it is (changed since it was switched)"
    fi
  done
  rec_drop "$1"
}
restore_lockscreen() {
  if rec_has lockscreen dropin; then
    if [ -f "$DROPIN" ]; then
      say "  lock screen: drop-in already back"
    elif [ ! -f "$SAVED_DROPIN" ]; then
      say "  lock screen: no saved drop-in; stays Plasma's own (lockscreen-enable.sh turns it on)"
    elif ! lockshell_dir; then
      say "  lock screen: $LOCKSHELL is not installed; stays Plasma's own"
    else
      FILEOPS+=(dropin-on)
    fi
  fi
  FILEOPS+=(dropin-forget)
  rec_drop lockscreen
}
# A user service's link comes back while it is still missing and the unit is still installed.
restore_link() { # PART
  local rel=$WANTS_REL/${UNIT[$1]}
  if rec_has "$1" link; then
    if [ -L "$CONFIG/$rel" ] || [ -e "$CONFIG/$rel" ]; then
      say "  $1: ${UNIT[$1]} already enabled again"
    elif [ ! -L "$GATE/saved/${UNIT[$1]}" ] && [ ! -e "$GATE/saved/${UNIT[$1]}" ]; then
      say "  $1: no saved link; ${UNIT[$1]} stays off (fusion-config.sh enables it)"
    elif [ ! -f "$CONFIG/systemd/user/${UNIT[$1]}" ]; then
      say "  $1: ${UNIT[$1]} is not installed any more; stays off"
    else
      FILEOPS+=("link-on:$1")
    fi
  fi
  FILEOPS+=("link-forget:$1")
  rec_drop "$1"
}
restore_part() {
  local n=${#WRITES[@]} nops=${#FILEOPS[@]}
  case $1 in
    lockscreen) restore_lockscreen ;;
    decoration) restore_keys decoration relaxed ;;
    powerfx | pengarage) restore_link "$1" ;;
    *) restore_keys "$1" ;;
  esac
  if [ ${#WRITES[@]} -gt "$n" ] || { [[ $1 =~ ^(lockscreen|powerfx|pengarage)$ ]] && [ ${#FILEOPS[@]} -gt $((nops + 1)) ]; }; then
    DID+=("$1 back on")
  else
    DID+=("$1 record cleared")
  fi
}

do_fileops() {
  local op p lnk saved
  for op in "${FILEOPS[@]}"; do
    case $op in
      dropin-off)
        [ -f "$DROPIN" ] || continue
        if [ "$DRY" = 1 ]; then say "  would move $DROPIN to $SAVED_DROPIN"; continue; fi
        { [ -d "${SAVED_DROPIN%/*}" ] || mkdir -p "${SAVED_DROPIN%/*}"; } && cp -p "$DROPIN" "$SAVED_DROPIN.tmp" && mv -f "$SAVED_DROPIN.tmp" "$SAVED_DROPIN" &&
          rm -f "$DROPIN" && { rmdir "$DROPIN_DIR" 2>/dev/null; say "  moved $DROPIN aside"; } ||
          say "  error: could not move $DROPIN aside"
        ;;
      dropin-on)
        if [ "$DRY" = 1 ]; then say "  would put $DROPIN back"; continue; fi
        if mkdir -p "$DROPIN_DIR" && cp -p "$SAVED_DROPIN" "$DROPIN.tmp" && mv -f "$DROPIN.tmp" "$DROPIN"; then
          say "  put $DROPIN back"
          DROPIN_RESTORED=1
        else
          say "  error: could not put $DROPIN back (kept $SAVED_DROPIN)"
          KEEP_SAVED=1
        fi
        ;;
      dropin-forget)
        [ "$DRY" = 1 ] || [ "${KEEP_SAVED:-0}" = 1 ] || [ ! -e "$SAVED_DROPIN" ] || rm -f "$SAVED_DROPIN"
        ;;
      link-off:* | link-on:* | link-forget:*)
        p=${op#*:} lnk=$CONFIG/$WANTS_REL/${UNIT[${op#*:}]} saved=$GATE/saved/${UNIT[${op#*:}]}
        case $op in
          link-off:*)
            [ -L "$lnk" ] || [ -e "$lnk" ] || continue
            if [ "$DRY" = 1 ]; then say "  would move $lnk to $saved"; continue; fi
            { [ -d "$GATE/saved" ] || mkdir -p "$GATE/saved"; } && mv -f "$lnk" "$saved" &&
              { rmdir "${lnk%/*}" 2>/dev/null; say "  moved $lnk aside"; } || say "  error: could not move $lnk aside"
            ;;
          link-on:*)
            if [ "$DRY" = 1 ]; then say "  would put $lnk back"; continue; fi
            if mkdir -p "${lnk%/*}" && mv -f "$saved" "$lnk"; then
              say "  put $lnk back"
              DROPIN_RESTORED=1
            else
              say "  error: could not put $lnk back (kept $saved)"
              KEEP_LINK[$p]=1
            fi
            ;;
          link-forget:*)
            [ "$DRY" = 1 ] || [ "${KEEP_LINK[$p]:-0}" = 1 ] || { [ ! -L "$saved" ] && [ ! -e "$saved" ]; } || rm -f "$saved"
            ;;
        esac
        ;;
    esac
  done
}
declare -A KEEP_LINK=()
do_writes() {
  local i f files=() ops what
  for ((i = 0; i + 3 < ${#WRITES[@]}; i += 4)); do
    case " ${files[*]} " in *" ${WRITES[i]} "*) ;; *) files+=("${WRITES[i]}") ;; esac
  done
  for f in "${files[@]}"; do
    ops=()
    for ((i = 0; i + 3 < ${#WRITES[@]}; i += 4)); do
      [ "${WRITES[i]}" = "$f" ] || continue
      ops+=("${WRITES[i + 1]}"$'\t'"${WRITES[i + 2]}"$'\t'"${WRITES[i + 3]}")
      if [ "${WRITES[i + 3]}" = - ]; then what="remove $f [${WRITES[i + 1]}] ${WRITES[i + 2]}"; else what="$f [${WRITES[i + 1]}] ${WRITES[i + 2]}${WRITES[i + 3]}"; fi
      [ "$DRY" = 1 ] && what="would write: $what"
      say "  $what"
      INI["u|$f|${WRITES[i + 1]}|${WRITES[i + 2]}"]=${WRITES[i + 3]}
    done
    [ "$DRY" = 1 ] || ini_edit "$f" "${ops[@]}" || say "  error: could not write $CONFIG/$f"
  done
}

# ---------- versions ----------

declare -A TESTED=() CUR=()
TESTED_STATE=missing TESTED_LOCK='' TESTED_TOOL='' TESTED_DB=rpm VERS_STATE='' VERS_FAKED=0 VERS_ASKED='' STAMP=''
load_tested() {
  local line fmt='' end='' p
  [ -f "$GATE/tested" ] || { TESTED_STATE=missing; return; }
  TESTED_STATE=corrupt
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      format=*) fmt=${line#format=} ;;
      db=*)
        case ${line#db=} in rpm | pacman | dpkg | nix) TESTED_DB=${line#db=} ;; *) return ;; esac ;;
      "pkg "*=*)
        p=${line#pkg }
        [[ ${p%%=*} =~ $NAME_RE ]] || return
        TESTED[${p%%=*}]=${p#*=} ;;
      lockshell-hash=*) TESTED_LOCK=${line#lockshell-hash=} ;;
      tool=/*) TESTED_TOOL=${line#tool=} ;;
      end=1) end=1 ;;
    esac
  done <"$GATE/tested"
  [ "$fmt" = "$FORMAT" ] && [ "$end" = 1 ] && [ ${#TESTED[@]} -gt 0 ] && [ -n "$TESTED_LOCK" ] && TESTED_STATE=ok
  # An earlier check on a system without rpm recorded every version as "no-rpm".
  for p in "${TESTED[@]}"; do [ "$p" != no-rpm ] || TESTED_STATE=nodb; done
}

use_db() { DB=$1; read -r -a PACKAGES <<<"${DB_PACKAGES[$1]}"; }
# db_tool DB: REPLY = the program that reads that database (return 1: not installed).
db_tool() {
  case $1 in
    rpm) REPLY=${PF_GATE_RPM:-rpm} ;;
    pacman) REPLY=pacman ;;
    dpkg) REPLY=dpkg-query ;;
    nix)
      [ -e "$NIX_SW" ] || return 1
      REPLY=nix-store
      command -v "$REPLY" >/dev/null 2>&1 || REPLY=$NIX_SW/bin/nix-store ;;
  esac
  command -v "$REPLY" >/dev/null 2>&1
}
# db_stamp DB: REPLY = what every transaction of that database changes (empty: not cached).
db_stamp() {
  local f
  REPLY=
  case $1 in
    rpm)
      for f in "$SYSROOT"/usr/lib/sysimage/rpm/rpmdb.sqlite "$SYSROOT"/var/lib/rpm/rpmdb.sqlite "$SYSROOT"/var/lib/rpm/Packages; do
        if [ -e "$f" ]; then
          REPLY=$(stat -L -c '%i:%s:%Y' "$f" "$f-wal" 2>/dev/null)
          REPLY=${REPLY//$'\n'/,}
          return 0
        fi
      done ;;
    # One directory per installed package, replaced when it is upgraded or reinstalled.
    pacman) f=$SYSROOT/var/lib/pacman/local; [ -d "$f" ] && REPLY=$(stat -L -c '%i:%s:%Y' "$f" 2>/dev/null) ;;
    # Written anew and renamed over by every dpkg run.
    dpkg) f=$SYSROOT/var/lib/dpkg/status; [ -f "$f" ] && REPLY=$(stat -L -c '%i:%s:%Y' "$f" 2>/dev/null) ;;
    # The system profile's package set: a new store path whenever a switch changes a package.
    nix) REPLY=$(readlink "$NIX_SW" 2>/dev/null) ;;
  esac
  return 0
}
# REPLY = the cache's key besides the stamp: the package names and how they were asked.
cache_list() {
  if [ "$DB" = rpm ]; then REPLY="${PACKAGES[*]} $QUERY_FORMAT"; else REPLY="${PACKAGES[*]} $DB"; fi
}
read_cache() {
  local line stamp='' list='' end='' db=rpm p
  [ -f "$GATE/cache" ] || return 1
  declare -A got=()
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      db=*) db=${line#db=} ;;
      stamp=*) stamp=${line#stamp=} ;;
      list=*) list=${line#list=} ;;
      "pkg "*=*) p=${line#pkg }; [[ ${p%%=*} =~ $NAME_RE ]] || return 1; got[${p%%=*}]=${p#*=} ;;
      end=1) end=1 ;;
    esac
  done <"$GATE/cache"
  case $db in rpm | pacman | dpkg | nix) ;; *) return 1 ;; esac
  use_db "$db"
  db_stamp "$db"
  [ -n "$REPLY" ] && [ "$stamp" = "$REPLY" ] && [ "$end" = 1 ] || return 1
  cache_list
  [ "$list" = "$REPLY" ] || return 1
  for p in "${PACKAGES[@]}"; do [ -n "${got[$p]-}" ] || return 1; CUR[$p]=${got[$p]}; done
  return 0
}
# CUR from the first package database that knows one of its packages: VERS_STATE ok, with DB,
# PACKAGES and STAMP that database's. A database that does not answer within 3 s ends the search.
# VERS_ASKED names the databases asked ("rpm", "rpm and pacman"; empty: none is installed).
query_versions() {
  local db prog out rc line n v p vs sorted asked=()
  declare -A got=()
  VERS_STATE=unknown VERS_ASKED='' STAMP=''
  for db in "${DBS[@]}"; do
    db_tool "$db" || continue
    prog=$REPLY
    use_db "$db"
    asked+=("${DB_NAME[$db]}")
    printf -v VERS_ASKED '%s, ' "${asked[@]}"
    VERS_ASKED=${VERS_ASKED%, }
    [ ${#asked[@]} -lt 2 ] || VERS_ASKED="${VERS_ASKED%, *} and ${asked[-1]}"
    # Taken before the query: a transaction during it makes the cache stale, never wrong.
    db_stamp "$db"
    STAMP=$REPLY
    case $db in
      rpm) out=$(LC_ALL=C timeout 3 "$prog" -q --qf "$QUERY_FORMAT" "${PACKAGES[@]}" 2>/dev/null) ;;
      pacman) out=$(LC_ALL=C timeout 3 "$prog" -Q "${PACKAGES[@]}" 2>/dev/null) ;;
      dpkg) out=$(LC_ALL=C timeout 3 "$prog" -W -f "$DPKG_FORMAT" 2>/dev/null) ;;
      nix) out=$(LC_ALL=C timeout 3 "$prog" --query --requisites "$NIX_SW" 2>/dev/null) ;;
    esac
    rc=$?
    [ "$rc" -lt 124 ] || return 1
    got=()
    while IFS= read -r line; do
      case $db in
        rpm) [[ $line == *=* ]] || continue; n=${line%%=*} v=${line#*=} ;;
        # name epoch:version-pkgrel
        pacman) [[ $line == *" "* ]] || continue; n=${line%% *} v=${line#* }; v=${v#*:}; v=${v%-*} ;;
        # status source=epoch:version-revision; a removed package can keep its configuration files
        dpkg)
          case $line in "not-installed "* | "config-files "* | "half-installed "*) continue ;; esac
          line=${line#* }
          [[ $line == *=* ]] || continue
          n=${line%%=*} v=${line#*=}; v=${v#*:}; [[ $v != *-* ]] || v=${v%-*} ;;
        # /nix/store/HASH-name-version[-output]: the name ends before the first "-digit"
        nix)
          line=${line##*/}; line=${line#*-}
          n=${line%%-[0-9]*}
          [ "$n" != "$line" ] || continue
          v=${line#"$n"-}; v=${v%%-*} ;;
      esac
      [[ $n =~ $NAME_RE ]] && [[ " ${PACKAGES[*]} " == *" $n "* ]] || continue
      if [ -z "${got[$n]-}" ]; then got[$n]=$v; elif [[ ,${got[$n]}, != *",$v,"* ]]; then got[$n]+=",$v"; fi
    done <<<"$out"
    # A database that knows none of them belongs to another package manager: ask the next.
    [ ${#got[@]} -gt 0 ] || continue
    for p in "${PACKAGES[@]}"; do
      v=${got[$p]:-absent}
      # Several versions (Debian binaries of one source at different versions): in version order,
      # so the order the database lists them in does not count.
      if [[ $v == *,* ]]; then
        IFS=, read -r -a vs <<<"$v"
        sorted=$(printf '%s\n' "${vs[@]}" | LC_ALL=C sort -V) && [ -n "$sorted" ] && v=${sorted//$'\n'/,}
      fi
      CUR[$p]=$v
    done
    VERS_STATE=ok
    return 0
  done
  return 1
}
current_versions() {
  local kv p
  [ -n "$VERS_STATE" ] && return 0
  if [ "$MODE" != deploy ] && read_cache; then
    VERS_STATE=ok
  elif query_versions && [ -n "$STAMP" ] && [ "$DRY" = 0 ]; then
    cache_list
    [ -d "$GATE" ] || mkdir -p "$GATE" 2>/dev/null
    { printf 'format=%s\n' "$FORMAT"
      [ "$DB" = rpm ] || printf 'db=%s\n' "$DB"
      printf 'stamp=%s\nlist=%s\n' "$STAMP" "$REPLY"
      for p in "${PACKAGES[@]}"; do printf 'pkg %s=%s\n' "$p" "${CUR[$p]}"; done
      printf 'end=1\n'; } >"$GATE/cache.tmp" 2>/dev/null && mv -f "$GATE/cache.tmp" "$GATE/cache"
  fi
  for kv in ${PF_GATE_FAKE_VERSIONS:-}; do
    [[ $kv == *=* && ${kv%%=*} =~ $NAME_RE ]] || continue
    CUR[${kv%%=*}]=${kv#*=}
    VERS_FAKED=1
  done
}
# REPLY = why the installed versions are unknown.
vers_why() {
  if [ -n "$VERS_ASKED" ]; then REPLY="$VERS_ASKED could not report the installed versions"
  else REPLY="no package database (rpm, pacman, dpkg or Nix) was found"; fi
}

# UPDATE_OK: installed versions equal the tested ones; LOCK_OK: also the lock-screen files.
# WHY: every reason (log); DIFFS: version changes, RECORD: why the record cannot be used, LOCKWHY:
# the lock-screen files (notification).
UPDATE_OK='' LOCK_OK='' WHY=() DIFFS=() RECORD='' LOCKWHY='' LOCK_HASH=''
check_versions() {
  local p
  [ -n "$UPDATE_OK" ] && return 0
  UPDATE_OK=1
  load_tested
  current_versions
  case $TESTED_STATE in
    missing) UPDATE_OK=0; RECORD="there is no record of it" ;;
    corrupt) UPDATE_OK=0; RECORD="its record is unreadable" ;;
    nodb) UPDATE_OK=0; RECORD="it was recorded without a package database" ;;
  esac
  if [ "$VERS_STATE" != ok ]; then
    UPDATE_OK=0
    vers_why
    RECORD="${RECORD:+$RECORD; }$REPLY"
  elif [ "$TESTED_STATE" = ok ] && [ "$TESTED_DB" != "$DB" ]; then
    UPDATE_OK=0
    RECORD="it was recorded with ${DB_NAME[$TESTED_DB]}, the versions now come from ${DB_NAME[$DB]}"
  elif [ "$TESTED_STATE" = ok ]; then
    for p in "${PACKAGES[@]}"; do
      [ "${TESTED[$p]-}" = "${CUR[$p]}" ] && continue
      UPDATE_OK=0
      DIFFS+=("$p ${TESTED[$p]:-?} → ${CUR[$p]}")
    done
  fi
  [ -z "$RECORD" ] || WHY+=("tested versions unknown: $RECORD")
  WHY+=("${DIFFS[@]}")
}
check_lock() {
  [ -n "$LOCK_OK" ] && return 0
  check_versions
  LOCK_OK=$UPDATE_OK
  if lockshell_dir; then
    lockshell_hash "$REPLY"
    LOCK_HASH=$REPLY
    if [ "$TESTED_STATE" = ok ] && [ "$TESTED_LOCK" != "$LOCK_HASH" ]; then
      LOCK_OK=0
      LOCKWHY="the lock-screen files changed since they were checked"
    fi
  else
    LOCK_HASH=absent
    LOCK_OK=0
    LOCKWHY="the lock-screen package $LOCKSHELL is not installed"
  fi
  [ -z "$LOCKWHY" ] || WHY+=("$LOCKWHY")
}

# ---------- notification ----------

queue_notification() {
  local body='' what=() d j how
  for d in "${UPD_OFF[@]}"; do
    case $d in
      lockscreen) what+=("Plasma's own lock screen") ;;
      decoration) what+=("the Aurorae title bars") ;;
      navigation) what+=("KWin's own edges instead of the tablet gestures") ;;
      desktop) what+=("Folder View instead of the tablet home screen") ;;
    esac
  done
  [ ${#what[@]} -gt 0 ] || return 0
  if [ ${#DIFFS[@]} -gt 0 ]; then
    printf -v j '%s, ' "${DIFFS[@]}"
    body="Plasma changed since Plasma Fusion was checked: ${j%, }. "
  fi
  [ -z "$RECORD" ] || body+="Plasma Fusion cannot tell which Plasma it was checked with ($RECORD). "
  [ -z "$LOCKWHY" ] || body+="${LOCKWHY^}. "
  # The fusion-config.sh that recorded the versions (its path is in the record), if it is still there.
  how=tools/device/fusion-config.sh
  [ -n "$TESTED_TOOL" ] && [ -f "$TESTED_TOOL" ] && how=$TESTED_TOOL
  [[ $how == "$HOME"/* ]] && how="~${how#"$HOME"}"
  j=${what[-1]}
  if [ ${#what[@]} -gt 1 ]; then
    printf -v d '%s, ' "${what[@]:0:${#what[@]}-1}"
    j="${d%, } and $j"
  fi
  body+="This session uses $j. To check and switch back, run $how."
  if [ "$DRY" = 1 ]; then say "  would queue a notification: $body"; return 0; fi
  [ -d "$GATE" ] || mkdir -p "$GATE" 2>/dev/null
  printf 'Safe mode after a Plasma change\n%s\n' "$body" >"$GATE/notify.tmp" && mv -f "$GATE/notify.tmp" "$GATE/notify" &&
    say "  notification queued"
}

# ---------- modes ----------

FUSION=0 LNF=
UPD_OFF=()
evaluate() { # the decision for every part; deploy only turns parts back on
  local p need_upd need_theme missing risky=0
  eff kdeglobals KDE LookAndFeelPackage
  LNF=$REPLY
  case $LNF in "$DARK" | "$LIGHT") FUSION=1 ;; esac
  # With automatic light/dark switching (AutomaticLookAndFeel), startplasma picks the light or dark
  # theme only after this check runs (setupPlasmaEnvironment), so LookAndFeelPackage can still name
  # the other one: a Plasma Fusion theme among the two counts, and the parts stay on.
  if [ "$FUSION" = 0 ] && eff kdeglobals KDE AutomaticLookAndFeel && [ "$REPLY" = true ]; then
    for p in DefaultLightLookAndFeel DefaultDarkLookAndFeel; do
      eff kdeglobals KDE "$p" && case $REPLY in "$DARK" | "$LIGHT") FUSION=1 ;; esac
    done
  fi
  if [ "$MODE" = deploy ]; then
    UPDATE_OK=1 LOCK_OK=1
  else
    for p in lockscreen decoration navigation desktop; do part_on "$p" || rec_has "$p" && risky=1; done
    [ "$risky" = 1 ] && check_versions
    { [ -f "$DROPIN" ] || rec_has lockscreen; } && check_lock
  fi
  for p in "${PARTS[@]}"; do
    need_upd=0 need_theme=0
    case $p in
      lockscreen) [ "${LOCK_OK:-1}" = 1 ] || need_upd=1 ;;
      decoration | navigation | desktop) [ "${UPDATE_OK:-1}" = 1 ] || need_upd=1 ;;
    esac
    [ "$p" != decoration ] && [ "$FUSION" = 0 ] && need_theme=1
    # The compiled decoration named (by the user or by the Global Theme's defaults) but not
    # installed: KWin would fall back to its built-in default, so the matching Aurorae theme is
    # chosen instead, without a notification. While the plugin is missing the record stays, and the
    # compiled title bars come back at the first login after it is installed again.
    # The same for the desktop: a containment naming a missing package would show an error.
    missing=0
    if [ "$p" = decoration ] && [ "$need_upd" = 0 ] && [ "$MODE" != deploy ] && ! cpp_deco_installed; then
      if part_on decoration; then
        missing=1
      elif rec_has decoration; then
        say "  decoration: $CPP_DECO is still not installed; the title bars stay Aurorae"
        continue
      fi
    elif [ "$p" = desktop ] && [ "$need_upd" = 0 ] && [ "$MODE" != deploy ] && ! desktop_installed; then
      if part_on desktop; then
        missing=1
      elif rec_has desktop; then
        say "  desktop: $DESKTOP is still not installed; the desktop stays Folder View"
        continue
      fi
    fi
    if [ "$missing" = 1 ]; then
      "off_$p" missing
    elif [ "$need_upd" = 1 ]; then
      if part_on "$p"; then
        "off_$p" update
        [ "$p" = decoration ] || [ "$FUSION" = 1 ] && UPD_OFF+=("$p")
      elif rec_has "$p"; then
        # Held off from an earlier login: still worth one notification per change.
        [ "$p" = decoration ] || [ "$FUSION" = 1 ] && UPD_OFF+=("$p")
      fi
    elif [ "$need_theme" = 1 ]; then
      [ "$MODE" = deploy ] && continue
      part_on "$p" || continue
      if rec_has "$p"; then
        rec_has "$p" kept || { rec_add "$p" theme kept - - - - - -; say "$p: turned on again under $LNF; left on"; }
      else
        "off_$p" theme
      fi
    elif rec_has "$p"; then
      restore_part "$p"
    fi
  done
}

finish_log() {
  local ts l ms size
  ms=$(((${EPOCHREALTIME/[.,]/} - T0) / 1000))
  [ "$MODE" = check ] && return 0
  printf -v ts '%(%Y-%m-%dT%H:%M:%S%z)T' -1
  [ -d "$ROOT" ] || mkdir -p "$ROOT" 2>/dev/null || return 0
  {
    printf '%s %s: %s (%s ms)\n' "$ts" "$MODE" "$SUMMARY" "$ms"
    for l in "${LINES[@]}"; do printf '%s   %s\n' "$ts" "$l"; done
  } >>"$LOG" 2>/dev/null
  # Keep it small; looking at the size on every twentieth run is enough.
  [ $((RANDOM % 20)) = 0 ] || return 0
  size=$(stat -c %s "$LOG" 2>/dev/null)
  if [ "${size:-0}" -gt 262144 ]; then
    tail -n 2000 "$LOG" >"$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
  fi
}

# ~/.local/state/plasma-fusion/gate/status for other parts (the settings module): which parts are
# held off and whether the installed Plasma is the tested one. Written only when it changes.
write_status() {
  local s p held=() vers=tested old=
  [ "$DRY" = 0 ] || return 0
  for p in "${PARTS[@]}"; do rec_has "$p" && held+=("$p"); done
  [ "${UPDATE_OK:-1}" = 1 ] && [ "${LOCK_OK:-1}" = 1 ] || vers=changed
  printf -v s 'format=%s\nlookandfeel=%s\nversions=%s\nheld=%s\n' "$FORMAT" "$LNF" "$vers" "${held[*]}"
  if [ -f "$GATE/status" ]; then
    IFS= read -r -d '' old <"$GATE/status"
  elif [ ${#held[@]} -eq 0 ] && [ "$vers" = tested ]; then
    return 0
  fi
  [ "$old" = "$s" ] && return 0
  [ -d "$GATE" ] || mkdir -p "$GATE" 2>/dev/null
  printf '%s' "$s" >"$GATE/status.tmp" && mv -f "$GATE/status.tmp" "$GATE/status"
}

run_check() {
  local fp old
  load_ini
  load_recs
  evaluate
  # Record first, then change: an interrupted run leaves a complete record.
  save_recs
  do_writes
  do_fileops
  save_recs
  if [ "${UPDATE_OK:-1}" = 1 ] && [ "${LOCK_OK:-1}" = 1 ]; then
    if [ "$DRY" = 0 ] && { [ -e "$GATE/notified" ] || [ -e "$GATE/notify" ]; }; then
      rm -f "$GATE/notified" "$GATE/notify"
    fi
  elif [ ${#UPD_OFF[@]} -gt 0 ]; then
    # One notification per change: the same versions and parts are not reported twice.
    fp="${WHY[*]}|$LOCK_HASH|${UPD_OFF[*]}"
    old=
    [ -f "$GATE/notified" ] && IFS= read -r old <"$GATE/notified"
    if [ "$old" != "$fp" ]; then
      queue_notification
      [ "$DRY" = 1 ] || { [ -d "$GATE" ] || mkdir -p "$GATE" 2>/dev/null; printf '%s\n' "$fp" >"$GATE/notified"; }
    fi
  fi
  write_status
  local vers=not-needed lock='' j
  [ -z "$UPDATE_OK" ] || { [ "$UPDATE_OK" = 1 ] && vers=tested || vers=changed; }
  [ -z "$LOCK_OK" ] || { [ "$LOCK_OK" = 1 ] && lock=" lock=tested" || lock=" lock=changed"; }
  [ "$VERS_FAKED" = 0 ] || vers+=" (fake versions)"
  if [ ${#DID[@]} -gt 0 ]; then
    printf -v j '%s; ' "${DID[@]}"
    [ "$DRY" = 1 ] && j="would change: $j"
    SUMMARY="theme=${LNF:-<default>} versions=$vers$lock; ${j%; }"
  else
    SUMMARY="theme=${LNF:-<default>} versions=$vers$lock; no change"
  fi
  [ ${#WHY[@]} -eq 0 ] || { printf -v j '%s; ' "${WHY[@]}"; say "why: ${j%; }"; }
  if [ "$MODE" = check ]; then
    printf '%s\n' "$SUMMARY"
    printf '%s\n' "${LINES[@]}"
  fi
}

run_deploy() {
  local p rc=0 lock=absent
  VERS_STATE=
  current_versions
  [ "$VERS_FAKED" = 0 ] || say "note: PF_GATE_FAKE_VERSIONS is set; recording the fake versions"
  if [ "$VERS_STATE" != ok ]; then
    if [ -n "$VERS_ASKED" ]; then
      echo "  login check: could not read the installed versions with $VERS_ASKED; the tested record stays as it was" >&2
    else
      vers_why
      echo "  login check: could not read the installed versions: $REPLY; the tested record stays as it was" >&2
    fi
    rc=1
  fi
  if lockshell_dir; then lockshell_hash "$REPLY"; lock=$REPLY; fi
  if [ "$rc" = 0 ]; then
    if [ "$DRY" = 1 ]; then
      echo "  login check: would record as tested: $(for p in "${PACKAGES[@]}"; do printf '%s %s, ' "$p" "${CUR[$p]}"; done)lock screen files ${lock:0:12}"
    else
      mkdir -p "$GATE" || return 1
      { printf 'format=%s\n' "$FORMAT"
        printf 'created=%(%Y-%m-%dT%H:%M:%S%z)T\n' -1
        [ "$DB" = rpm ] || printf 'db=%s\n' "$DB"
        for p in "${PACKAGES[@]}"; do printf 'pkg %s=%s\n' "$p" "${CUR[$p]}"; done
        printf 'lockshell-hash=%s\n' "$lock"
        # Named in the notification as the way back (fusion-config.sh passes its own path).
        [[ ${PF_GATE_TOOL:-} == /* && $PF_GATE_TOOL != *$'\n'* ]] && printf 'tool=%s\n' "$PF_GATE_TOOL"
        printf 'end=1\n'; } >"$GATE/tested.tmp" && mv -f "$GATE/tested.tmp" "$GATE/tested" || { echo "  login check: could not write $GATE/tested" >&2; return 1; }
      echo "  login check: recorded as tested: $(for p in "${PACKAGES[@]}"; do printf '%s %s, ' "$p" "${CUR[$p]}"; done)lock screen files ${lock:0:12}"
    fi
  fi
  load_ini
  load_recs
  evaluate
  do_writes
  do_fileops
  save_recs
  if [ "$DRY" = 0 ]; then
    rm -f "$GATE/notify" "$GATE/notified" 2>/dev/null
    [ "${DROPIN_RESTORED:-0}" = 0 ] || systemctl --user daemon-reload >/dev/null 2>&1 || true
  fi
  write_status
  if [ ${#DID[@]} -gt 0 ]; then printf -v SUMMARY '%s; ' "${DID[@]}"; SUMMARY=${SUMMARY%; }; else SUMMARY="nothing to turn back on"; fi
  echo "  login check: $SUMMARY"
  [ ${#LINES[@]} -eq 0 ] || printf '  %s\n' "${LINES[@]}"
  [ "$DRY" = 1 ] || finish_log
  return "$rc"
}

run_notify() {
  local summary body
  [ -f "$GATE/notify" ] || exit 0
  { IFS= read -r summary; IFS= read -r body; } <"$GATE/notify"
  # plasmashell owns the notification server; wait for it once the desktop is up.
  timeout 100 gdbus wait --session --timeout 90 org.freedesktop.Notifications >/dev/null 2>&1
  if notify-send --app-name="Plasma Fusion" --icon=dialog-warning --urgency=normal --expire-time=0 "$summary" "$body" >/dev/null 2>&1 ||
    timeout 20 gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.Notify "Plasma Fusion" 0 dialog-warning "$summary" "$body" '[]' '{}' 0 >/dev/null 2>&1; then
    rm -f "$GATE/notify"
    SUMMARY="shown: $summary"
  else
    SUMMARY="could not show the notification; it stays queued for the next login"
  fi
  finish_log
}

run_status() {
  echo "Plasma Fusion login check"
  echo "  log:      $LOG"
  if [ -f "$GATE/tested" ]; then echo "  tested:"; sed 's/^/    /' "$GATE/tested"; else echo "  tested:   no record (run tools/device/fusion-config.sh)"; fi
  if [ -f "$GATE/off" ]; then echo "  switched off:"; grep -v '^#' "$GATE/off" | sed 's/^/    /'; else echo "  switched off: nothing"; fi
  [ -f "$GATE/notify" ] && echo "  queued notification: $(head -n 1 "$GATE/notify")"
  if [ -f "$LOG" ]; then echo "  last runs:"; tail -n 8 "$LOG" | sed 's/^/    /'; fi
}

SUMMARY=
case $MODE in
  login | check) run_check; [ "$MODE" = login ] && finish_log; exit 0 ;;
  deploy) run_deploy; exit $? ;;
  notify) run_notify; exit 0 ;;
  status) run_status; exit 0 ;;
  *) echo "usage: plasma-fusion-gate.sh [login|check|deploy [--dry-run]|notify|status]" >&2; exit 2 ;;
esac
