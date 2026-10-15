#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of the copy-text shortcut (Meta+Shift+T: plasma-fusion-copytext, else Spectacle's region
# capture and its Extract Text): fusion-config.sh's step and fusion-restore.sh's undo, taken out of
# the scripts as they are and run against a fake kglobalaccel (copytext_fakebus.py, a JSON state
# file) in a throw-away HOME, and quick settings' header command run with stand-ins. The helper's
# own tests: packages/copytext/tests/helper-unit.sh. Test tooling only, not installed; never
# touches the caller's session or configuration.
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
  awk '/^HELPER_DIRS=\(/ { on = 1 } on { print } on && /\)$/ { exit }' "$TOOL"
  extract note keyname install_text shortcut_get shortcut_set key_holders helper_path copytext_exec copytext_desktop \
    component_loaded ensure_copytext_shortcut
} >"$LIB"
grep -q '^ensure_copytext_shortcut() {' "$LIB" || { echo "FAIL: ensure_copytext_shortcut was not found in fusion-config.sh"; exit 1; }
# fusion-restore.sh: the shortcut records and the components (section 1), and the files of the
# manifest (section 3's loop).
UNDO=$BASE/undo.sh
{
  grep -m1 '^NOTIFY_COMPONENT=' "$RESTORE"
  grep -m1 '^COPYTEXT_COMPONENT=' "$RESTORE" || true
  grep -m1 '^CLIPBOARD_COMPONENT=' "$RESTORE" || true
  awk '/^# 1\. Shortcuts, newest change first/ { on = 1 } /^# 1b\. / { exit } on { print }' "$RESTORE"
  awk '/^while read -r state path; do/ { on = 1 } on { print } on && /^done <"\$BACKUP\/manifest"/ { exit }' "$RESTORE"
} >"$UNDO"
grep -q 'unregister' "$UNDO" || { echo "FAIL: the shortcut section was not found in fusion-restore.sh"; exit 1; }

PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
# STATE JSON for the fake bus: {"keys": {"comp|action": [keys]}, "registered": [...], "calls": [...]}
setup_case() { # NAME [initial state JSON] [HOME's name]
  CASE=$BASE/$1
  CHOME=$CASE/${3:-home}
  mkdir -p "$CHOME/.local/share" "$CASE/backup" "$CASE/bin"
  printf '%s\n' "${2:-{\}}" >"$CASE/state.json"
  : >"$CASE/backup/shortcuts"
  printf '#!/bin/sh\nexit 0\n' >"$CASE/bin/spectacle"
  chmod +x "$CASE/bin/spectacle"
}
run_step() { # [nospectacle]: fusion-config.sh's step in the case's HOME; prints its notes
  env -i PATH="$CASE/bin:/usr/bin:/bin" HOME="$CHOME" FAKE_STATE="$CASE/state.json" FAKEBUS="$HERE/copytext_fakebus.py" \
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
  env -i PATH="/usr/bin:/bin" HOME="$CHOME" FAKE_STATE="$CASE/state.json" FAKEBUS="$HERE/copytext_fakebus.py" bash -c '
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
HELPER_REL=.local/libexec/plasma-fusion/plasma-fusion-copytext
# A system package's helper (a machine with Plasma Fusion installed) is found after the user's.
SYSTEM_HELPER=
for d in /usr/local/libexec/plasma-fusion /usr/libexec/plasma-fusion /usr/lib/plasma-fusion /run/current-system/sw/libexec/plasma-fusion; do
  [ -x "$d/plasma-fusion-copytext" ] && { SYSTEM_HELPER=$d/plasma-fusion-copytext; break; }
done
NO_HELPER=${SYSTEM_HELPER:-spectacle --region}
add_helper() { # the user's copy of the helper (fusion-config.sh --install), in the case's HOME
  mkdir -p "$(dirname "$CHOME/$HELPER_REL")"
  printf '#!/bin/sh\necho helper >>"$T/ran"\n' >"$CHOME/$HELPER_REL"
  chmod +x "$CHOME/$HELPER_REL"
}

# 1. A free key: the component is installed, registered and gets Meta+Shift+T; the old (no) key is
#    recorded for the restore.
setup_case free
out=$(run_step)
f=$CASE/home/$FILE
[ -x "$f" ] && grep -qx "Exec=$NO_HELPER" "$f" && ok "the component file is executable and, without the helper, runs $NO_HELPER" ||
  bad "the component file: $(ls -l "$f" 2>&1) $(grep '^Exec=' "$f" 2>&1)"
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

# 1b. With the helper installed (--install, or the package) the key runs it; a component file from
#     an earlier run (spectacle --region) is written again.
setup_case helper
mkdir -p "$(dirname "$CASE/home/$FILE")"
printf '[Desktop Entry]\nExec=spectacle --region\n' >"$CASE/home/$FILE"
add_helper
out=$(run_step)
f=$CASE/home/$FILE
grep -qx "Exec=$CASE/home/$HELPER_REL" "$f" &&
  grep -qx "Comment=Select an area to copy its text (installed by Plasma Fusion's fusion-config.sh, removed by fusion-restore.sh)" "$f" &&
  case $out in *"write $f"*) true ;; *) false ;; esac && ok "with the helper the key runs it (the earlier file is written again)" ||
  bad "with the helper: $(grep -e '^Exec=' -e '^Comment=' "$f") / $out"
