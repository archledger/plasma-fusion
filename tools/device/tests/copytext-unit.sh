#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of the copy-text shortcut (Meta+Shift+T, Spectacle's region capture and its Extract
# Text): fusion-config.sh's step and fusion-restore.sh's undo, taken out of the scripts as they are
# and run against a fake kglobalaccel (copytext_fakebus.py, a JSON state file) in a throw-away HOME.
# Test tooling only, not installed; never touches the caller's session or configuration.
#
#   copytext-unit.sh BASE
#
# BASE must be a scratch directory on disk (not /tmp); it is emptied first.
set -euo pipefail
BASE=${1:?scratch directory}
BASE=$(realpath -m -- "$BASE")
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
TOOL=$HERE/../fusion-config.sh
RESTORE=$HERE/../fusion-restore.sh
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
LIB=$BASE/lib.sh
{
  grep -m1 '^META=' "$TOOL"
  grep -m1 '^COPYTEXT_COMPONENT=' "$TOOL" || true
  grep -m1 '^COPYTEXT_SHORTCUT=' "$TOOL" || true
  extract note keyname install_text shortcut_get shortcut_set key_holders copytext_desktop ensure_copytext_shortcut
} >"$LIB"
grep -q '^ensure_copytext_shortcut() {' "$LIB" || { echo "FAIL: ensure_copytext_shortcut was not found in fusion-config.sh"; exit 1; }
# fusion-restore.sh: the shortcut records and the components (section 1), and the files of the
# manifest (section 3's loop).
UNDO=$BASE/undo.sh
{
  grep -m1 '^NOTIFY_COMPONENT=' "$RESTORE"
  grep -m1 '^COPYTEXT_COMPONENT=' "$RESTORE" || true
  awk '/^# 1\. Shortcuts, newest change first/ { on = 1 } /^# 1b\. / { exit } on { print }' "$RESTORE"
  awk '/^while read -r state path; do/ { on = 1 } on { print } on && /^done <"\$BACKUP\/manifest"/ { exit }' "$RESTORE"
} >"$UNDO"
grep -q 'unregister' "$UNDO" || { echo "FAIL: the shortcut section was not found in fusion-restore.sh"; exit 1; }

PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
# STATE JSON for the fake bus: {"keys": {"comp|action": [keys]}, "registered": [...], "calls": [...]}
setup_case() { # NAME [initial state JSON]
  CASE=$BASE/$1
  mkdir -p "$CASE/home/.local/share" "$CASE/backup" "$CASE/bin"
  printf '%s\n' "${2:-{\}}" >"$CASE/state.json"
  : >"$CASE/backup/shortcuts"
  printf '#!/bin/sh\nexit 0\n' >"$CASE/bin/spectacle"
  chmod +x "$CASE/bin/spectacle"
}
run_step() { # [nospectacle]: fusion-config.sh's step in the case's HOME; prints its notes
  env -i PATH="$CASE/bin:/usr/bin:/bin" HOME="$CASE/home" FAKE_STATE="$CASE/state.json" FAKEBUS="$HERE/copytext_fakebus.py" \
    NOSPECTACLE="${1:-}" bash -c '
    set -euo pipefail
    bus() { python3 "$FAKEBUS" "$FAKE_STATE" plain "$@"; }
    bus_json() { python3 "$FAKEBUS" "$FAKE_STATE" json "$@"; }
    if [ -n "$NOSPECTACLE" ]; then
      command() { if [ "$1" = -v ] && [ "${2:-}" = spectacle ]; then return 1; fi; builtin command "$@"; }
    fi
    . "$1"
    DRY=0 CHANGES=0 DATA=$HOME/.local/share BACKUP=$2
    ensure_copytext_shortcut
    echo "changes=$CHANGES"' _ "$LIB" "$CASE/backup"
}
run_undo() { # fusion-restore.sh's sections for the case's backup
  env -i PATH="/usr/bin:/bin" HOME="$CASE/home" FAKE_STATE="$CASE/state.json" FAKEBUS="$HERE/copytext_fakebus.py" bash -c '
    set -euo pipefail
    bus() { python3 "$FAKEBUS" "$FAKE_STATE" plain "$@"; }
    note() { printf "  %s\n" "$*"; }
    run() { "$@"; }
    DRY=0 DATA=$HOME/.local/share CONFIG=$HOME/.config BACKUP=$2 LATER=()
    . "$1"' _ "$UNDO" "$CASE/backup"
}
state() { python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {"s": s}))' "$CASE/state.json" "$1"; }
FILE=.local/share/kglobalaccel/org.plasmafusion.copytext.desktop
KEY=$((0x10000000 + 0x02000000 + 0x54))

