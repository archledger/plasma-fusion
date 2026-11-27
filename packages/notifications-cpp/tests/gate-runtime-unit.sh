#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test fallback notice transitions independently of the desktop or user manager.
#   gate-runtime-unit.sh SCRATCH_PARENT CONFIGURED_GATE_DIR
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
mkdir -p "${1:?scratch parent required}"
base=$(mktemp -d "$(realpath "$1")/notification-runtime.XXXXXX")
gate=$(realpath -m "${2:?configured gate directory required}")
select=$gate/plasma-fusion-notifications-select
notify=$gate/plasma-fusion-notifications-notify
mkdir -p "$base/bin" "$base/home/.config" "$base/state/plasma-fusion/gate" \
  "$base/sys/usr/lib/sysimage/rpm"
: >"$base/sys/usr/lib/sysimage/rpm/rpmdb.sqlite"
: >"$base/org.kde.plasma.notifications.so"
printf 'source-plasma-workspace=6.8.3\nplasma-workspace=6.8.3\nqt=6.11.2\n' >"$base/record"
state=$base/state/plasma-fusion/notifications
login_notice=$base/state/plasma-fusion/gate/notify
printf 'login check notice\n' >"$login_notice"

cat >"$base/bin/check" <<'EOF'
#!/bin/bash
[[ ${FAIL_CHECK:-0} == 0 ]]
EOF
cat >"$base/bin/systemctl" <<'EOF'
#!/bin/bash
[[ $* == '--user start --no-block plasma-fusion-notifications-notify.service' ]] || exit 9
printf '%s\n' "$*" >>"$FIXTURE/requests"
EOF
cat >"$base/bin/gdbus" <<'EOF'
#!/bin/bash
case $1 in
  wait) [[ ${FAIL_WAIT:-0} == 0 ]] ;;
  call)
    [[ " $* " == *' --method org.freedesktop.Notifications.Notify '* ]] || exit 9
    [[ ${FAIL_DELIVERY:-0} == 0 ]] || exit 1
    printf '%s\n' "$*" >>"$FIXTURE/delivered"
    ;;
  *) exit 9 ;;
esac
EOF
chmod +x "$base/bin/"*

as_user() {
  env -i HOME="$base/home" PATH="$base/bin:/usr/bin:/bin" XDG_STATE_HOME="$base/state" \
    XDG_CONFIG_DIRS="$base/xdg" PF_GATE_ROOT="$base/sys" PF_NOTIFICATIONS_RECORD="$base/record" \
    PF_NOTIFICATIONS_PLUGIN="$base/org.kde.plasma.notifications.so" \
    PF_NOTIFICATIONS_CHECK="$base/bin/check" \
    PF_NOTIFICATIONS_THEME_ENGINE="$root/tools/device/gate/plasma-fusion-gate.sh" \
    INVOCATION_ID=4c26812a3ce04762bd12418e22166da9 FIXTURE="$base" "$@"
}

theme() {
  printf '[KDE]\nLookAndFeelPackage=%s\n' "$1" >"$base/home/.config/kdeglobals"
}

admit() {
  as_user PF_GATE_FAKE_VERSIONS=plasma-workspace=6.8.3 "$select" >/dev/null
}

stock() {
  local output
  if output=$(as_user "$@") || [ -n "$output" ]; then
    echo 'FAIL expected stock without a path' >&2
    exit 1
  fi
}

theme org.plasmafusion.dark.desktop
admit
stock PF_GATE_FAKE_VERSIONS=plasma-workspace=6.8.4 "$select"
if [ ! -f "$state/notify" ]; then echo 'FAIL version fallback did not queue its notice'; exit 1; fi
test "$(wc -l <"$base/requests")" = 1
grep -Fxq 'Plasma changed under Plasma Fusion, or the notification applet could not be loaded. The banner keyboard shortcut is off until Plasma Fusion is updated.' "$state/notify"
stock PF_GATE_FAKE_VERSIONS=plasma-workspace=6.8.4 "$select"
test "$(wc -l <"$base/requests")" = 1
as_user FAIL_WAIT=1 "$notify" || true
test -f "$state/notify"
test ! -e "$base/delivered"
as_user FAIL_DELIVERY=1 "$notify" || true
test -f "$state/notify"
test ! -e "$base/delivered"
as_user "$notify"
as_user "$notify"
test ! -e "$state/notify"
test "$(wc -l <"$base/delivered")" = 1
test "$(cat "$login_notice")" = 'login check notice'

admit
stock PF_GATE_FAKE_VERSIONS=plasma-workspace=6.8.3 FAIL_CHECK=1 "$select"
test -f "$state/notify"
test "$(wc -l <"$base/requests")" = 2
as_user "$notify"
admit
theme org.kde.breeze.desktop
stock "$select"
test ! -e "$state/notify"
theme org.plasmafusion.dark.desktop
admit
mv "$base/record" "$base/record.missing"
stock "$select"
test ! -e "$state/notify"
test "$(wc -l <"$base/requests")" = 2
printf 'PASS fallback notice transitions, definite delivery, and independent login queue\n'
