#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of fusion-config.sh's config writes that must keep a user's choice, against a
# throw-away XDG_CONFIG_HOME: the key helpers (read_key, set_key, managed_key), the hot-corner
# step, the on-screen keyboard step, workspace step and privacy migration are taken out as
# they are and run with the real kreadconfig6 and kwriteconfig6 (KWin's D-Bus calls are stubbed). Test tooling only, not installed; never touches the caller's configuration.
#
#   config-keys-unit.sh BASE
#
# BASE must be a scratch directory on disk (not /tmp); it is emptied first.
set -euo pipefail
BASE=${1:?scratch directory}
BASE=$(realpath -m -- "$BASE")
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
TOOL=$HERE/../fusion-config.sh
rm -rf "${BASE:?}"
mkdir -p "$BASE"

# The functions, by name: a one-line "NAME() { ...; }", or from "NAME() {" to the first "}" at
# the start of a line.
extract() {
  local name
  for name in "$@"; do
    awk -v n="$name" '
      $0 ~ "^" n "\\(\\) \\{" { on = 1; print; if ($0 ~ /\}[[:space:]]*$/) exit; next }
      on { print } on && /^}/ { exit }' "$TOOL"
  done
}
# The hot-corner step: from its comment up to the blur settings that follow it.
hot_corner_step() {
  awk '/^# Hot corner: / { on = 1 } on && /Effect-blur/ { exit } on { print }' "$TOOL"
}
LIB=$BASE/lib.sh
{
  grep -m1 '^UNSET=' "$TOOL"
  grep -m1 '^OSK_DESKTOP=' "$TOOL"
  extract note read_key show set_key managed_key upgrade_log keyboard_policy_touch migrate_lock_notifications install_config make_backup
  echo 'UPGRADE_LOG=()'
} >"$LIB"
LOCK_STEP=$BASE/lock-migration-step.sh
awk '/^previous_lock=/ { on = 1 } on { print } on && /^migrate_lock_notifications / { exit }' "$TOOL" >"$LOCK_STEP"
grep -q '^migrate_lock_notifications ' "$LOCK_STEP" || { echo "FAIL: the privacy migration call was not found"; exit 1; }
# The on-screen keyboard step: from its comment up to the accent pop-up setting that follows it.
osk_step() {
  awk '/^# On-screen keyboard \(TABLET T6\)/ { on = 1 } on && /^# plasma-keyboard \(6\.7 and later\)/ { exit } on { print }' "$TOOL"
}
STEP=$BASE/step.sh
hot_corner_step >"$STEP"
grep -q 'BorderActivate' "$STEP" || { echo "FAIL: the hot-corner step was not found in fusion-config.sh"; exit 1; }