# 1. A free key: the component is installed, registered and gets Meta+Shift+T; the old (no) key is
#    recorded for the restore.
setup_case free
out=$(run_step)
f=$CASE/home/$FILE
[ -x "$f" ] && grep -qx 'Exec=spectacle --region' "$f" && ok "the component file is executable and runs spectacle --region" ||
  bad "the component file: $(ls -l "$f" 2>&1)"
[ "$(state 's["keys"].get("org.plasmafusion.copytext.desktop|_launch")')" = "[$KEY]" ] && ok "Meta+Shift+T is set" ||
  bad "Meta+Shift+T is set: $(state 's.get("keys")') / $out"
[ "$(state '"org.plasmafusion.copytext.desktop|_launch" in s.get("registered", [])')" = True ] && ok "the component is registered with kglobalaccel" ||
  bad "the component is registered: $(state 's.get("registered")')"
[ "$(state '"org.plasmafusion.copytext.desktop|_launch" in s.get("present", [])')" = True ] &&
  ok "its key is given again as present, so it works before the next login" || bad "present: $(state 's.get("present")')"
[ "$(cat "$CASE/backup/shortcuts")" = "$(printf 'org.plasmafusion.copytext.desktop\t_launch\t')" ] && ok "the previous key (none) is recorded" ||
  bad "the previous key is recorded: $(cat -A "$CASE/backup/shortcuts")"
# A second run changes nothing.
out=$(run_step)
case $out in *"(kept)"*changes=0*) ok "a second run keeps the key and changes nothing" ;; *) bad "a second run: $out" ;; esac
# The restore gives the key back (none), unregisters the component and removes the file it made.
printf 'absent-file %s\n' "$FILE" >"$CASE/backup/manifest"
run_undo >/dev/null
[ "$(state 's["keys"].get("org.plasmafusion.copytext.desktop|_launch")')" = "[]" ] && ok "restore: the key goes back to none" ||
  bad "restore: the key goes back to none: $(state 's.get("keys")')"
[ "$(state '"org.plasmafusion.copytext.desktop|_launch" in s.get("unregistered", [])')" = True ] && ok "restore: the component is unregistered" ||
  bad "restore: the component is unregistered: $(state 's.get("unregistered")')"
[ ! -e "$f" ] && ok "restore: the component file is removed" || bad "restore: the component file is still there"

# 2. Another action holds Meta+Shift+T: it keeps it, the component gets no key.
setup_case taken "{\"keys\": {\"kwin|Some Action\": [$KEY]}}"
out=$(run_step)
[ "$(state 's["keys"].get("kwin|Some Action")')" = "[$KEY]" ] && [ "$(state 's["keys"].get("org.plasmafusion.copytext.desktop|_launch", [])')" = "[]" ] &&
  case $out in *"is in use"*) true ;; *) false ;; esac && ok "a key in use stays with its action; the setup says so" ||
  bad "a key in use: $(state 's.get("keys")') / $out"

# 3. The user gave the action another key: it is kept.
setup_case user "{\"keys\": {\"org.plasmafusion.copytext.desktop|_launch\": [$((0x10000000 + 0x08000000 + 0x54))]}}"
out=$(run_step)
[ "$(state 's["keys"].get("org.plasmafusion.copytext.desktop|_launch")')" = "[$((0x10000000 + 0x08000000 + 0x54))]" ] &&
  case $out in *"Meta+Alt+T (kept)"*) true ;; *) false ;; esac && ok "the user's own key (Meta+Alt+T) is kept" || bad "the user's own key: $out"

# 4. No Spectacle: nothing is installed or registered.
setup_case nospectacle
out=$(run_step nospectacle)
[ ! -e "$CASE/home/$FILE" ] && [ "$(state 's.get("registered", [])')" = "[]" ] && ok "without Spectacle nothing is installed" ||
  bad "without Spectacle: $out"

# 5. Quick settings' header action runs the component's command (one action, two ways in).
QS=$HERE/../../../packages/plasmoids/org.plasmafusion.quicksettings/contents/ui
cmd=$(bash -c '. "$1"; copytext_desktop' _ "$LIB" | sed -n 's/^Exec=//p')
grep -qF "spectacle --region >/dev/null 2>&1 &" "$QS/Backend.qml" && [ "$cmd" = "spectacle --region" ] &&
  grep -q 'onClicked: page.backend.session.copyText()' "$QS/QuickSettingsMain.qml" &&
  ok "quick settings' header button runs the same command ($cmd)" || bad "quick settings' header button and the component differ"

echo "copytext-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