# A HOME with a space: the path is quoted; one with a character the desktop entry would have to
# escape: Spectacle's region capture.
setup_case space '{}' "my home"
add_helper
run_step >/dev/null
grep -qxF "Exec=\"$CHOME/$HELPER_REL\"" "$CHOME/$FILE" && ok "a helper path with a space is quoted in Exec" ||
  bad "a helper path with a space: $(grep '^Exec=' "$CHOME/$FILE")"
setup_case dollar '{}' 'home$x'
add_helper
run_step >/dev/null
grep -qxF "Exec=$NO_HELPER" "$CHOME/$FILE" && ok "a helper path with a \$ is not used" || bad "a helper path with a \$: $(grep '^Exec=' "$CHOME/$FILE")"
setup_case percent '{}' 'home%q'
add_helper
run_step >/dev/null
grep -qxF "Exec=$NO_HELPER" "$CHOME/$FILE" && ok "a helper path with a % (a field code) is not used" || bad "a helper path with a %: $(grep '^Exec=' "$CHOME/$FILE")"

# 1c. An update in a running session: kglobalaccel holds the 0.5.0 component (spectacle --region)
#     with the user's own key. The component is made again from the new file (unregistered, then
#     registered), and the key is the same afterwards; the backup records no change of key.
ALT_T=$((0x10000000 + 0x08000000 + 0x54))
setup_case reload "{\"keys\": {\"org.plasmafusion.copytext.desktop|_launch\": [$ALT_T]}, \"loaded\": [\"org.plasmafusion.copytext.desktop|_launch\"]}"
mkdir -p "$(dirname "$CHOME/$FILE")"
printf '[Desktop Entry]\nExec=spectacle --region\n' >"$CHOME/$FILE"
add_helper
out=$(run_step)
[ "$(state 's.get("unregistered")')" = "['org.plasmafusion.copytext.desktop|_launch']" ] &&
  [ "$(state 's.get("loaded")')" = "['org.plasmafusion.copytext.desktop|_launch']" ] &&
  case $out in *"reload org.plasmafusion.copytext.desktop"*) true ;; *) false ;; esac &&
  ok "a loaded component with an old command is made again (unregistered, registered)" ||
  bad "the reload: unregistered $(state 's.get("unregistered")'), loaded $(state 's.get("loaded")') / $out"
[ "$(state 's["keys"].get("org.plasmafusion.copytext.desktop|_launch")')" = "[$ALT_T]" ] && [ ! -s "$CASE/backup/shortcuts" ] &&
  ok "the reload keeps the user's key (Meta+Alt+T) and records no change" ||
  bad "after the reload: $(state 's.get("keys")'), backup $(cat "$CASE/backup/shortcuts")"