PASS=0 FAIL=0
# CASE DESCRIPTION, PREV_VERSION, HOT_CORNER, the value before (or "unset"), the value wanted
case_hot() {
  local desc=$1 prev=$2 flag=$3 before=$4 want=$5 home got
  home=$BASE/home-$((PASS + FAIL))
  mkdir -p "$home"
  [ "$before" = unset ] || printf '[Effect-overview]\nBorderActivate=%s\n' "$before" >"$home/kwinrc"
  got=$(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home" bash -c '
    set -euo pipefail
    . "$1"
    DRY=0 CHANGES=0 PREV_VERSION=$2 CONFIG_VERSION=2 HOT_CORNER=$3
    . "$4" >/dev/null
    kreadconfig6 --file kwinrc --group Effect-overview --key BorderActivate' _ "$LIB" "$prev" "$flag" "$STEP" 2>/dev/null) || got="(error)"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1)); echo "PASS $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $desc: BorderActivate=$got, want $want"
  fi
}

case_hot "first run turns the corner off" 0 0 7 9
case_hot "first run with --hot-corner turns it on" 0 1 unset 7
case_hot "a later run keeps the corner the user turned on" 2 0 7 7
case_hot "a later run keeps more edges the user set" 2 0 "1,7" "1,7"
# An unset key is KWin's default, the top-left corner: System Settings > Screen Edges deletes the
# key when the user turns that corner on.
case_hot "a later run keeps an unset key (KWin's default corner, on)" 2 0 unset ""
case_hot "a later run keeps the corner off" 2 0 9 9
case_hot "--hot-corner turns an off corner on" 2 1 9 7

OSKSTEP=$BASE/osk-step.sh
osk_step >"$OSKSTEP"
grep -q 'InputMethod' "$OSKSTEP" || { echo "FAIL: the on-screen keyboard step was not found in fusion-config.sh"; exit 1; }
# CASE DESCRIPTION, PREV_VERSION, the keyboard policy in the layout file, "live" (plasmashell
# answers with that policy; else it is not running), InputMethod before, InputMethod wanted
OSK=/usr/share/applications/org.kde.plasma.keyboard.desktop
case_osk() {
  local desc=$1 prev=$2 policy=$3 live=$4 before=$5 want=$6 home got
  home=$BASE/home-$((PASS + FAIL))
  mkdir -p "$home"
  printf '[Wayland]\nInputMethod=%s\n' "$before" >"$home/kwinrc"
  printf '[Containments][2][Applets][5]\nplugin=org.plasmafusion.quicksettings\n\n[Containments][2][Applets][5][General]\nkeyboardPolicy=%s\n' \
    "$policy" >"$home/plasma-org.kde.plasma.desktop-appletsrc"
  got=$(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home" bash -c '
    set -euo pipefail
    . "$1"
    DRY=0 CHANGES=0 PREV_VERSION=$2 CONFIG_VERSION=2 CONFIG=$HOME LIVE=$3 POLICY=$4
    bus() { echo "b false"; }
    system_data_path() { return 1; }
    has_name() { [ "$LIVE" = live ]; }
    plasmashell_eval() { if [ "$POLICY" = touch ]; then echo touch; else echo; fi; }
    . "$5" >/dev/null
    kreadconfig6 --file kwinrc --group Wayland --key InputMethod' _ "$LIB" "$prev" "$live" "$policy" "$OSKSTEP" 2>/dev/null) || got="(error)"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1)); echo "PASS $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $desc: InputMethod=$got, want $want"
  fi
}
case_osk "laptop posture, policy Tablet mode: the keyboard goes off" 2 tablet live "$OSK" ""
case_osk "laptop posture, policy On touch: the keyboard stays" 2 touch live "$OSK" "$OSK"
case_osk "policy On touch read from the layout file without plasmashell" 2 touch no "$OSK" "$OSK"
case_osk "policy Never: off" 2 never no "$OSK" ""
case_osk "another input method the user chose is kept" 2 tablet live /usr/share/applications/fcitx5.desktop /usr/share/applications/fcitx5.desktop

# The workspace step: from its header up to the shortcuts step that follows it.
workspaces_step() {
  awk '/^# ---------- 2\. virtual desktops ----------/ { on = 1 } on && /^# ---------- 3\. shortcuts/ { exit } on { print }' "$TOOL"
}
WSSTEP=$BASE/workspaces-step.sh
workspaces_step >"$WSSTEP"
grep -q 'createDesktop' "$WSSTEP" || { echo "FAIL: the workspace step was not found in fusion-config.sh"; exit 1; }
# CASE DESCRIPTION, kwinrc [Plugins] plasmafusion-workspacesEnabled (or "unset"), the workspaces
# KWin is asked to create ("position name;" each, empty for none). KWin has Work and Design.
case_ws() {
  local desc=$1 enabled=$2 want=$3 home got
  home=$BASE/home-$((PASS + FAIL))
  mkdir -p "$home/backup"
  [ "$enabled" = unset ] || printf '[Plugins]\nplasmafusion-workspacesEnabled=%s\n' "$enabled" >"$home/kwinrc"
  printf '{"type":"a(uss)","data":[[0,"id-1","Work"],[1,"id-2","Design"]]}\n' >"$home/backup/desktops.json"
  got=$(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home" bash -c '
    set -euo pipefail
    . "$1"
    DRY=0 CHANGES=0 BACKUP=$HOME/backup
    DESKTOP_NAMES=(Work Design Media Chat)
    say() { :; }
    bus_json() { cat "$BACKUP/desktops.json"; }
    bus() {
      case "$*" in
        *" rows") echo "u 1" ;;
        *createDesktop*) shift 5; echo "$2 $3;" >>"$HOME/created" ;;
        *) echo "$*" >>"$HOME/calls" ;;
      esac
    }
    . "$2" >/dev/null
    tr -d "\n" <"$HOME/created" 2>/dev/null || true' _ "$LIB" "$WSSTEP" 2>/dev/null) || got="(error)"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1)); echo "PASS $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $desc: created '$got', want '$want'"
  fi
}
case_ws "the missing named workspaces are created" unset "2 Media;3 Chat;"
case_ws "dynamic workspaces off: the same" false "2 Media;3 Chat;"
case_ws "dynamic workspaces on: none is created (the script would remove them again)" true ""

