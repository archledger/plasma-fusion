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
#    lockscreen-enable.sh) or the compiled decoration (kwinrc [org.kde.kdecoration2]
#    library=org.plasmafusion.decoration) is on, the installed versions of PACKAGES (rpm, cached by
#    the rpm database's size and time) and the lock-screen package files (sha256) are compared with
#    what fusion-config.sh recorded as tested. On a difference, or without a readable record, the
#    drop-in is moved aside (stock lock screen), the decoration becomes the Plasma Fusion Aurorae
#    theme of the current variant (-Left and its button lists for ButtonStyle=LeftCircles) and one
#    notification is queued for after the desktop is up. The next login with matching versions, or
#    the next fusion-config.sh run, turns them back on.
# 2. Switching back. While the Global Theme (kdeglobals [KDE] LookAndFeelPackage) is not Plasma
#    Fusion Dark or Light, the lock-screen drop-in, the plasmafusion-snap and plasmafusion-attach KWin
#    scripts, kwinrc [Outline] QmlPath and the Fusion window switcher are switched off, once: a part
#    the user turns on again is left on. A Plasma Fusion theme turns them back on at the next login.
#
# Every change is recorded first (~/.local/state/plasma-fusion/gate/off) and undone only while the
# value is still the one written here. With matching versions and a Fusion theme nothing changes.
# At login it runs no GUI program, makes no D-Bus or systemd call and always exits 0 (the stub also
# limits its run time). Log: ~/.local/state/plasma-fusion/gate.log.
#
# Test hooks (never set in a real session): PF_GATE_FAKE_VERSIONS="kwin=6.8.0 kscreenlocker=6.8.0"
# replaces installed versions in memory (never cached); PF_GATE_RPM names the rpm program.

PACKAGES=(plasma-workspace kwin kscreenlocker libplasma kdecoration qt6-qtbase qt6-qtdeclarative)
# Upstream version only: a distribution rebuild (-2.fc44) keeps the interfaces Fusion uses.
QUERY_FORMAT='%{NAME}=%{VERSION}\n'
FORMAT=1
DARK=org.plasmafusion.dark.desktop
LIGHT=org.plasmafusion.light.desktop
LOCKSHELL=org.plasmafusion.lockshell
CPP_DECO=org.plasmafusion.decoration
AURORAE=org.kde.kwin.aurorae.v2
BREEZE_DECO=org.kde.breeze
SWITCHER=org.plasmafusion.switcher
KWIN_SWITCHER=thumbnail_grid
PARTS=(lockscreen decoration snap attach outline switcher)
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

