#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Render the real drop-in, then execute its launch command with stand-ins.
#   notifications-setup-unit.sh SCRATCH_PARENT
set -euo pipefail

script=$(cd "$(dirname "$0")/.." && pwd)/fusion-config.sh
mkdir -p "${1:?scratch parent required}"
base=$(mktemp -d "$(realpath "$1")/notification-setup.XXXXXX")
for function in notifications_unit_arg notifications_shell_dropin notifications_vendor_supported \
    notifications_service_unit notifications_setup install_text session_manager; do
  sed -n "/^$function() {/,/^}/p" "$script" >>"$base/functions"
  if ! grep -q "^$function() {" "$base/functions"; then
    printf 'FAIL missing setup function: %s\n' "$function" >&2
    exit 1
  fi
done

# shellcheck source=/dev/null
source "$base/functions"

HOME="$base/home with spaces %"
CONFIG="$HOME/XDG config %"
DATA="$HOME/XDG data %"
STATE="$HOME/XDG state %"
NOTIFICATIONS_VENDOR=$base/vendor.service
NOTIFICATIONS_ROOT="$base/private qt %"
NOTIFICATIONS_SELECTOR="$base/selector with spaces %"
NOTIFICATIONS_SHELL="$base/record-shell"
NOTIFICATIONS_DROPIN_REL=systemd/user/plasma-plasmashell.service.d/20-plasma-fusion-notifications.conf
NOTIFICATIONS_NOTIFY=$base/bin-notify
NOTIFICATIONS_WATCH=$base/bin-watch
NOTIFICATIONS_NOTIFY_NAME=plasma-fusion-notifications-notify.service
NOTIFICATIONS_NOTIFY_REL=systemd/user/$NOTIFICATIONS_NOTIFY_NAME
NOTIFICATIONS_WATCH_REL=systemd/user/plasma-fusion-notifications-watch@.service
NOTIFICATIONS_WANTS_REL=systemd/user/xdg-desktop-autostart.target.wants/$NOTIFICATIONS_NOTIFY_NAME
NOTIFICATIONS_FILES=("$NOTIFICATIONS_DROPIN_REL" "$NOTIFICATIONS_NOTIFY_REL" "$NOTIFICATIONS_WATCH_REL"
  "$NOTIFICATIONS_WANTS_REL")
dropin=$CONFIG/$NOTIFICATIONS_DROPIN_REL
export CHANGES=0 DRY=0
export HOME XDG_CONFIG_HOME="$CONFIG" XDG_DATA_HOME="$DATA" XDG_STATE_HOME="$STATE"
export STANDIN_ROOT="$NOTIFICATIONS_ROOT" RECORD_PID="$base/ran" SELECT_MODE=match
export DBUS_SESSION_BUS_ADDRESS=unix:path=/private-probe
manager_bus=$DBUS_SESSION_BUS_ADDRESS
note() { printf '%s\n' "$*" >>"$base/setup.log"; }
busctl() {
  [[ $* == '--user --timeout=1s --json=short get-property org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager UnitPath' ]]
  python3 -c 'import json,sys; print(json.dumps({"type":"as","data":sys.argv[1:]}))' \
    "$CONFIG/systemd/user" "$base"
}
systemctl() {
  case "$*" in
    '--user show-environment') printf 'DBUS_SESSION_BUS_ADDRESS=%s\n' "$manager_bus" ;;
    '--user show -p FragmentPath --value plasma-plasmashell.service') printf '%s\n' "$NOTIFICATIONS_VENDOR" ;;
    '--user show -p DropInPaths --value plasma-plasmashell.service') [[ ! -f $dropin ]] || printf '%s\n' "$dropin" ;;
    '--user daemon-reload') printf 'reload\n' >>"$base/manager.log" ;;
    *) printf 'unexpected systemctl: %s\n' "$*" >&2; exit 1 ;;
  esac
}

cat >"$NOTIFICATIONS_VENDOR" <<'EOF'
[Service]
ExecStart=/usr/bin/plasmashell --no-respawn
Type=dbus
BusName=org.kde.plasmashell
Restart=on-failure
TimeoutSec=40sec
EOF
cat >"$NOTIFICATIONS_SELECTOR" <<'EOF'
#!/bin/bash
case "$SELECT_MODE" in
  match) printf '%s\n' "$STANDIN_ROOT" ;;
  fail) printf '%s\n' "$STANDIN_ROOT"; exit 1 ;;
  bad) printf '%s\nunexpected extra output\n' "$STANDIN_ROOT" ;;
  blank-line) printf '%s\n\n' "$STANDIN_ROOT" ;;
  nul) printf '%s\0\n' "$STANDIN_ROOT" ;;
  no-newline) printf '%s' "$STANDIN_ROOT" ;;
  dot-then-fail) printf '%s\n.' "$STANDIN_ROOT"; exit 1 ;;
  line-then-hang) printf '%s\n' "$STANDIN_ROOT"; trap '' TERM; sleep 30 ;;
  hang) trap '' TERM; sleep 30 ;;
  *) exit 1 ;;
