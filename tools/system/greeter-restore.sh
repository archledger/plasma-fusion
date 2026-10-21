#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Undo greeter-apply.sh: put back the login greeter's settings from its backups. Run as root.
#
#   greeter-restore.sh [BACKUP_DIR | --greeter sddm|plasmalogin] [--dry-run]
#
#   BACKUP_DIR   a /var/lib/plasma-fusion/greeter-backup-<UTC time> directory: go back to the
#                state saved in it (default: for SDDM's and plasma-login-manager's runs each, the
#                newest backup taken while that greeter did not use Plasma Fusion yet, i.e. the
#                look from before Plasma Fusion; the oldest when every one was taken while it
#                already did, chosen by hand before the first run)
#   --greeter G  without BACKUP_DIR: only that greeter's runs (the uninstall restores the greeter
#                that uses Plasma Fusion now, and leaves the other's later settings alone)
#   --dry-run    show what would be restored; change nothing
#   -h, --help
#
# Every run of greeter-apply.sh leaves one backup of what it is about to change. This script
# undoes the runs one by one, newest first, down to and including BACKUP_DIR, so a second run
# (for example after a package update, whose backup holds the Plasma Fusion state) never hides
# the state from before. For each backup, as the greeter user plasmalogin: the files in its
# ~/.config that run wrote (kdeglobals, plasmarc, kcminputrc, kwinoutputconfig.json: the saved
# copy, or removed when there was none) and ~/.config/kdedefaults/ (the greeter's session start
# rewrote it from the Plasma Fusion Global Theme); as root: /etc/plasmalogin.conf (byte for
# byte while nobody changed it since that run; otherwise only the wallpaper keys get their old
# values back) and the /etc/plasmalogin.conf.d/plasma-fusion.conf of the first version of
# greeter-apply.sh. Then ~/.cache is removed. Nothing is restarted: the greeter shows the old
# look the next time it starts. Each backup's config/ also holds the greeter's whole ~/.config
# as it was, for anything else.
#
# An SDDM run (info greeter=sddm) wrote /etc/sddm.conf.d/kde_settings.conf, /etc/sddm.conf (keys
# removed) and the theme's theme.conf.user. Each goes back byte for byte while nobody changed it
# since that run; otherwise key by key, and a key only while kde_settings.conf still has the value
# the run wrote: a theme or cursor chosen since on System Settings' Login Screen (SDDM) page stays.
# shellcheck disable=SC2016 # the sh -c snippets take their arguments as $0, $1, ...
set -euo pipefail

GREETER_USER=plasmalogin
DROPIN_NAME=plasma-fusion.conf
DROPIN_DIR=/etc/plasmalogin.conf.d
CONF=/etc/plasmalogin.conf
WALLPAPER_KEYS=("Greeter WallpaperPlugin" "Greeter/Wallpaper/org.kde.image/General Image"
                "Greeter/Wallpaper/org.kde.image/General PreviewImage")
BACKUP_ROOT=/var/lib/plasma-fusion

DRY=0 TARGET='' ONLY=''
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY=1 ;;
    --greeter)
      case ${2:-} in
        sddm) ONLY=SDDM ;;
        plasmalogin) ONLY=plasma-login-manager ;;
        *) echo "--greeter needs sddm or plasmalogin" >&2; exit 2 ;;
      esac
      shift ;;
    -h|--help) sed -n '/^#   greeter-restore.sh/,/^#   -h, --help/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) TARGET=$1 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die() { printf 'greeter-restore: %s\n' "$*" >&2; exit 1; }

# PF_GREETER_ROOT: the tests undo SDDM runs in a directory tree instead of / (never as root, who
# must not write through a tree another user prepared).
SYSROOT=${PF_GREETER_ROOT:-}
if [ -n "$SYSROOT" ]; then
  [ "$(id -u)" != 0 ] || die "PF_GREETER_ROOT is for the tests and never used as root"
else
  [ "$(id -u)" = 0 ] || die "run as root"
fi
BACKUP_ROOT=$SYSROOT$BACKUP_ROOT

