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

# ---- c: carry the unit configuration, not the last runtime verdict
C=$BASE/home-c
cfg=.config/systemd/user
dropin=$cfg/plasma-plasmashell.service.d/20-plasma-fusion-notifications.conf
notify=$cfg/plasma-fusion-notifications-notify.service
watch=$cfg/plasma-fusion-notifications-watch@.service
wants=$cfg/xdg-desktop-autostart.target.wants/plasma-fusion-notifications-notify.service
state=$C/.local/state/plasma-fusion/notifications
mkdir -p "$C/${dropin%/*}" "$C/${wants%/*}" "$state"
for f in "$dropin" "$notify" "$watch"; do printf '[Service]\n' >"$C/$f"; done
ln -s ../plasma-fusion-notifications-notify.service "$C/$wants"
printf 'past verdict\n' >"$state/qml-failed"
snap_c=$(in_home "$C" bash "$BACKUP" "$BASE/snap-c" 2>"$BASE/backup-c.err")
tar -tzf "$snap_c" >"$BASE/members-c.txt"
for f in "$dropin" "$notify" "$watch" "$wants"; do
  check "c: snapshot carries $f" grep -Fxq "$f" "$BASE/members-c.txt"
done
check "c: snapshot does not copy the runtime verdict" \
  bash -c '! grep -Fq /notifications/qml-failed "$1"' _ "$BASE/members-c.txt"
in_home "$C" bash "$RESTORE" "$snap_b" --dry-run >"$BASE/restore-c.txt" 2>&1
check "c: older snapshot removes the managed launch override" \
  grep -Fxq "would: rm -rf -- $dropin" "$BASE/restore-c.txt"
check "c: older snapshot clears the live verdict" \
  grep -Fxq "would: rm -rf -- $state" "$BASE/restore-c.txt"
check "c: dry run leaves the runtime verdict alone" test -f "$state/qml-failed"

D=$BASE/home-d
xdg="$D/custom config"
for f in "$dropin" "$notify" "$watch"; do
  mkdir -p "$xdg/$(dirname "${f#.config/}")"
  printf 'custom %s\n' "$f" >"$xdg/${f#.config/}"
done
mkdir -p "$xdg/$(dirname "${wants#.config/}")" "$D/$(dirname "$dropin")"
ln -s ../missing-notify.service "$xdg/${wants#.config/}"
printf 'not the live override\n' >"$D/$dropin"
# The default tree's wants directory is snapshotted as a whole, but with this config home the
# notification link in it is not the managed one: the archive holds the custom tree's instead.
mkdir -p "$D/${wants%/*}"
ln -s ../other.service "$D/${wants%/*}/other.service"
ln -s ../plasma-fusion-notifications-notify.service "$D/$wants"
snap_d=$(in_home "$D" env XDG_CONFIG_HOME="$xdg" bash "$BACKUP" "$BASE/snap-d" 2>"$BASE/backup-d.err")
check "d: snapshot captures live XDG override at the compatible archive path" bash -c '
  actual=$(tar -xzOf "$1" "$2"); [[ $actual == "custom $2" ]]' _ "$snap_d" "$dropin"
tar -tvzf "$snap_d" >"$BASE/members-d.txt"
check "d: snapshot preserves the dangling custom XDG wants link" \
  grep -Fq "$wants -> ../missing-notify.service" "$BASE/members-d.txt"
in_home "$D" env XDG_CONFIG_HOME="$xdg" bash "$RESTORE" "$snap_d" --dry-run >"$BASE/restore-d.txt" 2>&1
check "d: current snapshot restores the override to the live XDG config home" \
  grep -Fq " $xdg/${dropin#.config/}" "$BASE/restore-d.txt"
in_home "$D" env XDG_CONFIG_HOME="$xdg" bash "$RESTORE" "$snap_b" --dry-run >"$BASE/restore-d-old.txt" 2>&1
check "d: older snapshot removes the live XDG override" \
  grep -Fxq "would: rm -f -- $xdg/${dropin#.config/}" "$BASE/restore-d-old.txt"

mkdir "$BASE/profile-test-bin"
for t in systemctl qdbus-qt6 kquitapp6 sleep fc-cache setsid; do
  ln -s /usr/bin/true "$BASE/profile-test-bin/$t"
done
restore_custom() {
  in_home "$D" env PATH="$BASE/profile-test-bin:$PATH" XDG_CONFIG_HOME="$xdg" \
    bash "$RESTORE" "$1"
}
printf 'changed\n' >"$xdg/${dropin#.config/}"
restore_custom "$snap_d" >"$BASE/restore-d-live.txt" 2>&1
check "d: current restore writes the saved custom-XDG override" bash -c \
  '[[ $(<"$1") == "custom $2" ]]' _ "$xdg/${dropin#.config/}" "$dropin"
check "d: current restore writes the exact dangling link" bash -c \
  '[[ $(readlink "$1") == ../missing-notify.service ]]' _ "$xdg/${wants#.config/}"
check "d: current restore keeps the default tree's own notification link" bash -c \
  '[[ $(readlink "$1") == ../plasma-fusion-notifications-notify.service ]]' _ "$D/$wants"
check "d: ...and restores the rest of that wants directory" bash -c \
  '[[ $(readlink "$1") == ../other.service ]]' _ "$D/${wants%/*}/other.service"
restore_custom "$snap_b" >"$BASE/restore-d-live-old.txt" 2>&1
check "d: older restore actually removes the custom-XDG override" test ! -e "$xdg/${dropin#.config/}"
check "d: older restore also removes a dangling custom link" test ! -L "$xdg/${wants#.config/}"
check "d: the unrelated default config override is untouched" grep -Fxq 'not the live override' "$D/$dropin"
# A failed copy of the default tree's own notification link must not cost that link: the restore
# then leaves its directory as it was.
mkdir "$BASE/profile-test-bin-cpfail"
cat >"$BASE/profile-test-bin-cpfail/cp" <<'EOF'
#!/bin/bash
if [[ $1 == -a && $2 == --remove-destination && $3 == -- && $4 == .config/*/plasma-fusion-notifications-notify.service ]]; then
  exit 1
fi
exec /usr/bin/cp "$@"
EOF
chmod +x "$BASE/profile-test-bin-cpfail/cp"
in_home "$D" env PATH="$BASE/profile-test-bin-cpfail:$BASE/profile-test-bin:$PATH" XDG_CONFIG_HOME="$xdg" \
  bash "$RESTORE" "$snap_d" >"$BASE/restore-d-keep-failed.txt" 2>&1
check "d: a restore that cannot keep that link leaves its directory as it was" bash -c \
  '[[ $(readlink "$1") == ../plasma-fusion-notifications-notify.service && $(readlink "$2") == ../other.service ]]' \
  _ "$D/$wants" "$D/${wants%/*}/other.service"

echo "== $passed passed, $failed failed"
[ "$failed" = 0 ]