esac
EOF
cat >"$NOTIFICATIONS_SHELL" <<'EOF'
#!/bin/bash
# The children this process has when it starts were left by the launch that exec'd it; read with
# a builtin, so that the shell adds none of its own.
children=
read -r children <"/proc/$$/task/$$/children" || :
printf '%s\n' "$children" >"$RECORD_PID.children"
printf '%s\n%s\n' "$*" "${QT_PLUGIN_PATH-<unset>}" >"$RECORD_PID"
EOF
cat >"$NOTIFICATIONS_WATCH" <<'EOF'
#!/bin/bash
printf '%s|%s|%s\n' "$*" "${SERVICE_RESULT-<unset>}" "${INVOCATION_ID-<unset>}" >>"$WATCH_LOG"
EOF
chmod +x "$NOTIFICATIONS_SELECTOR" "$NOTIFICATIONS_SHELL" "$NOTIFICATIONS_WATCH"
ln -s /usr/bin/true "$NOTIFICATIONS_NOTIFY"
export WATCH_LOG=$base/watch.log

: >"$base/manager.log"
DRY=1
notifications_setup
for rel in "${NOTIFICATIONS_FILES[@]}"; do test ! -e "$CONFIG/$rel"; done
test ! -s "$base/manager.log"
test "$CHANGES" = 4
DRY=0 CHANGES=0
notifications_setup
for rel in "${NOTIFICATIONS_FILES[@]}"; do test -f "$CONFIG/$rel"; done
test "$(readlink "$CONFIG/$NOTIFICATIONS_WANTS_REL")" = "../$NOTIFICATIONS_NOTIFY_NAME"
test "$(wc -l <"$base/manager.log")" = 1
notifications_setup
test "$(wc -l <"$base/manager.log")" = 1
test "$CHANGES" = 4

launch() {
  local want=$1
  shift
  # Each case checks its own launch, also where a caller's condition turns errexit off.
  rm -f -- "$RECORD_PID" "$RECORD_PID.children"
  env "$@" python3 - "$dropin" <<'PY' || return 1
import os
import shlex
import sys
from pathlib import Path

lines = Path(sys.argv[1]).read_text().splitlines()
assert "ExecStart=" in lines
line, = (line for line in lines if line.startswith("ExecStart=:"))
cmd = shlex.split(line.removeprefix("ExecStart=:").replace("%%", "%"))
os.execv(cmd[0], cmd)
PY
  test "$(cat "$RECORD_PID")" = "$(printf '%s\n%s\n' --no-respawn "$want")"
}
# The launch leaves none of its own processes, running or unreaped, to the shell it execs (#231).
no_children() {
  local left
  left=$(<"$RECORD_PID.children")
  if [[ -n $left ]]; then
    printf 'FAIL the launch %s left children to the shell: %s\n' "$1" "$left" >&2
    exit 1
  fi
}

export QT_PLUGIN_PATH=/some/other/plugins:/second
launch "$NOTIFICATIONS_ROOT:$QT_PLUGIN_PATH"
no_children 'that admits the copy'
launch "$NOTIFICATIONS_ROOT:$QT_PLUGIN_PATH" \
  "QT_PLUGIN_PATH=$NOTIFICATIONS_ROOT:$QT_PLUGIN_PATH:$NOTIFICATIONS_ROOT"
launch "$QT_PLUGIN_PATH" SELECT_MODE=fail
launch "$QT_PLUGIN_PATH" SELECT_MODE=bad
# Only the selector's exact line admits the copy: output that a command substitution would
# forgive (a blank line after it, a NUL byte, no newline at its end) starts the shell stock, and
# so does a selector that fails or is stopped after it has written its output.
for mode in blank-line nul no-newline dot-then-fail line-then-hang; do
  if ! launch "$QT_PLUGIN_PATH" SELECT_MODE="$mode"; then
    printf 'FAIL the launch admitted the copy for the selector output %s\n' "$mode" >&2
    exit 1
  fi