# The backups, newest first (their names sort by time). greeter-apply.sh writes a backup's
# manifest and then its info before it changes any file, so one without both is a run that
# stopped before it changed anything: passed over, so that it cannot block every later restore.
mapfile -t FOUND < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'greeter-backup-*' 2>/dev/null | LC_ALL=C sort -r)
BACKUPS=()
for b in "${FOUND[@]}"; do
  if [ -f "$b/manifest" ] && [ -f "$b/info" ]; then
    BACKUPS+=("$b")
  else
    note "skip $b: incomplete (a run that stopped before it changed anything)"
  fi
done
[ "${#BACKUPS[@]}" -gt 0 ] || die "no backup in $BACKUP_ROOT"
# Which greeter a backup is of: an SDDM run's info says greeter=sddm, plasma-login-manager's says
# nothing.
kind() {
  if grep -qx 'greeter=sddm' "$1/info" 2>/dev/null; then echo SDDM; else echo plasma-login-manager; fi
}
CHAIN=() TARGETS=()
if [ -n "$TARGET" ]; then
  [ -z "$ONLY" ] || die "name a backup or --greeter, not both"
  TARGET=$(cd "$TARGET" && pwd) || die "$TARGET does not exist"
  case " ${BACKUPS[*]} " in *" $TARGET "*) ;; *) die "$TARGET is not one of the backups in $BACKUP_ROOT" ;; esac
  # Every run since that one, of either greeter.
  for b in "${BACKUPS[@]}"; do
    CHAIN+=("$b")
    [ "$b" = "$TARGET" ] && break
  done
  TARGETS=("$TARGET")
