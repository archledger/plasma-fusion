#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Run the real device restore against a disposable HOME and stand-in session commands.
#   notifications-restore-unit.sh SCRATCH_PARENT
set -euo pipefail

restore=$(cd "$(dirname "$0")/.." && pwd)/fusion-restore.sh
mkdir -p "${1:?scratch parent required}"
base=$(mktemp -d "$(realpath "$1")/notifications-restore.XXXXXX")
mkdir "$base/bin"
for t in kquitapp6 setsid sleep fc-cache dbus-send kreadconfig6; do
  ln -s /usr/bin/true "$base/bin/$t"
done
cat >"$base/bin/busctl" <<'EOF'
#!/bin/bash
case "$*" in
  *'GetConnectionUnixProcessID s org.kde.plasmashell') echo 'u 9999999' ;;
  *'NameHasOwner s org.kde.plasmashell') echo 'b true' ;;
  *shortcutNames) echo 'as 0' ;;
esac
EOF
cat >"$base/bin/systemctl" <<'EOF'
#!/bin/bash
case "$*" in
  '--user show -p MainPID --value plasma-plasmashell.service')
    if [[ $TEST_MANAGER == owned ]]; then echo 9999999; else echo 9999998; fi ;;
  '--user show-environment')
    if [[ $TEST_MANAGER == owned ]]; then
      echo DBUS_SESSION_BUS_ADDRESS=unix:path=/fixture-session
    else
      echo DBUS_SESSION_BUS_ADDRESS=unix:path=/foreign-session
    fi ;;
  '--user start plasma-plasmashell.service')
    test ! -e "$XDG_STATE_HOME/plasma-fusion/notifications" || exit 9
    printf 'start\n' >>"$TRACE" ;;
  '--user stop plasma-plasmashell.service') printf 'stop shell\n' >>"$TRACE" ;;
  '--user daemon-reload') printf 'reload\n' >>"$TRACE" ;;
  *'stop '*plasma-fusion-notifications*) printf 'stop notification units\n' >>"$TRACE" ;;
  *) printf 'unexpected manager command %s\n' "$*" >&2; exit 9 ;;
esac
EOF
chmod +x "$base/bin/busctl" "$base/bin/systemctl"

paths=(
  systemd/user/plasma-plasmashell.service.d/20-plasma-fusion-notifications.conf
  systemd/user/plasma-fusion-notifications-notify.service
  systemd/user/plasma-fusion-notifications-watch@.service
  systemd/user/xdg-desktop-autostart.target.wants/plasma-fusion-notifications-notify.service
)

for mode in dry older current foreign; do
  home=$base/$mode
  cfg="$home/XDG config"
  state="$home/state/plasma-fusion/notifications"
  backup="$home/backup"
  mkdir -p "$cfg" "$state" "$backup/config"
  printf 'stale\n' >"$state/qml-failed"
  printf 'lookandfeel=org.kde.breeze.desktop\n' >"$backup/info"
  printf '{"data":[]}\n' >"$backup/desktops.json"
  : >"$backup/manifest"
  touch "$home/trace"
  for path in "${paths[@]}"; do
    mkdir -p "$cfg/${path%/*}"
    printf 'new\n' >"$cfg/$path"
    if [[ $mode == current ]]; then
      mkdir -p "$backup/config/${path%/*}"
      if [[ $path == *wants/* ]]; then
        ln -s ../old-notify.service "$backup/config/$path"
      else
        printf 'old\n' >"$backup/config/$path"
      fi
      printf 'present %s\n' "$path" >>"$backup/manifest"
    fi
  done
  printf 'unrelated\n' >"$cfg/systemd/user/other.service"
  args=("$backup")
  [[ $mode != dry ]] || args+=(--dry-run)
  manager=owned
  [[ $mode != foreign ]] || manager=foreign
  env -i HOME="$home" XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$home/state" \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/fixture-session PATH="$base/bin:/usr/bin:/bin" \
    TEST_MANAGER="$manager" TRACE="$home/trace" bash "$restore" "${args[@]}" >"$home/log" 2>&1

  if [[ $mode == dry ]]; then
    test -f "$state/qml-failed"
    test ! -s "$home/trace"
    for path in "${paths[@]}"; do test "$(cat "$cfg/$path")" = new; done
  else
    if [[ -e $state ]]; then echo "FAIL $mode: stale notification state survived"; exit 1; fi
    for path in "${paths[@]}"; do
      if [[ $mode == current ]]; then
        if [[ $path == *wants/* ]]; then
          test "$(readlink "$cfg/$path")" = ../old-notify.service
        else
          test "$(cat "$cfg/$path")" = old
        fi
      else
        test ! -e "$cfg/$path" && test ! -L "$cfg/$path"
      fi
    done
    if [[ $mode == foreign ]]; then
      test ! -s "$home/trace"
    else
      test "$(cat "$home/trace")" = $'stop shell\nstop notification units\nreload\nstart'
    fi
  fi
  test "$(cat "$cfg/systemd/user/other.service")" = unrelated
  printf 'PASS device restore %s\n' "$mode"
done