# Legacy privacy opt-outs are applied once, without enabling either notification option.
migration_case() {
  local desc=$1 legacy=$2 current=$3 want=$4 mode=${5:-normal} home got marker=1 key
  home=$BASE/lock-$((PASS + FAIL))
  mkdir -p "$home"
  for key in showNotifications showNotificationSummaries; do
    [ "$legacy" = unset ] || kwriteconfig6 --file "$home/kscreenlockerrc" --group 'Greeter][LnF][General' --key "$key" "$legacy"
    [ "$current" = unset ] || kwriteconfig6 --file "$home/kscreenlockerrc" --group Greeter --group LnF --group General --key "$key" "$current"
  done
  kwriteconfig6 --file "$home/kscreenlockerrc" --group 'Greeter][LnF][General' --key Unrelated old
  kwriteconfig6 --file "$home/kscreenlockerrc" --group Greeter --group LnF --group General --key Unrelated new
  [ "$mode" != dry ] || marker='unset'
  got=$(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home" bash -c '
    set -euo pipefail
    . "$1"
    CONFIG=$HOME DRY=0 CHANGES=0
    [ "$2" != dry ] || DRY=1
    if [ "$2" = backup ]; then
      cp "$CONFIG/kscreenlockerrc" "$CONFIG/before-update"
      for key in showNotifications showNotificationSummaries; do
        kwriteconfig6 --file "$CONFIG/kscreenlockerrc" --group "Greeter][LnF][General" --key "$key" true
      done
      migrate_lock_notifications "$CONFIG/before-update" >/dev/null
    else
      migrate_lock_notifications >/dev/null
    fi
    if [ "$2" = reenable ]; then
      for key in showNotifications showNotificationSummaries; do
        kwriteconfig6 --file "$CONFIG/kscreenlockerrc" --group Greeter --group LnF --group General --key "$key" true
      done
      migrate_lock_notifications >/dev/null
    fi
    for key in showNotifications showNotificationSummaries; do
      printf "%s|" "$(kreadconfig6 --file "$CONFIG/kscreenlockerrc" --group Greeter --group LnF --group General --key "$key" --default unset)"
    done
    printf "%s|" "$(kreadconfig6 --file "$CONFIG/plasmafusionrc" --group Config --key LockNotificationGroupsVersion --default unset)"
    printf "%s|" "$(kreadconfig6 --file "$CONFIG/kscreenlockerrc" --group "Greeter][LnF][General" --key Unrelated)"
    kreadconfig6 --file "$CONFIG/kscreenlockerrc" --group Greeter --group LnF --group General --key Unrelated
    ' _ "$LIB" "$mode" 2>/dev/null) || got='(error)'
  if [ "$got" = "$want|$want|$marker|old|new" ]; then
    PASS=$((PASS + 1)); echo "PASS $desc"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $desc: $got"
  fi
}
migration_case "legacy opt-outs populate missing settings" false unset false
migration_case "legacy opt-outs override enabled settings once" false true false
migration_case "existing opt-outs remain disabled" false false false
migration_case "legacy enabled values do not create enabled settings" true unset unset
migration_case "legacy enabled values do not override current opt-outs" true false false
migration_case "no legacy choice preserves current enabled settings" unset true true
migration_case "no legacy choice preserves current opt-outs" unset false false
migration_case "no choices do not create notification settings" unset unset unset
migration_case "dry run does not write settings or a completion marker" false true true dry
migration_case "later explicit choices survive repeated migration" false true true reenable
migration_case "pre-update opt-outs survive replacement configuration" false true false backup

# Even when called from a conditional, failed or ineffective writes must not mark completion.
for failure in failed-write ignored-write failed-marker ignored-marker failed-legacy-read failed-marker-read failed-marker-readback; do
  home=$BASE/lock-$failure
  mkdir -p "$home"
  kwriteconfig6 --file "$home/kscreenlockerrc" --group 'Greeter][LnF][General' --key showNotifications false
  kwriteconfig6 --file "$home/kscreenlockerrc" --group Greeter --group LnF --group General --key showNotifications true
  got=$(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home" bash -c '
    set -euo pipefail
    . "$1"
    CONFIG=$HOME DRY=0 CHANGES=0
    failure=$2
    native_write=$(command -v kwriteconfig6)
    native_read=$(command -v kreadconfig6)
    if [[ $failure == failed-*-read* ]]; then
      kreadconfig6() {
        if { [ "$failure" = failed-legacy-read ] && [[ $* == *"Greeter][LnF][General"* ]]; } ||
           { [ "$failure" = failed-marker-read ] && [[ $* == *LockNotificationGroupsVersion* ]]; } ||
           { [ "$failure" = failed-marker-readback ] && [[ $* == *LockNotificationGroupsVersion* && $* != *--default* ]]; }; then
          return 1
        fi
        "$native_read" "$@"
      }
    elif [ "$failure" = failed-write ]; then
      kwriteconfig6() { return 1; }
    elif [ "$failure" = ignored-write ]; then
      kwriteconfig6() {
        [[ $* != *LockNotificationGroupsVersion* ]] || "$native_write" "$@"
      }
    else
      kwriteconfig6() {
        if [[ $* == *LockNotificationGroupsVersion* ]]; then
          [ "$failure" != failed-marker ] || return 1
          return 0
        fi
        "$native_write" "$@"
      }
    fi
    status=0
    migrate_lock_notifications >/dev/null || status=$?
    printf "%s|" "$status"
    "$native_read" --file "$CONFIG/plasmafusionrc" --group Config --key LockNotificationGroupsVersion --default unset
    ' _ "$LIB" "$failure" 2>/dev/null) || got='(error)'
  expected='1|unset'
  [ "$failure" != failed-marker-readback ] || expected='1|1'
  if [ "$got" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "PASS $failure reports failure at the expected completion state"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $failure: $got"
  fi
done

for disabled_key in showNotifications showNotificationSummaries; do
  home=$BASE/mixed-$disabled_key
  mkdir -p "$home"
  for key in showNotifications showNotificationSummaries; do
    kwriteconfig6 --file "$home/kscreenlockerrc" --group 'Greeter][LnF][General' --key "$key" true
    kwriteconfig6 --file "$home/kscreenlockerrc" --group Greeter --group LnF --group General --key "$key" true
  done
  kwriteconfig6 --file "$home/kscreenlockerrc" --group 'Greeter][LnF][General' --key "$disabled_key" false
  got=$(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home" bash -c '
    set -euo pipefail
    . "$1"
    CONFIG=$HOME DRY=0 CHANGES=0
    migrate_lock_notifications >/dev/null
    printf "%s|" "$(kreadconfig6 --file "$CONFIG/kscreenlockerrc" --group Greeter --group LnF --group General --key showNotifications)"
    kreadconfig6 --file "$CONFIG/kscreenlockerrc" --group Greeter --group LnF --group General --key showNotificationSummaries
    ' _ "$LIB" 2>/dev/null) || got='(error)'
  expected='false|true'
  [ "$disabled_key" != showNotificationSummaries ] || expected='true|false'
  if [ "$got" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "PASS only the $disabled_key opt-out is migrated"
  else
    FAIL=$((FAIL + 1)); echo "FAIL mixed preferences for $disabled_key: $got"
  fi
done

# Exercise the real backup, installation and migration functions; desktop queries are stubbed.
privacy_install_case() {
  local mode=$1 home=$BASE/install-$1 got expected
  mkdir -p "$home/templates"
  for key in showNotifications showNotificationSummaries; do
    kwriteconfig6 --file "$home/kscreenlockerrc" --group 'Greeter][LnF][General' --key "$key" false
    kwriteconfig6 --file "$home/kscreenlockerrc" --group Greeter --group LnF --group General --key "$key" true
    kwriteconfig6 --file "$home/templates/kscreenlockerrc" --group Greeter --group LnF --group General --key "$key" true
  done
  kwriteconfig6 --file "$home/plasmafusionrc" --group Config --key Unrelated kept
  kwriteconfig6 --file "$home/templates/plasmafusionrc" --group Config --key Replacement unwanted
  printf 'new configuration\n' >"$home/templates/new.conf"
  if [ "$mode" = completed ]; then
    kwriteconfig6 --file "$home/plasmafusionrc" --group Config --key LockNotificationGroupsVersion 1
  elif [ "$mode" = relative ]; then
    mv "$home/kscreenlockerrc" "$home/lock-settings"
    ln -s lock-settings "$home/kscreenlockerrc"
  elif [ "$mode" = dangling ]; then
    rm "$home/kscreenlockerrc"
    ln -s missing-lock-settings "$home/kscreenlockerrc"
  fi
  got=$(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home" bash -c '
    set -euo pipefail
    . "$1"
    CONFIG=$HOME DRY=0 CHANGES=0 STATE=$HOME/backups-first VARIANT=dark PREV_VERSION=2
    BACKUP_FILES=(kscreenlockerrc plasmafusionrc)
    BACKUP_DIRS=() BACKUP_HOME=()
    say() { :; }
    bus_json() { echo "[]"; }
    bus() { echo "u 1"; }
    run_migration_step() { (die() { exit 1; }; . "$1"); }
    make_backup
    install_config "$CONFIG/templates" >/dev/null
    if [ "$2" = preserve ]; then
      cmp -s "$CONFIG/kscreenlockerrc" "$BACKUP/config/kscreenlockerrc"
      cmp -s "$CONFIG/plasmafusionrc" "$BACKUP/config/plasmafusionrc"
      test -s "$CONFIG/new.conf"
      printf preserved
      exit
    fi
    if [ "$2" = retry ]; then
      kwriteconfig6() { return 1; }
      status=0
      run_migration_step "$3" >/dev/null || status=$?
      test "$status" = 1
      unset -f kwriteconfig6
      # A later invocation takes a fresh backup before installing again.
      STATE=$HOME/backups-second
      make_backup
      install_config "$CONFIG/templates" >/dev/null
    fi
    if [ "$2" = dangling ]; then
      status=0
      run_migration_step "$3" >/dev/null || status=$?
      test -L "$CONFIG/kscreenlockerrc"
      printf "%s|" "$status"
      kreadconfig6 --file "$CONFIG/plasmafusionrc" --group Config --key LockNotificationGroupsVersion --default unset
      exit
    fi
    run_migration_step "$3" >/dev/null
    for key in showNotifications showNotificationSummaries; do
      printf "%s|" "$(kreadconfig6 --file "$CONFIG/kscreenlockerrc" --group Greeter --group LnF --group General --key "$key")"
    done
    printf "%s|" "$(kreadconfig6 --file "$CONFIG/plasmafusionrc" --group Config --key LockNotificationGroupsVersion --default unset)"
    kreadconfig6 --file "$CONFIG/plasmafusionrc" --group Config --key Unrelated --default missing
    ' _ "$LIB" "$mode" "$LOCK_STEP" 2>/dev/null) || got='(error)'
  case $mode in
    preserve) expected=preserved ;;
    retry|relative) expected='false|false|1|kept' ;;
    completed) expected='true|true|1|kept' ;;
    dangling) expected='1|unset' ;;
  esac
  if [ "$got" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "PASS privacy configuration install $mode"
  else
    FAIL=$((FAIL + 1)); echo "FAIL privacy configuration install $mode: $got"
  fi
}
privacy_install_case preserve
privacy_install_case retry
privacy_install_case completed
privacy_install_case relative
privacy_install_case dangling

# Readback must use the effective configuration, including administrator policy.
for policy in mutable immutable; do
  home=$BASE/policy-$policy
  mkdir -p "$home/policy"
  kwriteconfig6 --file "$home/kscreenlockerrc" --group 'Greeter][LnF][General' --key showNotifications false
  policy_key=showNotifications
  [ "$policy" != immutable ] || policy_key='showNotifications[$i]'
  printf '[Greeter][LnF][General]\n%s=true\n' "$policy_key" >"$home/policy/kscreenlockerrc"
  got=$(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home" XDG_CONFIG_DIRS="$home/policy" bash -c '
    set -euo pipefail
    . "$1"
    CONFIG=$HOME DRY=0 CHANGES=0
    status=0
    migrate_lock_notifications >/dev/null || status=$?
    printf "%s|" "$status"
    printf "%s|" "$(kreadconfig6 --file kscreenlockerrc --group Greeter --group LnF --group General --key showNotifications)"
    kreadconfig6 --file "$CONFIG/plasmafusionrc" --group Config --key LockNotificationGroupsVersion --default unset
    ' _ "$LIB" 2>/dev/null) || got='(error)'
  expected='0|false|1'
  [ "$policy" != immutable ] || expected='1|true|unset'
  if [ "$got" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "PASS effective $policy policy is respected"
  else
    FAIL=$((FAIL + 1)); echo "FAIL effective $policy policy: $got"
  fi
done

# An inherited false must become a stored user preference before migration completes.
for default_change in removed enabled ignored-write; do
  home=$BASE/inherited-false-$default_change
  mkdir -p "$home/policy"
  for key in showNotifications showNotificationSummaries; do
    kwriteconfig6 --file "$home/kscreenlockerrc" --group 'Greeter][LnF][General' --key "$key" false
  done
  printf '[Greeter][LnF][General]\nshowNotifications=false\nshowNotificationSummaries=false\n' >"$home/policy/kscreenlockerrc"
  got=$(env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home" XDG_CONFIG_DIRS="$home/policy" bash -c '
    set -euo pipefail
    . "$1"
    CONFIG=$HOME DRY=0 CHANGES=0
    native_write=$(command -v kwriteconfig6)
    if [ "$2" = ignored-write ]; then
      kwriteconfig6() {
        [[ $* != *LockNotificationGroupsVersion* ]] || "$native_write" "$@"
      }
    fi
    status=0
    migrate_lock_notifications >/dev/null || status=$?
    case $2 in
      removed) rm "$CONFIG/policy/kscreenlockerrc" ;;
      enabled) printf "[Greeter][LnF][General]\nshowNotifications=true\nshowNotificationSummaries=true\n" >"$CONFIG/policy/kscreenlockerrc" ;;
    esac
    printf "%s|" "$status"
    for key in showNotifications showNotificationSummaries; do
      printf "%s|" "$(kreadconfig6 --file "$CONFIG/kscreenlockerrc" --group Greeter --group LnF --group General --key "$key" --default unset)"
      printf "%s|" "$(kreadconfig6 --file kscreenlockerrc --group Greeter --group LnF --group General --key "$key" --default unset)"
    done
    kreadconfig6 --file "$CONFIG/plasmafusionrc" --group Config --key LockNotificationGroupsVersion --default unset
    ' _ "$LIB" "$default_change" 2>/dev/null) || got='(error)'
  expected='0|false|false|false|false|1'
  [ "$default_change" != ignored-write ] || expected='1|unset|false|unset|false|unset'
  if [ "$got" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "PASS inherited false survives $default_change"
  else
    FAIL=$((FAIL + 1)); echo "FAIL inherited false with $default_change: $got"
  fi
done

echo "config-keys-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