else
  # Each greeter's runs change files of their own and make a chain of their own: each goes back to
  # its newest backup taken while that greeter did not use Plasma Fusion yet. A backup whose run
  # found the greeter already on Plasma Fusion holds that state; go further back. Backups of the
  # first version of greeter-apply.sh have no "before" line: they count as taken before Plasma
  # Fusion.
  for k in SDDM plasma-login-manager; do
    [ -z "$ONLY" ] || [ "$k" = "$ONLY" ] || continue
    t='' runs=()
    for b in "${BACKUPS[@]}"; do
      [ "$(kind "$b")" = "$k" ] || continue
      runs+=("$b")
      if ! grep -qx 'before=plasma-fusion' "$b/info" 2>/dev/null; then t=$b; break; fi
    done
    [ "${#runs[@]}" -gt 0 ] || continue
    # Every one was taken while the greeter already used Plasma Fusion (chosen by hand before the
    # first run): back to the oldest, the state before any run of this script.
    [ -n "$t" ] || t=${runs[${#runs[@]}-1]}
    CHAIN+=("${runs[@]}")
    TARGETS+=("$t")
  done
  [ "${#TARGETS[@]}" -gt 0 ] || die "no $ONLY backup in $BACKUP_ROOT"
fi

# The plasma-login-manager greeter user, looked up for the first backup of its files (an SDDM
# run needs none).
GHOME='' GGROUP=''
need_greeter() {
  [ -z "$GHOME" ] || return 0
  [ -z "$SYSROOT" ] || die "PF_GREETER_ROOT is only for SDDM backups"
  command -v setpriv >/dev/null || die "setpriv (util-linux) is missing"
  entry=$(getent passwd "$GREETER_USER") || die "user $GREETER_USER does not exist"
  GHOME=$(printf '%s' "$entry" | cut -d: -f6)
  GGROUP=$(id -gn "$GREETER_USER")
}
as_greeter() { setpriv --reuid="$GREETER_USER" --regid="$GGROUP" --init-groups --no-new-privs -- \
  env -i PATH=/usr/bin:/bin HOME="$GHOME" LANG=C.UTF-8 "$@"; }
# kreadconfig6/kwriteconfig6 offscreen, with a HOME of their own (KConfig wants a writable
# ~/.config, or it pops up an error dialog).
own=$(mktemp -d "${TMPDIR:-/tmp}/plasma-fusion-greeter.XXXXXX")
trap 'rm -rf "$own"' EXIT
mkdir -p "$own/home/.config" "$own/run"
chmod 0700 "$own/run"
as_root_tool() { env -i PATH=/usr/bin:/bin HOME="$own/home" XDG_CONFIG_HOME="$own/home/.config" \
  XDG_RUNTIME_DIR="$own/run" XDG_CONFIG_DIRS=/etc/xdg QT_QPA_PLATFORM=offscreen LANG=C.UTF-8 "$@"; }
run() { [ "$DRY" = 1 ] || "$@"; }

kgroups() { # $1 group (nested with /): kreadconfig6/kwriteconfig6 --group arguments
  local g part
  IFS=/ read -r -a g <<<"$1"
  for part in "${g[@]}"; do printf -- '--group\0%s\0' "$part"; done
}
# Give the wallpaper keys of $CONF the values they had in the backup copy $1 (or remove them).
# Keys that already have that value are left alone: kwriteconfig6 rewrites the whole file and
# drops its comments.
restore_wallpaper_keys() {
  local e group key old cur args=()
  for e in "${WALLPAPER_KEYS[@]}"; do
    group=${e% *} key=${e##* }
    mapfile -d '' args < <(kgroups "$group")
    old='' cur=''
    [ ! -f "$1" ] || old=$(as_root_tool kreadconfig6 --file "$1" "${args[@]}" --key "$key" 2>/dev/null || true)
    [ ! -f "$CONF" ] || cur=$(as_root_tool kreadconfig6 --file "$CONF" "${args[@]}" --key "$key" 2>/dev/null || true)
    if [ "$old" = "$cur" ]; then
      note "  $key: ${old:-<unset>} (unchanged)"
    elif [ -n "$old" ]; then
      note "  $key = $old"
      run as_root_tool kwriteconfig6 --file "$CONF" "${args[@]}" --key "$key" "$old"
    else
      note "  $key removed"
      run as_root_tool kwriteconfig6 --file "$CONF" "${args[@]}" --key "$key" --delete
    fi
  done
}

# Put one file of the greeter's ~/.config back from backup $1 (path config/<name>).
restore_config_file() { # $1 backup, $2 name below .config
  local src=$1/config/$2 dest=$GHOME/.config/$2 mode
  if [ -L "$src" ]; then
    # The greeter user's own link: made again by that user, never followed by root.
    note "restore $dest (a link to $(readlink "$src"))"
    run as_greeter ln -sfn "$(readlink "$src")" "$dest"
  elif [ -f "$src" ]; then
    note "restore $dest"
    mode=$(stat -c %a "$src")
    # Root reads the backup (a regular file, checked above); the greeter user writes its own file.
    [ "$DRY" = 1 ] || as_greeter sh -c 'cat >"$0.plasma-fusion-new" && chmod "$1" "$0.plasma-fusion-new" && mv -f "$0.plasma-fusion-new" "$0"' \
      "$dest" "$mode" <"$src"
  else
    note "skip $dest: the backup holds no regular file"
  fi
}

# ---------- SDDM ----------

SDDM_KEYS=(Current CursorTheme)
SDDM_WRITTEN=()
kr() { # $1 file, $2 group, $3 key
  as_root_tool kreadconfig6 --file "$1" --group "$2" --key "$3" 2>/dev/null || true
}
# Give [GROUP] KEY of FILE what it was in the saved copy SAVED: the same value, an empty one too,
# or no key when the copy had none (an empty value and a missing key differ: an empty Current=
# hides a vendor file's theme).
kback() { # $1 file, $2 group, $3 key, $4 saved copy (or "" when there was none)
  if [ -n "$4" ] && [ -n "$(key_lines "$4" "$2" "$3")" ]; then
    run as_root_tool kwriteconfig6 --file "$1" --group "$2" --key "$3" "$(kr "$4" "$2" "$3")"
  else
    run as_root_tool kwriteconfig6 --file "$1" --group "$2" --key "$3" --delete
  fi
}
put_back() { # $1 saved copy (with the file's old mode, owner and group), $2 the file
  run install -m "$(stat -c %a "$1")" -- "$1" "$2"
  # The saved owner and group, not root's: a file SDDM's group reads (root:sddm, 0640) must stay so
  [ "$DRY" = 1 ] || [ -n "$SYSROOT" ] || chown --reference="$1" -- "$2"
}
# Put the lines of file LINES back into [SECTION] of FILE, in their order, right below the section's
# first header (or in a new section at the end), leaving every other line as it is. One batch: with
# several assignments of a key, the last still wins as before.
add_lines() { # $1 file, $2 section, $3 file of lines
  [ "$DRY" = 0 ] || return 0
  # The new file starts as a copy: it keeps the file's mode and owner (a 0600 file stays private).
  cp -p -- "$1" "$1.plasma-fusion-new"
  awk -v sect="[$2]" -v lines="$3" '
    function put(l) { while ((getline l <lines) > 0) print l; close(lines) }
    { print; t = $0; gsub(/^[ \t]+|[ \t]+$/, "", t); if (!done && t == sect) { put(); done = 1 } }
    END { if (!done) { print ""; print sect; put() } }' "$1" >"$1.plasma-fusion-new"
  mv -f -- "$1.plasma-fusion-new" "$1"
}
# The lines of FILE that set [SECTION] KEY, an empty value included, as SDDM's parser finds them
# (greeter-apply.sh sddm_conf).
key_lines() { # $1 file, $2 section, $3 key
  [ -f "$1" ] || return 0
  awk -v want_s="$2" -v want_k="$3" '
    function trim(s) { sub(/^[ \t\r\f\v]+/, "", s); sub(/[ \t\r\f\v]+$/, "", s); return s }
    BEGIN { s = "General" }
    {
      line = $0
      if ((c = index(line, "#")) > 0) line = substr(line, 1, c - 1)
      line = trim(line)
      if ((e = index(line, "=")) > 0) {
        if (s == want_s && trim(substr(line, 1, e - 1)) == want_k) print $0
      } else if (line ~ /^\[.*\]$/) s = substr(line, 2, length(line) - 2)
    }' "$1"
}
# The value SDDM reads for [SECTION] KEY of FILE: its last assignment, from the first # on cut off
# (KConfig, which kreadconfig6 uses, keeps such a comment in the value).
key_value() { # $1 file, $2 section, $3 key
  key_lines "$1" "$2" "$3" | tail -n 1 | awk '{
    l = $0; if ((c = index(l, "#")) > 0) l = substr(l, 1, c - 1)
    v = substr(l, index(l, "=") + 1); sub(/^[ \t\r\f\v]+/, "", v); sub(/[ \t\r\f\v]+$/, "", v); print v }'
}

# Whether SDDM's QDir::LocaleAware listing may order drop-ins $1 and $2 (default kde_settings.conf)
# otherwise than byte order does (greeter-apply.sh sddm_order_depends_on_locale: only a first
# difference in a lower-case ASCII letter or digit on both sides, or one name beginning with the
# other, is sure).
order_depends_on_locale() { # $1 file name, [$2 file name]
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
# The file whose [Theme] KEY SDDM reads last - SDDM 0.21 reads /usr/lib/sddm/sddm.conf.d/*, then
# /etc/sddm.conf.d/* (each sorted, as greeter-apply.sh orders them), then /etc/sddm.conf - with
# the two files this restore changes taken from SDDM_ROOT. Empty when no file sets it; "?" when
# another file of its directory that sets the key may be read after it depending on the locale:
# one with another value, or either being kde_settings.conf (the run's value there is what is to
# be decided; nothing is then put back over the drop-in). Files that do not set the key do not
# count, kde_settings.conf among them.
deciding_file() { # $1 key
  local f i last
  local -a files=() dirs=() values=()
  while IFS= read -r f; do
    [ -n "$(key_lines "$f" Theme "$1")" ] || continue
    files+=("$f") values+=("$(key_value "$f" Theme "$1")")
    # Where SDDM lists it: kde_settings.conf comes from SDDM_ROOT, among /etc's drop-ins
    case $f in
      "$SDDM_ROOT/etc/sddm.conf.d/kde_settings.conf" | "$SYSROOT/etc/sddm.conf.d/"*) dirs+=(etc) ;;
      "$SYSROOT/usr/lib/sddm/sddm.conf.d/"*) dirs+=(vendor) ;;
      *) dirs+=(conf) ;;
    esac
  done < <(
    # -H: a configuration directory that is itself a link is listed too, as SDDM's QDir lists it
    find -H "$SYSROOT/usr/lib/sddm/sddm.conf.d" -mindepth 1 -maxdepth 1 ! -name '.*' -xtype f 2>/dev/null | LC_ALL=C sort
    { find -H "$SYSROOT/etc/sddm.conf.d" -mindepth 1 -maxdepth 1 ! -name '.*' ! -name kde_settings.conf -xtype f \
        -printf '%f\t%p\n' 2>/dev/null
      printf 'kde_settings.conf\t%s\n' "$SDDM_ROOT/etc/sddm.conf.d/kde_settings.conf"
    } | LC_ALL=C sort | cut -f2-
    printf '%s\n' "$SDDM_ROOT/etc/sddm.conf")
  [ "${#files[@]}" -gt 0 ] || return 0
  last=$((${#files[@]} - 1))
  if [ "${dirs[last]}" != conf ]; then
    for ((i = 0; i < last; i++)); do
      [ "${dirs[i]}" = "${dirs[last]}" ] && order_depends_on_locale "${files[i]##*/}" "${files[last]##*/}" || continue
      if [ "${values[i]}" != "${values[last]}" ] || [ "${files[i]##*/}" = kde_settings.conf ] ||
        [ "${files[last]##*/}" = kde_settings.conf ]; then
        printf '?'
        return
      fi
    done
  fi
  printf '%s' "${files[last]}"
}

undo_sddm() { # $1 backup directory of an SDDM run
  local backup=$1 state path file applied k cur image line saved all=1 moved=0 tree f dir_was real_was now
  local kde=$SDDM_ROOT/etc/sddm.conf.d/kde_settings.conf conf=$SDDM_ROOT/etc/sddm.conf user_conf
  local -A ours=() still=() decides=()
  # A dry run changes its copy of the files (SDDM_ROOT), so each run's undo sees the state the
  # newer ones left, as the real restore does; the system's files stay as they are.
  [ "$SDDM_ROOT" = "$SYSROOT" ] || local DRY=0
  user_conf=$SDDM_ROOT$(sed -n 's/^theme_dir=//p' "$backup/info")/theme.conf.user
  image=$(sed -n 's/^image=//p' "$backup/info")
  ours[Current]=$(sed -n 's/^theme=//p' "$backup/info")
  ours[CursorTheme]=$(sed -n 's/^cursors=//p' "$backup/info")
  say "Undo the run of greeter-apply.sh that made $backup (SDDM)"
  for k in kreadconfig6 kwriteconfig6; do command -v "$k" >/dev/null || die "$k is missing (kf6-kconfig)"; done
  # A link put in kde_settings.conf's place since is a newer choice, whatever it reads as: it is
  # left alone below, so nothing read through it may let /etc/sddm.conf's old lines back over it.
  [ ! -L "$kde" ] || note "${kde#"$SDDM_ROOT"} is a link now: its keys count as chosen since"
  # The theme tree the run's Current names now: with ThemeDir pointed elsewhere since, that name is
  # another tree's theme - the administrator's choice, kept (as when it is not known which file
  # decides ThemeDir).
  f=$(deciding_file ThemeDir)
  case $f in
    '') tree=/usr/share/sddm/themes ;;
    '?') tree='' ;;
    *) tree=$(key_value "$f" Theme ThemeDir) ;;
  esac
  # Also where that path leads, links resolved: a ThemeDir link retargeted since keeps the path and
  # names another tree (backups from before theme_real= compare the paths only). A theme that is
  # gone with its path still leading where it did names no other theme: the run is undone.
  dir_was=$(sed -n 's/^theme_dir=//p' "$backup/info") real_was=$(sed -n 's/^theme_real=//p' "$backup/info")
  if [ "$(realpath -ms -- "$tree/${ours[Current]}")" != "$(realpath -ms -- "$dir_was")" ]; then
    moved=1
    note "[Theme] ThemeDir is ${tree:-not known} now: Current=${ours[Current]} names another theme tree's theme (kept)"
  elif [ -n "$real_was" ]; then
    if now=$(realpath -m -- "$SYSROOT$tree/${ours[Current]}"); then
      [ -z "$SYSROOT" ] || now=${now#"$(realpath -m -- "$SYSROOT")"}
    else
      now='not resolvable'
    fi
    if [ "$now" != "$real_was" ]; then
      moved=1
      note "[Theme] ThemeDir $tree leads to $now now (the run's was $real_was): Current=${ours[Current]} names another theme tree's theme (kept)"
    fi
  fi
  # The keys System Settings' file still has the run's value for. Only these go back: one changed
  # since (another theme chosen on the page) is kept. /etc/sddm.conf, read last, gets its old lines
  # back only while that file still decides the key: a later drop-in may have chosen since.
  for k in "${SDDM_KEYS[@]}"; do
    if [ ! -L "$kde" ] && [ -n "${ours[$k]}" ] && [ "$(key_value "$kde" Theme "$k")" = "${ours[$k]}" ] &&
      { [ "$k" != Current ] || [ "$moved" = 0 ]; }; then
      still[$k]=1
      [ "$(deciding_file "$k")" != "$kde" ] || decides[$k]=1
    fi
    [ -n "${decides[$k]:-}" ] || all=0
  done
  while read -r state path <&3; do
    case $path in
      etc/sddm.conf.d/kde_settings.conf) file=$kde ;;
      etc/sddm.conf) file=$conf ;;
      sddm-theme/theme.conf.user) file=$user_conf ;;
      *) note "skip unknown manifest entry: $state $path"; continue ;;
    esac
    applied=$backup/$path.applied
    if [ ! -f "$applied" ]; then
      note "${file#"$SDDM_ROOT"} was not changed by this run (kept)"
      continue
    fi
    # greeter-apply.sh wrote a file: a link there now was put there by someone else since.
    if [ -L "$file" ]; then
      note "${file#"$SDDM_ROOT"} is a link now: left alone"
      continue
    fi
    SDDM_WRITTEN+=("$file")
    # Unchanged since that run: back as it was. /etc/sddm.conf only while the keys it gets back
    # are still the run's choice (it is read last and would override a theme chosen since), and
    # kde_settings.conf only while its Current still names the run's theme tree.
    if [ -f "$file" ] && cmp -s "$file" "$applied" && { [ "$path" != etc/sddm.conf ] || [ "$all" = 1 ]; } &&
      { [ "$path" != etc/sddm.conf.d/kde_settings.conf ] || [ "$moved" = 0 ]; }; then
      if [ "$state" = present ]; then
        note "restore ${file#"$SDDM_ROOT"} (unchanged since that run)"
        put_back "$backup/$path" "$file"
      else
        note "remove ${file#"$SDDM_ROOT"} (there was none)"
        run rm -f -- "$file"
      fi
      continue
    fi
    if [ ! -e "$file" ]; then
      note "${file#"$SDDM_ROOT"} was removed after that run (left that way)"
      continue
    fi
    note "${file#"$SDDM_ROOT"} changed after that run: key by key"
    case $path in
      etc/sddm.conf.d/kde_settings.conf)
        saved=''
        [ "$state" != present ] || saved=$backup/$path
        for k in "${SDDM_KEYS[@]}"; do
          if [ -n "${still[$k]:-}" ]; then
            if [ -n "$saved" ] && [ -n "$(key_lines "$saved" Theme "$k")" ]; then
              note "  [Theme] $k = $(kr "$saved" Theme "$k")"
            else
              note "  [Theme] $k removed (there was none)"
            fi
            kback "$file" Theme "$k" "$saved"
          else
            note "  [Theme] $k: $(kr "$file" Theme "$k") was chosen since (kept)"
          fi
        done ;;
      etc/sddm.conf)
        # The lines the run removed come back while their key is the run's choice yet and nobody
        # set it in this file since.
        [ "$state" = present ] || continue
        for k in "${SDDM_KEYS[@]}"; do
          [ -n "$(key_lines "$backup/$path" Theme "$k")" ] || continue
          if [ -n "${decides[$k]:-}" ] && [ -z "$(key_lines "$file" Theme "$k")" ]; then
            key_lines "$backup/$path" Theme "$k" >"$own/lines"
            while IFS= read -r line; do note "  [Theme] $line"; done <"$own/lines"
            add_lines "$file" Theme "$own/lines"
          else
            note "  [Theme] $k: not put back (set in this file, or chosen since here or in a later file)"
          fi
        done ;;
      sddm-theme/theme.conf.user)
        saved=''
        [ "$state" != present ] || saved=$backup/$path
        cur=$(kr "$file" General background)
        if [ -f "$file" ] && [ "$cur" = "$image" ]; then
          note "  background back as it was"
          kback "$file" General background "$saved"
        else
          note "  background: ${cur:-<unset>} was chosen since (kept)"
        fi ;;
    esac
  done 3<"$backup/manifest"
}

