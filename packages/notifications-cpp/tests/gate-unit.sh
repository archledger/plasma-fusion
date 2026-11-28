#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Offline selector behavior; no real RPM database, desktop, or user manager.
#   gate-unit.sh SCRATCH_PARENT CONFIGURED_SELECTOR EXPECTED_PLUGIN_ROOT
set -euo pipefail

root=$(cd "$(dirname "$0")/../../.." && pwd)
mkdir -p "${1:?scratch parent required}"
base=$(mktemp -d "$(realpath "$1")/selector.XXXXXX")
selector=$(realpath -m "${2:?configured selector required}")
plugin_root=${3:?expected output root required}
theme_engine=$root/tools/device/gate/plasma-fusion-gate.sh

if [ ! -x "$selector" ]; then
  echo "FAIL: selector absent: $selector" >&2
  exit 1
fi

cat >"$base/rpm" <<'EOF'
#!/bin/bash
set -eu
[[ $# == 4 && $1 == -q && $2 == --qf && $3 == '%{NAME}=%{VERSION}\n' && $4 == plasma-workspace ]]
printf 'q\n' >>"$CASE/rpm.calls"
cat "$CASE/versions"
EOF
cat >"$base/check" <<'EOF'
#!/bin/bash
set -eu
[[ $# == 1 && $1 == "$PF_NOTIFICATIONS_PLUGIN" ]]
printf 'check\n' >>"$CASE/check.calls"
case $(cat "$CASE/check-mode") in
  pass) ;;
  fail) printf '%s\n' "$EXPECTED_ROOT"; exit 1 ;;
  kill) kill -KILL $$ ;;
  hang) trap '' TERM; sleep 20 ;;
  move-db) printf 'transaction\n' >>"$CASE/root/usr/lib/sysimage/rpm/rpmdb.sqlite-wal" ;;
  move-plugin) printf 'replaced\n' >>"$1" ;;
  remove-plugin) rm -- "$1" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$base/rpm" "$base/check"

new_case() {
  case_dir=$base/$1
  home=$case_dir/home
  db=$case_dir/root/usr/lib/sysimage/rpm/rpmdb.sqlite
  plugin=$case_dir/org.kde.plasma.notifications.so
  record=$case_dir/record
  state=$case_dir/state/plasma-fusion/notifications
  mkdir -p "$home/.config/kdedefaults" "$case_dir/etc" "${db%/*}"
  printf 'test db\n' >"$db"
  printf 'test plugin\n' >"$plugin"
  write_record 6.8.3 6.8.3
  printf 'plasma-workspace=6.8.3\n' >"$case_dir/versions"
  printf 'pass\n' >"$case_dir/check-mode"
  set_theme org.plasmafusion.dark.desktop
  : >"$case_dir/rpm.calls"
  : >"$case_dir/check.calls"
}

write_record() {
  printf 'source-plasma-workspace=%s\nplasma-workspace=%s\nqt=6.11.2\n' "$1" "$2" >"$record"
}

set_theme() {
  printf '[KDE]\nLookAndFeelPackage=%s\n' "$1" >"$home/.config/kdeglobals"
}

run_selector() {
  env -i HOME="$home" PATH=/usr/bin:/bin XDG_CONFIG_DIRS="$case_dir/etc" \
    XDG_STATE_HOME="$case_dir/state" PF_GATE_ROOT="$case_dir/root" PF_GATE_RPM="$base/rpm" \
    PF_NOTIFICATIONS_PLUGIN="$plugin" PF_NOTIFICATIONS_RECORD="$record" \
    PF_NOTIFICATIONS_CHECK="$base/check" PF_NOTIFICATIONS_THEME_ENGINE="$theme_engine" \
    CASE="$case_dir" EXPECTED_ROOT="$plugin_root" "$@" "$selector"
}

admit() {
  local output
  output=$(run_selector "$@") || { echo "FAIL ${case_dir##*/}: rejected matching copy"; exit 1; }
  if [ "$output" != "$plugin_root" ]; then
    printf 'FAIL %s: wrong output <%s>\n' "${case_dir##*/}" "$output"
    exit 1
  fi
}

stock() {
  local output
  if output=$(run_selector "$@") || [ -n "$output" ]; then
    printf 'FAIL %s: admitted or emitted <%s>\n' "${case_dir##*/}" "$output"
    exit 1
  fi
}

calls() {
  local actual
  actual=$(wc -l <"$case_dir/$1.calls")
  if [ "$actual" != "$2" ]; then
    printf 'FAIL %s: %s calls, expected %s, got %s\n' "${case_dir##*/}" "$1" "$2" "$actual"
    exit 1
  fi
}