grep -qx "Exec=$CHOME/$HELPER_REL" "$CHOME/$FILE" && ok "the reloaded component's file runs the helper" || bad "the file: $(grep '^Exec=' "$CHOME/$FILE")"
out=$(run_step)
[ "$(state 'len(s.get("unregistered", []))')" = 1 ] && ok "a second run does not reload (the command is the same)" ||
  bad "a second run reloaded again: $(state 's.get("unregistered")')"

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

# 5. Quick settings' header button runs what the key runs (one action, two ways in): its command,
#    as Plasma's executable source runs it (sh -c), finds the helper where the setup does, in the
#    same order, else starts Spectacle's region capture.
QS=$HERE/../../../packages/plasmoids/org.plasmafusion.quicksettings/contents/ui
qs_cmd=$(python3 -c '
import json, re, sys
lines = open(sys.argv[1]).read().split("\n")
at = [i for i, l in enumerate(lines) if "readonly property string copyTextCommand:" in l]
text = ""
if at:
    part = [lines[at[0]].split("copyTextCommand:", 1)[1]]
    for l in lines[at[0] + 1:]:
        if not l.strip().startswith("+"):
            break
        part.append(l)
    text = "".join(json.loads(x) for x in re.findall(r"\"(?:[^\"\\]|\\.)*\"", " ".join(part)))
print(text)' "$QS/Backend.qml")
grep -q 'onTriggered: backend.run(backend.copyTextCommand)' "$QS/Backend.qml" &&
  grep -q 'onClicked: page.backend.session.copyText()' "$QS/QuickSettingsMain.qml" && [ -n "$qs_cmd" ] &&
  ok "the header button runs Backend.copyTextCommand" || bad "the header button's command was not found"
# The places, in order: the command's list against fusion-config.sh's HELPER_DIRS.
dirs=$([ -n "$qs_cmd" ] || { echo "no command"; exit 0; }; python3 -c '
import re, shlex, sys
cmd, tool = sys.argv[1], open(sys.argv[2]).read()
qs = shlex.split(re.search(r"for d in (.*?); do", shlex.split(cmd)[2]).group(1))
setup = shlex.split(re.search(r"^HELPER_DIRS=\((.*?)\)$", tool, re.S | re.M).group(1).replace("\\\n", " "))
print("same" if qs == setup else "differ: %s / %s" % (qs, setup))' "$qs_cmd" "$TOOL" || echo "unreadable")
[ "$dirs" = same ] && ok "the button looks in the setup's places, in its order" || bad "the button's places: $dirs"
qs_run() { # runs the command in the case's HOME; prints what ran
  env -i PATH="$CASE/bin:/usr/bin:/bin" HOME="$CHOME" T="$CASE" sh -c "$qs_cmd"
  for _ in $(seq 50); do [ -s "$CASE/ran" ] && break; sleep 0.1; done
  cat "$CASE/ran" 2>/dev/null
}
setup_case qs-helper
printf '#!/bin/sh\necho "spectacle $*" >>"$T/ran"\n' >"$CASE/bin/spectacle"
add_helper
[ "$(qs_run)" = helper ] && ok "with the user's helper the button runs it" || bad "the button with the helper ran: $(cat "$CASE/ran" 2>/dev/null)"
setup_case qs-spectacle
printf '#!/bin/sh\necho "spectacle $*" >>"$T/ran"\n' >"$CASE/bin/spectacle"
if [ -z "$SYSTEM_HELPER" ]; then
  [ "$(qs_run)" = "spectacle --region" ] && ok "without the helper the button starts spectacle --region" ||
    bad "the button without the helper ran: $(cat "$CASE/ran" 2>/dev/null)"
else
  echo "(the button without the helper: not run, $SYSTEM_HELPER is installed)"
fi

echo "copytext-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