load_ini() {
  local d dirs n=0 seen=: f l args=() lbl spec st
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
  [ ${#args[@]} -gt 0 ] || return 0
  while IFS=$'\t' read -r lbl spec st; do
    INI["$lbl|$spec"]=$st
  done < <(LC_ALL=C awk -v want="$WANT" "$INI_AWK" "${args[@]}" 2>/dev/null)
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
# lock-screen drop-in, "kept" marks a part the user turned on again.
RECS=()
RECS_CHANGED=0
valid_part() { case $1 in lockscreen | decoration | snap | attach | outline | switcher) return 0 ;; esac; return 1; }
load_recs() {
  local line f bad=0
  [ -f "$GATE/off" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in '#'* | '') continue ;; esac
    IFS=$'\t' read -r -a f <<<"$line"
    if [ ${#f[@]} -eq 9 ] && valid_part "${f[0]}" && [[ ${f[2]} =~ ^(key|dropin|kept)$ ]]; then
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
cpp_deco_installed() {
  local d dirs
  IFS=: read -r -a dirs <<<"${QT_PLUGIN_PATH:-}"
  for d in "${dirs[@]}" /usr/lib64/qt6/plugins /usr/lib/qt6/plugins /usr/lib/x86_64-linux-gnu/qt6/plugins; do
    [ -n "$d" ] && [ -f "$d/org.kde.kdecoration3/$CPP_DECO.so" ] && return 0
  done
  return 1
}

part_on() {
  case $1 in
    lockscreen) [ -f "$DROPIN" ] ;;
    decoration) eff kwinrc org.kde.kdecoration2 library && [ "$REPLY" = "$CPP_DECO" ] ;;
    snap) eff kwinrc Plugins plasmafusion-snapEnabled && [ "$REPLY" = true ] ;;
    attach) eff kwinrc Plugins plasmafusion-attachEnabled && [ "$REPLY" = true ] ;;
    outline) eff kwinrc Outline QmlPath && [[ $REPLY == *plasmafusion* ]] ;;
    switcher)
      { eff kwinrc TabBox LayoutName && [ "$REPLY" = "$SWITCHER" ]; } ||
        { eff kwinrc TabBoxAlternative LayoutName && [ "$REPLY" = "$SWITCHER" ]; } ;;
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
restore_part() {
  local n=${#WRITES[@]} nops=${#FILEOPS[@]}
  case $1 in
    lockscreen) restore_lockscreen ;;
    decoration) restore_keys decoration relaxed ;;
    *) restore_keys "$1" ;;
  esac
  if [ ${#WRITES[@]} -gt "$n" ] || { [ "$1" = lockscreen ] && [ ${#FILEOPS[@]} -gt $((nops + 1)) ]; }; then
    DID+=("$1 back on")
  else
    DID+=("$1 record cleared")
  fi
}

do_fileops() {
  local op
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
    esac
  done
}
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
TESTED_STATE=missing TESTED_LOCK='' TESTED_TOOL='' VERS_STATE='' VERS_FAKED=0
load_tested() {
  local line fmt='' end='' p
  [ -f "$GATE/tested" ] || { TESTED_STATE=missing; return; }
  TESTED_STATE=corrupt
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      format=*) fmt=${line#format=} ;;
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
}

rpmdb_stamp() {
  local f
  REPLY=
  for f in /usr/lib/sysimage/rpm/rpmdb.sqlite /var/lib/rpm/rpmdb.sqlite /var/lib/rpm/Packages; do
    if [ -e "$f" ]; then
      REPLY=$(stat -L -c '%i:%s:%Y' "$f" "$f-wal" 2>/dev/null)
      REPLY=${REPLY//$'\n'/,}
      return 0
    fi
  done
}
read_cache() { # STAMP
  local line stamp='' list='' end='' p
  [ -n "$1" ] && [ -f "$GATE/cache" ] || return 1
  declare -A got=()
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      stamp=*) stamp=${line#stamp=} ;;
      list=*) list=${line#list=} ;;
      "pkg "*=*) p=${line#pkg }; [[ ${p%%=*} =~ $NAME_RE ]] || return 1; got[${p%%=*}]=${p#*=} ;;
      end=1) end=1 ;;
    esac
  done <"$GATE/cache"
  [ "$stamp" = "$1" ] && [ "$list" = "${PACKAGES[*]} $QUERY_FORMAT" ] && [ "$end" = 1 ] || return 1
  for p in "${PACKAGES[@]}"; do [ -n "${got[$p]-}" ] || return 1; CUR[$p]=${got[$p]}; done
  return 0
}
query_rpm() {
  local rpm=${PF_GATE_RPM:-rpm} out rc line n v p
  declare -A got=()
  if ! command -v "$rpm" >/dev/null 2>&1; then
    for p in "${PACKAGES[@]}"; do CUR[$p]=no-rpm; done
    VERS_STATE=ok
    return 0
  fi
  out=$(LC_ALL=C timeout 3 "$rpm" -q --qf "$QUERY_FORMAT" "${PACKAGES[@]}" 2>/dev/null)
  rc=$?
  [ "$rc" -lt 124 ] || { VERS_STATE=unknown; return 1; }
  while IFS= read -r line; do
    [[ $line == *=* ]] || continue
    n=${line%%=*} v=${line#*=}
    [[ $n =~ $NAME_RE ]] || continue
    if [ -n "${got[$n]-}" ] && [[ ,${got[$n]}, != *",$v,"* ]]; then got[$n]+=",$v"; else got[$n]=$v; fi
  done <<<"$out"
  [ ${#got[@]} -gt 0 ] || { VERS_STATE=unknown; return 1; }
  for p in "${PACKAGES[@]}"; do CUR[$p]=${got[$p]:-absent}; done
  VERS_STATE=ok
}
current_versions() {
  local stamp kv p
  [ -n "$VERS_STATE" ] && return 0
  rpmdb_stamp
  stamp=$REPLY
  if [ "$MODE" != deploy ] && read_cache "$stamp"; then
    VERS_STATE=ok
  elif query_rpm && [ -n "$stamp" ] && [ "$DRY" = 0 ]; then
    [ -d "$GATE" ] || mkdir -p "$GATE" 2>/dev/null
    { printf 'format=%s\nstamp=%s\nlist=%s\n' "$FORMAT" "$stamp" "${PACKAGES[*]} $QUERY_FORMAT"
      for p in "${PACKAGES[@]}"; do printf 'pkg %s=%s\n' "$p" "${CUR[$p]}"; done
      printf 'end=1\n'; } >"$GATE/cache.tmp" 2>/dev/null && mv -f "$GATE/cache.tmp" "$GATE/cache"
  fi
  for kv in ${PF_GATE_FAKE_VERSIONS:-}; do
    [[ $kv == *=* && ${kv%%=*} =~ $NAME_RE ]] || continue
    CUR[${kv%%=*}]=${kv#*=}
    VERS_FAKED=1
  done
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
  esac
  if [ "$VERS_STATE" != ok ]; then
    UPDATE_OK=0
    RECORD="${RECORD:+$RECORD; }rpm could not report the installed versions"
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
  body+="This session uses ${what[0]}${what[1]:+ and ${what[1]}}. To check and switch back, run $how."
  if [ "$DRY" = 1 ]; then say "  would queue a notification: $body"; return 0; fi
  [ -d "$GATE" ] || mkdir -p "$GATE" 2>/dev/null
  printf 'Safe mode after a Plasma change\n%s\n' "$body" >"$GATE/notify.tmp" && mv -f "$GATE/notify.tmp" "$GATE/notify" &&
    say "  notification queued"
}

# ---------- modes ----------

FUSION=0 LNF=
UPD_OFF=()
evaluate() { # the decision for every part; deploy only turns parts back on
  local p need_upd need_theme risky=0
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
    for p in lockscreen decoration; do part_on "$p" || rec_has "$p" && risky=1; done
    [ "$risky" = 1 ] && check_versions
    { [ -f "$DROPIN" ] || rec_has lockscreen; } && check_lock
  fi
  for p in "${PARTS[@]}"; do
    need_upd=0 need_theme=0
    case $p in
      lockscreen) [ "${LOCK_OK:-1}" = 1 ] || need_upd=1 ;;
      decoration) [ "${UPDATE_OK:-1}" = 1 ] || need_upd=1 ;;
    esac
    [ "$p" != decoration ] && [ "$FUSION" = 0 ] && need_theme=1
    if [ "$need_upd" = 1 ]; then
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
    echo "  login check: could not read the installed versions with rpm; the tested record stays as it was" >&2
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