# ---------- plasma-login-manager ----------

undo() { # $1 backup directory
  local backup=$1 state path applied f
  if grep -qx 'greeter=sddm' "$backup/info" 2>/dev/null; then undo_sddm "$backup"; return; fi
  need_greeter
  say "Undo the run of greeter-apply.sh that made $backup"
  run as_greeter mkdir -p "$GHOME/.config"
  # The manifest comes in on descriptor 3, so no command in the loop can read from it.
  while read -r state path <&3; do
    case $path in
      config/kdedefaults)
        # Put the directory back as it was (the greeter's session start rewrote it).
        note "$([ "$state" = present ] && echo restore || echo remove) $GHOME/.config/kdedefaults/"
        run as_greeter rm -rf "$GHOME/.config/kdedefaults"
        if [ "$state" = present ] && [ "$DRY" = 0 ]; then
          # tar stores links as links (it never follows them), the greeter user unpacks.
          tar -C "$backup/config" -cf - kdedefaults | as_greeter tar -C "$GHOME/.config" -xf - --no-same-owner
        fi
        ;;
      config/*)
        f=${path#config/}
        if [ "$state" = present ]; then
          restore_config_file "$backup" "$f"
        else
          note "remove $GHOME/.config/$f (there was none)"
          run as_greeter rm -f "$GHOME/.config/$f"
        fi
        ;;
      etc/plasmalogin.conf)
        applied=$backup/etc/plasmalogin.conf.applied
        if [ ! -f "$applied" ]; then
          note "$CONF was not changed by this run (kept)"
        elif [ -f "$CONF" ] && cmp -s "$CONF" "$applied"; then
          if [ "$state" = present ]; then
            note "restore $CONF (unchanged since that run: the saved copy goes back as it was)"
            run install -m 0644 -o root -g root "$backup/etc/plasmalogin.conf" "$CONF"
          else
            note "remove $CONF (there was none)"
            run rm -f "$CONF"
          fi
        else
          note "$CONF changed after that run: put back only the wallpaper keys"
          restore_wallpaper_keys "$backup/etc/plasmalogin.conf"
        fi
        ;;
      etc/"$DROPIN_NAME")
        if [ "$state" = present ]; then
          note "restore $DROPIN_DIR/$DROPIN_NAME"
          run install -m 0644 -o root -g root "$backup/etc/$DROPIN_NAME" "$DROPIN_DIR/$DROPIN_NAME"
        else
          note "remove $DROPIN_DIR/$DROPIN_NAME"
          run rm -f "$DROPIN_DIR/$DROPIN_NAME"
        fi
        ;;
      *) note "skip unknown manifest entry: $state $path" ;;
    esac
  done 3<"$backup/manifest"
}

for t in "${TARGETS[@]}"; do
  say "Restore the login greeter ($(kind "$t")) to $t$([ "$DRY" = 1 ] && echo ' (dry run: nothing is changed)')"
done
# SDDM's files: the system's, or for a dry run a copy of them in the temporary directory
SDDM_ROOT=$SYSROOT
if [ "$DRY" = 1 ]; then
  SDDM_ROOT=$own/dry
  for b in "${CHAIN[@]}"; do
    [ "$(kind "$b")" = SDDM ] || continue
    for f in etc/sddm.conf.d/kde_settings.conf etc/sddm.conf "$(sed -n 's/^theme_dir=//p' "$b/info")/theme.conf.user"; do
      f=${f#/}
      mkdir -p "$(dirname "$SDDM_ROOT/$f")"
      if [ -e "$SYSROOT/$f" ] || [ -L "$SYSROOT/$f" ]; then
        [ -e "$SDDM_ROOT/$f" ] || [ -L "$SDDM_ROOT/$f" ] || cp -a -- "$SYSROOT/$f" "$SDDM_ROOT/$f"
      fi
    done
  done
fi
[ "${#CHAIN[@]}" = 1 ] || say "(${#CHAIN[@]} runs of greeter-apply.sh to undo, newest first)"
for b in "${CHAIN[@]}"; do undo "$b"; done
if [ -n "$GHOME" ]; then
  note "remove $GHOME/.cache (the greeter rebuilds it)"
  run as_greeter rm -rf "$GHOME/.cache"
fi

if [ "$DRY" = 0 ] && [ -z "$SYSROOT" ] && command -v restorecon >/dev/null && command -v selinuxenabled >/dev/null && selinuxenabled; then
  if [ -n "$GHOME" ]; then
    restorecon -R "$GHOME/.config" || true
    [ ! -e "$CONF" ] || restorecon "$CONF" || true
  fi
  for f in "${SDDM_WRITTEN[@]}"; do [ ! -e "$f" ] || restorecon "$f" || true; done
fi
say "Done. The greeter shows its previous look the next time it starts (after the next logout or reboot)."