new_case cache-and-rebuild
admit
admit
calls rpm 1
calls check 1
printf 'rpm rebuild of the same upstream version\n' >>"$db"
admit
calls rpm 2
calls check 2
mv -- "$plugin" "$plugin.old"
cp -- "$plugin.old" "$plugin"
admit
calls check 3
printf 'bad cache\n' >"$state/pass"
admit
calls check 4
printf 'PASS cache, RPM rebuild, replaced inode, malformed cache\n'

for fixture in source-version build-version unknown-rpm duplicate-rpm malformed-record missing-key; do
  new_case "$fixture"
  case $fixture in
    source-version) write_record 6.8.2 6.8.3 ;;
    build-version) write_record 6.8.3 6.8.2 ;;
    unknown-rpm) : >"$case_dir/versions" ;;
    duplicate-rpm) printf 'plasma-workspace=6.8.4\n' >>"$case_dir/versions" ;;
    malformed-record) printf 'plasma-workspace=$(exit 0)\n' >>"$record" ;;
    missing-key) printf 'plasma-workspace=6.8.3\n' >"$record" ;;
  esac
  stock
  calls check 0
done
printf 'PASS mismatch, unknown RPM and malformed records reject before loading\n'

new_case fake-version
admit
stock PF_GATE_FAKE_VERSIONS=plasma-workspace=6.8.4
admit
calls rpm 1
calls check 1
new_case fake-cannot-seed
printf 'plasma-workspace=6.8.4\n' >"$case_dir/versions"
admit PF_GATE_FAKE_VERSIONS=plasma-workspace=6.8.3
stock
calls rpm 1
calls check 1
printf 'PASS fake versions do not contaminate persistent passes\n'

for fixture in move-db move-plugin remove-plugin fail kill hang; do
  new_case "$fixture"
  printf '%s\n' "$fixture" >"$case_dir/check-mode"
  start=${EPOCHREALTIME/.}
  stock
  end=${EPOCHREALTIME/.}
  if [ "$fixture" = hang ]; then
    elapsed_ms=$(((10#$end - 10#$start) / 1000))
    test "$elapsed_ms" -lt 5000
    printf 'Timed out with kill escalation after %s ms\n' "$elapsed_ms"
  fi
  test ! -e "$state/pass"
  printf 'pass\n' >"$case_dir/check-mode"
  printf 'test plugin\n' >"$plugin"
  admit
  calls check 2
done
printf 'PASS stale identity, failed/interrupted checks, retry\n'

for fixture in missing-plugin missing-record breeze deletion inherited automatic; do
  new_case "$fixture"
  case $fixture in
    missing-plugin) rm -- "$plugin" ;;
    missing-record) rm -- "$record" ;;
    breeze) set_theme org.kde.breeze.desktop ;;
    deletion)
      mv "$home/.config/kdeglobals" "$home/.config/kdedefaults/kdeglobals"
      printf '[KDE]\nLookAndFeelPackage[$d]\n' >"$home/.config/kdeglobals"
      ;;
    inherited) mv "$home/.config/kdeglobals" "$home/.config/kdedefaults/kdeglobals" ;;
    automatic)
      set_theme org.kde.breeze.desktop
      printf 'AutomaticLookAndFeel=true\nDefaultDarkLookAndFeel=org.plasmafusion.dark.desktop\n' \
        >>"$home/.config/kdeglobals"
      ;;
  esac
  case $fixture in
    inherited | automatic) admit ;;
    *) stock; calls rpm 0; calls check 0 ;;
  esac
  test ! -e "$state/notify"
done
printf 'PASS installed payload and effective theme cases\n'

new_case timing
for ((i = 0; i < 21; i++)); do
  printf 'transaction %s\n' "$i" >>"$db"
  t=${EPOCHREALTIME/.}
  admit
  end=${EPOCHREALTIME/.}
  printf '%s\n' "$(((10#$end - 10#$t) / 1000))" >>"$case_dir/cold-ms"
  t=${EPOCHREALTIME/.}
  admit
  end=${EPOCHREALTIME/.}
  printf '%s\n' "$(((10#$end - 10#$t) / 1000))" >>"$case_dir/warm-ms"
done
calls rpm 21
calls check 21
for mode in cold warm; do
  printf '%s ms: ' "$mode"
  sort -n "$case_dir/$mode-ms" | awk 'NR == 11 {printf "median %s; ", $1} END {print "max " $1}'
done
printf 'PASS 21 warm starts used neither RPM nor the load checker; raw data at %s\n' "$case_dir"