done
start=${EPOCHREALTIME/.}
launch "$QT_PLUGIN_PATH" SELECT_MODE=hang
end=${EPOCHREALTIME/.}
test "$(((10#$end - 10#$start) / 1000))" -lt 5500
mv -- "$NOTIFICATIONS_SELECTOR" "$base/selector.missing"
launch "$QT_PLUGIN_PATH"
mv -- "$base/selector.missing" "$NOTIFICATIONS_SELECTOR"

# After the shell's process ends, the unit hands its result to the watcher, whose failure must
# not fail the unit.
env SERVICE_RESULT=core-dump INVOCATION_ID=0123456789abcdef0123456789abcdef python3 - "$dropin" <<'PY'
import os
import shlex
import sys
from pathlib import Path

line, = (line for line in Path(sys.argv[1]).read_text().splitlines() if line.startswith("ExecStopPost="))
command = line.removeprefix("ExecStopPost=")
assert command.startswith("-"), line
cmd = shlex.split(command.removeprefix("-").replace("%%", "%"))
os.execv(cmd[0], cmd)
PY
test "$(cat "$WATCH_LOG")" = '--stopped|core-dump|0123456789abcdef0123456789abcdef'

mkdir -p "$DATA/plasma-fusion/notifications/plugins/plasma/applets"
legacy=$DATA/plasma-fusion/notifications/plugins/plasma/applets
ln -s -- "$NOTIFICATIONS_SHELL" "$legacy/org.kde.plasma.notifications.so"
chmod 0555 "$legacy"
launch "$QT_PLUGIN_PATH" SELECT_MODE=fail
"$NOTIFICATIONS_SHELL" --no-respawn
test "$(sed -n '2p' "$RECORD_PID")" = "$QT_PLUGIN_PATH"
test -L "$legacy/org.kde.plasma.notifications.so"
chmod u+w "$legacy"

printf 'ExecStart=/usr/bin/plasmashell --different-argv\n' >>"$NOTIFICATIONS_VENDOR"
launch "$QT_PLUGIN_PATH"
no_children 'for a vendor unit changed since setup'
notifications_setup
for rel in "${NOTIFICATIONS_FILES[@]}"; do test ! -e "$CONFIG/$rel" && test ! -L "$CONFIG/$rel"; done
test "$(wc -l <"$base/manager.log")" = 2

sed -i '$d' "$NOTIFICATIONS_VENDOR"
foreign_dropin=${dropin%/*}/05-vendor-start.conf
printf '[Service]\nExecStart=\nExecStart=/usr/bin/plasmashell --different-argv\n' >"$foreign_dropin"
notifications_setup
if [[ -e $dropin ]]; then
  echo 'FAIL setup overwrote a conflicting on-disk drop-in not yet loaded by the manager'
  exit 1
fi
manager_bus=unix:path=/other-session
notifications_setup
test ! -e "$dropin"
rm -- "$foreign_dropin"
notifications_setup
test ! -e "$dropin"
test "$(wc -l <"$base/manager.log")" = 2
test ! -e "$CONFIG/plasma-workspace/env/plasma-fusion-notifications.sh"

# Without its recovery unit the copy must not be admitted: a unit that cannot be written keeps
# the launch on stock, even where the drop-in itself could be written.
manager_bus=$DBUS_SESSION_BUS_ADDRESS
watch_unit=$CONFIG/$NOTIFICATIONS_WATCH_REL
rm -f -- "$watch_unit"
mkdir -- "$watch_unit.tmp"
notifications_setup
test ! -e "$dropin"
rmdir -- "$watch_unit.tmp"
notifications_setup
test -f "$dropin"
test -f "$watch_unit"
printf '# edited\n' >>"$watch_unit"
mkdir -- "$watch_unit.tmp"
notifications_setup
test ! -e "$dropin"
rmdir -- "$watch_unit.tmp"
notifications_setup
test -f "$dropin"

# Nor without its notice service enabled: a file where the wants directory belongs.
wants_dir=$CONFIG/${NOTIFICATIONS_WANTS_REL%/*}
rm -f -- "$CONFIG/$NOTIFICATIONS_WANTS_REL"
rmdir -- "$wants_dir"
: >"$wants_dir"
notifications_setup
test ! -e "$dropin"
rm -f -- "$wants_dir"
notifications_setup
test -f "$dropin"
test -L "$CONFIG/$NOTIFICATIONS_WANTS_REL"

# A drop-in that cannot be rewritten is removed rather than left to admit the copy as before.
printf '# an older drop-in\n' >>"$dropin"
mkdir -- "$dropin.tmp"
notifications_setup
test ! -e "$dropin"
rmdir -- "$dropin.tmp"
printf 'PASS per-launch environment, exact selector output, stop step, fallback, foreign unit, dry-run, manager fencing and unit write failures\n'
