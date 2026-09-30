#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Undo greeter-apply.sh: put back the login greeter's settings from its backups. Run as root.
#
#   greeter-restore.sh [BACKUP_DIR] [--dry-run]
#
#   BACKUP_DIR   a /var/lib/plasma-fusion/greeter-backup-<UTC time> directory: go back to the
#                state saved in it (default: the newest backup taken while the greeter did not
#                use Plasma Fusion yet, i.e. the look from before Plasma Fusion)
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
# shellcheck disable=SC2016 # the sh -c snippets take their arguments as $0, $1, ...
set -euo pipefail

GREETER_USER=plasmalogin
DROPIN_NAME=plasma-fusion.conf
DROPIN_DIR=/etc/plasmalogin.conf.d
CONF=/etc/plasmalogin.conf
WALLPAPER_KEYS=("Greeter WallpaperPlugin" "Greeter/Wallpaper/org.kde.image/General Image"
                "Greeter/Wallpaper/org.kde.image/General PreviewImage")
BACKUP_ROOT=/var/lib/plasma-fusion

DRY=0 TARGET=''
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '/^#   greeter-restore.sh/,/^#   -h, --help/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) TARGET=$1 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die() { printf 'greeter-restore: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root"
command -v setpriv >/dev/null || die "setpriv (util-linux) is missing"

# The backups, newest first (their names sort by time).
mapfile -t BACKUPS < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'greeter-backup-*' 2>/dev/null | LC_ALL=C sort -r)
[ "${#BACKUPS[@]}" -gt 0 ] || die "no backup in $BACKUP_ROOT"
if [ -n "$TARGET" ]; then
  TARGET=$(cd "$TARGET" && pwd) || die "$TARGET does not exist"
  case " ${BACKUPS[*]} " in *" $TARGET "*) ;; *) die "$TARGET is not one of the backups in $BACKUP_ROOT" ;; esac
else
  # A backup whose run found the greeter already on Plasma Fusion holds that state; go further
  # back. Backups of the first version of greeter-apply.sh have no "before" line: they count as
  # taken before Plasma Fusion.
  for b in "${BACKUPS[@]}"; do
    if ! grep -qx 'before=plasma-fusion' "$b/info" 2>/dev/null; then TARGET=$b; break; fi
  done
  [ -n "$TARGET" ] || die "every backup in $BACKUP_ROOT was taken while the greeter already used Plasma Fusion; name one"
fi
CHAIN=()
for b in "${BACKUPS[@]}"; do
  [ -f "$b/manifest" ] || die "$b is not a greeter-apply.sh backup (no manifest)"
  CHAIN+=("$b")
  [ "$b" = "$TARGET" ] && break
done

entry=$(getent passwd "$GREETER_USER") || die "user $GREETER_USER does not exist"
GHOME=$(printf '%s' "$entry" | cut -d: -f6)
GGROUP=$(id -gn "$GREETER_USER")
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

undo() { # $1 backup directory
  local backup=$1 state path applied f
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

say "Restore the login greeter to $TARGET$([ "$DRY" = 1 ] && echo ' (dry run: nothing is changed)')"
[ "${#CHAIN[@]}" = 1 ] || say "(${#CHAIN[@]} runs of greeter-apply.sh to undo, newest first)"
for b in "${CHAIN[@]}"; do undo "$b"; done
note "remove $GHOME/.cache (the greeter rebuilds it)"
run as_greeter rm -rf "$GHOME/.cache"

if [ "$DRY" = 0 ] && command -v restorecon >/dev/null && command -v selinuxenabled >/dev/null && selinuxenabled; then
  restorecon -R "$GHOME/.config" || true
  [ ! -e "$CONF" ] || restorecon "$CONF" || true
fi
say "Done. The greeter shows its previous look the next time it starts (after the next logout or reboot)."
