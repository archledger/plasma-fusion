#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of the profile safety net (backup-profile.sh, restore-profile.sh) for the window
# placement memory: a snapshot carries ~/.config/plasmafusion-placementrc and puts it back, and a
# restore of a snapshot taken before Plasma Fusion removes the memory file and the KWin script
# package; the running script is unloaded first, so it cannot write its newer map over the restored
# file. The dynamic workspaces' script package goes the same way, and that script is unloaded first
# too (KWin writes its desktops to kwinrc at every change the script makes). Runs in throw-away HOME trees with `env -i` (no session bus, no display); the restore runs
# with --dry-run only, so nothing is stopped, started or written outside BASE. Test tooling only,
# not installed.
#
#   profile-unit.sh BASE
#
# BASE must be a scratch directory on disk (not /tmp); it is emptied first.
set -euo pipefail
BASE=${1:?scratch directory}
BASE=$(realpath -m -- "$BASE")
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
BACKUP=$HERE/../backup-profile.sh
RESTORE=$HERE/../restore-profile.sh
rm -rf "${BASE:?}"
mkdir -p "$BASE/run" "$BASE/tmp"
chmod 700 "$BASE/run"

passed=0
failed=0
check() { # LABEL COMMAND...
  local label=$1
  shift
  if "$@"; then
    echo "PASS $label"
    passed=$((passed + 1))
  else
    echo "FAIL $label"
    failed=$((failed + 1))
  fi
}

# A command in the throw-away HOME: the caller's environment, session bus and display left out.
in_home() { # HOME COMMAND...
  local home=$1
  shift
  env -i HOME="$home" PATH="$PATH" LANG=C.UTF-8 TMPDIR="$BASE/tmp" XDG_RUNTIME_DIR="$BASE/run" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$BASE/run/no-bus" "$@"
}

memory='{"v":1,"apps":{"org.kde.kwrite":{"x":137,"y":93,"width":640,"height":420}}}'

# ---- a: a snapshot taken with the memory carries it, and a restore puts it back
A=$BASE/home-a
mkdir -p "$A/.config"
printf '[Plugins]\nplasmafusion-placementEnabled=true\nplasmafusion-workspacesEnabled=true\n' >"$A/.config/kwinrc"
printf '[Windows]\nwindows=%s\n' "$memory" >"$A/.config/plasmafusion-placementrc"
snap_a=$(in_home "$A" bash "$BACKUP" "$BASE/snap-a" 2>"$BASE/backup-a.err")
check "a: the snapshot was written" test -s "$snap_a"
tar -xzOf "$snap_a" paths.txt >"$BASE/paths-a.txt"
check "a: the snapshot lists the window memory" grep -qx '.config/plasmafusion-placementrc' "$BASE/paths-a.txt"
check "a: the snapshot holds the memory as it was" \
  bash -c 'tar -xzOf "$1" .config/plasmafusion-placementrc | cmp -s - "$2"' _ "$snap_a" "$A/.config/plasmafusion-placementrc"
printf '[Windows]\nwindows={"v":1,"apps":{}}\n' >"$A/.config/plasmafusion-placementrc"
in_home "$A" bash "$RESTORE" "$snap_a" --dry-run >"$BASE/restore-a.txt" 2>&1
check "a: the restore unloads the running script first" grep -qx 'would: unload the KWin script plasmafusion-placement' "$BASE/restore-a.txt"
check "a: ...and the dynamic workspaces" grep -qx 'would: unload the KWin script plasmafusion-workspaces' "$BASE/restore-a.txt"
# The snapshot enables the dynamic workspaces: the closing reconfigure must not load them in this
# session, so the key is off while KWin reads the restored kwinrc, and the snapshot's file comes
# back after it (the last kwinrc copy of the restore).
check "a: the dynamic workspaces are held off for the reconfigure" \
  grep -qx "would: kwriteconfig6 --file $A/.config/kwinrc --group Plugins --key plasmafusion-workspacesEnabled false" "$BASE/restore-a.txt"
check "a: the snapshot's kwinrc is put back after the hold" bash -c '
  hold=$(grep -n "plasmafusion-workspacesEnabled false" "$1" | cut -d: -f1)
  back=$(grep -n "^would: cp -a .*/\.config/kwinrc \.config/kwinrc$" "$1" | tail -n 1 | cut -d: -f1)
  [ -n "$hold" ] && [ -n "$back" ] && [ "$back" -gt "$hold" ]' _ "$BASE/restore-a.txt"
check "a: the restore puts the memory back" grep -qE '^would: cp -a .*/\.config/plasmafusion-placementrc \.config/plasmafusion-placementrc$' "$BASE/restore-a.txt"
check "a: the restore does not remove the memory it puts back" \
  bash -c '! grep -qx "would: rm -rf -- .config/plasmafusion-placementrc" "$1"' _ "$BASE/restore-a.txt"

# ---- b: a snapshot taken before Plasma Fusion: the memory and the script package go
B=$BASE/home-b
mkdir -p "$B/.config"
printf '[Plugins]\n' >"$B/.config/kwinrc"
snap_b=$(in_home "$B" bash "$BACKUP" "$BASE/snap-b" 2>"$BASE/backup-b.err")
check "b: the snapshot was written" test -s "$snap_b"
mkdir -p "$B/.local/share/kwin/scripts/plasmafusion-placement/contents/ui"
printf '{}\n' >"$B/.local/share/kwin/scripts/plasmafusion-placement/metadata.json"
mkdir -p "$B/.local/share/kwin/scripts/plasmafusion-workspaces/contents/ui"
printf '{}\n' >"$B/.local/share/kwin/scripts/plasmafusion-workspaces/metadata.json"
printf '[Windows]\nwindows=%s\n' "$memory" >"$B/.config/plasmafusion-placementrc"
in_home "$B" bash "$RESTORE" "$snap_b" --dry-run >"$BASE/restore-b.txt" 2>&1
check "b: the restore unloads the running script first" grep -qx 'would: unload the KWin script plasmafusion-placement' "$BASE/restore-b.txt"
check "b: the memory file is removed" grep -qx 'would: rm -rf -- .config/plasmafusion-placementrc' "$BASE/restore-b.txt"
check "b: the script package is removed" grep -qx 'would: rm -rf -- .local/share/kwin/scripts/plasmafusion-placement' "$BASE/restore-b.txt"
check "b: the dynamic workspaces are unloaded first" grep -qx 'would: unload the KWin script plasmafusion-workspaces' "$BASE/restore-b.txt"
check "b: the dynamic workspaces package is removed" grep -qx 'would: rm -rf -- .local/share/kwin/scripts/plasmafusion-workspaces' "$BASE/restore-b.txt"
check "b: a snapshot without them holds nothing" bash -c '! grep -q "plasmafusion-workspacesEnabled" "$1"' _ "$BASE/restore-b.txt"
check "b: the dry run changed nothing" test -s "$B/.config/plasmafusion-placementrc"

echo "== $passed passed, $failed failed"
[ "$failed" = 0 ]
