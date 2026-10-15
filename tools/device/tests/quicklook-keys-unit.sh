#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of the setup's Quick Look step (Space in Dolphin, fusion-config.sh's
# ensure_quicklook_space): taken out of the script as it is and run in a throw-away HOME with
# stand-ins for Dolphin and Quick Look; Dolphin's interface file (kxmlgui5/dolphin/dolphinui.rc)
# is checked as XML. Then fusion-restore.sh's file loop puts the file back from the backup the
# setup made. Test tooling only, not installed.
#
#   quicklook-keys-unit.sh BASE
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

# The functions, by name: from "NAME() {" to the first "}" at the start of a line.
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
  grep -m1 '^QUICKLOOK_ACTION=' "$TOOL"
  grep -m1 '^DOLPHIN_UI_REL=' "$TOOL"
  extract note install_text data_path quicklook_installed dolphin_ui_with_quicklook ensure_quicklook_space
} >"$LIB"
grep -q '^ensure_quicklook_space() {' "$LIB" || { echo "FAIL: ensure_quicklook_space was not found in fusion-config.sh"; exit 1; }
UNDO=$BASE/undo.sh
awk '/^while read -r state path; do/ { on = 1 } on { print } on && /^done <"\$BACKUP\/manifest"/ { exit }' "$RESTORE" >"$UNDO"
grep -q 'present-file' "$UNDO" || { echo "FAIL: the file loop was not found in fusion-restore.sh"; exit 1; }

# The tools the step uses; nothing else of the system is in its PATH (no Dolphin of the machine).
SYS=$BASE/sys
mkdir -p "$SYS"
for t in cat chmod dirname mkdir mv python3 stat; do
  ln -s "$(command -v "$t")" "$SYS/$t"
done

PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
ACTION=servicemenu_plasma-fusion-quicklook.desktop::quicklook
RC_REL=.local/share/kxmlgui5/dolphin/dolphinui.rc

setup_case() { # NAME [dolphin] [quicklook]: a HOME with the stand-ins asked for
  CASE=$BASE/$1
  mkdir -p "$CASE/home/.local/share" "$CASE/bin" "$CASE/backup"
  : >"$CASE/backup/manifest"
  shift
  for t in "$@"; do
    case $t in
      dolphin) printf '#!/bin/sh\nexit 0\n' >"$CASE/bin/dolphin" ;;
      quicklook)
        printf '#!/bin/sh\nexit 0\n' >"$CASE/bin/plasma-fusion-quicklook"
        mkdir -p "$CASE/home/.local/share/kio/servicemenus"
        : >"$CASE/home/.local/share/kio/servicemenus/plasma-fusion-quicklook.desktop"
        ;;
    esac
  done
  chmod +x "$CASE"/bin/* 2>/dev/null || true
  RC=$CASE/home/$RC_REL
}
backup() { # what the setup's backup does for the file (make_backup, BACKUP_HOME)
  if [ -e "$RC" ]; then
    mkdir -p "$CASE/backup/home/$(dirname "$RC_REL")"
    cp -a "$RC" "$CASE/backup/home/$RC_REL"
    echo "present-file $RC_REL" >>"$CASE/backup/manifest"
  else
    echo "absent-file $RC_REL" >>"$CASE/backup/manifest"
  fi
}
run_step() { # the step in the case's HOME; prints its notes
  env -i PATH="$CASE/bin:$SYS" HOME="$CASE/home" /bin/bash -c '
    set -euo pipefail
    . "$1"
    DRY=0 CHANGES=0 DATA=$HOME/.local/share INSTALL=
    ensure_quicklook_space
    echo "changes=$CHANGES"' _ "$LIB"
}
run_undo() {
  env -i PATH="/usr/bin:/bin" HOME="$CASE/home" bash -c '
    set -euo pipefail
    note() { printf "  %s\n" "$*"; }
    run() { "$@"; }
    DRY=0 DATA=$HOME/.local/share CONFIG=$HOME/.config BACKUP=$2
    . "$1"' _ "$UNDO" "$CASE/backup"
}
# The shortcut of an action in the file ("<none>" without an entry), its version, the root's name.
xml() { # EXPRESSION over the parsed file (actions: {name: shortcut}, version, gui, text)
  python3 - "$RC" "$1" <<'PY'
import sys
from xml.dom import minidom
doc = minidom.parse(sys.argv[1])
gui = doc.documentElement
props = [e for e in gui.childNodes if e.nodeType == e.ELEMENT_NODE and e.tagName == "ActionProperties"]
actions = {a.getAttribute("name"): a.getAttribute("shortcut") for p in props for a in p.getElementsByTagName("Action")}
version, text = gui.getAttribute("version"), open(sys.argv[1]).read()
print(eval(sys.argv[2]))
PY
}

# 1. Without Dolphin, or without Quick Look, nothing is written.
setup_case nodolphin quicklook
out=$(run_step)
[ ! -e "$RC" ] && case $out in *"Dolphin is not installed"*changes=0*) true ;; *) false ;; esac &&
  ok "without Dolphin nothing is written" || bad "without Dolphin: $out"
setup_case noquicklook dolphin
out=$(run_step)
[ ! -e "$RC" ] && case $out in *"Quick Look is not installed"*changes=0*) true ;; *) false ;; esac &&
  ok "without Quick Look Dolphin's Space is left alone" || bad "without Quick Look: $out"

# 2. No copy of Dolphin's file yet (the usual case): a version-0 file with Space for Quick Look and
#    none for selection mode, which Dolphin merges into its own; a second run keeps it.
setup_case fresh dolphin quicklook
backup
out=$(run_step)
[ -f "$RC" ] && [ "$(xml 'gui.tagName, gui.getAttribute("name"), version')" = "('gui', 'dolphin', '0')" ] &&
  ok "a new file is a Dolphin interface of version 0 (merged into Dolphin's own)" || bad "the new file: $(cat "$RC" 2>&1)"
[ "$(xml "actions.get('$ACTION', '<none>'), actions.get('toggle_selection_mode', '<none>')")" = "('Space', '')" ] &&
  ok "Space goes to Quick Look, selection mode's Space is taken off" || bad "the shortcuts: $(xml actions)"
[ "$(xml "'MenuBar' in text or 'ToolBar' in text")" = False ] && ok "the file holds only shortcuts (menus and toolbars stay Dolphin's)" ||
  bad "the file holds more than shortcuts"
case $out in *"Space shows Quick Look"*changes=1*) ok "the setup says so, from Dolphin's next start" ;; *) bad "the notes: $out" ;; esac
before=$(cat "$RC")
out=$(run_step)
[ "$(cat "$RC")" = "$before" ] && case $out in *"(kept)"*changes=0*) true ;; *) false ;; esac &&
  ok "a second run changes nothing" || bad "a second run: $out"
run_undo >/dev/null
[ ! -e "$RC" ] && ok "restore: the file the setup made is removed" || bad "restore: the file is still there"

# 3. Dolphin's own merged file (a user who changed shortcuts): Quick Look added, the rest kept.
setup_case merged dolphin quicklook
mkdir -p "$(dirname "$RC")"
cat >"$RC" <<'EOF'
<?xml version='1.0' encoding='UTF-8'?>
<!DOCTYPE gui SYSTEM "kpartgui.dtd">
<gui name="dolphin" version="38">
 <MenuBar>
  <Menu name="file"><Action name="new_menu"/></Menu>
 </MenuBar>
 <ToolBar name="mainToolBar"><Action name="go_back"/></ToolBar>
 <ActionProperties scheme="Default">
  <Action name="edit_cut" shortcut="Ctrl+Shift+X"/>
 </ActionProperties>
</gui>
EOF
original=$(cat "$RC")
backup
out=$(run_step)
[ "$(xml "version, actions.get('edit_cut'), actions.get('$ACTION'), actions.get('toggle_selection_mode')")" = "('38', 'Ctrl+Shift+X', 'Space', '')" ] &&
  ok "in Dolphin's own file: the user's keys and the version stay, Quick Look gets Space" || bad "merged: $(xml 'version, actions')"
[ "$(xml "'<Menu name=\"file\">' in text and 'mainToolBar' in text")" = True ] && ok "its menus and toolbars stay" || bad "the menus are gone"
run_undo >/dev/null
[ "$(cat "$RC")" = "$original" ] && ok "restore: the user's file comes back as it was" || bad "restore: $(cat "$RC")"

# 4. The user moved selection mode to another key: Space is free, selection mode keeps theirs.
setup_case moved dolphin quicklook
mkdir -p "$(dirname "$RC")"
printf '<!DOCTYPE gui>\n<gui name="dolphin" version="38"><ActionProperties scheme="Default"><Action name="toggle_selection_mode" shortcut="Ctrl+Shift+S"/></ActionProperties></gui>\n' >"$RC"
run_step >/dev/null
[ "$(xml "actions.get('$ACTION'), actions.get('toggle_selection_mode')")" = "('Space', 'Ctrl+Shift+S')" ] &&
  ok "selection mode on the user's own key keeps it; Quick Look gets Space" || bad "moved: $(xml actions)"

# 5. The user gave Space to an action (selection mode, or another): nothing changes.
for holder in toggle_selection_mode show_preview; do
  setup_case "taken-$holder" dolphin quicklook
  mkdir -p "$(dirname "$RC")"
  printf '<!DOCTYPE gui>\n<gui name="dolphin" version="38"><ActionProperties scheme="Default"><Action name="%s" shortcut="F5; Space"/></ActionProperties></gui>\n' "$holder" >"$RC"
  before=$(cat "$RC")
  out=$(run_step)
  [ "$(cat "$RC")" = "$before" ] && case $out in *"Space belongs to $holder"*changes=0*) true ;; *) false ;; esac &&
    ok "a Space the user gave $holder stays with it" || bad "taken by $holder: $out"
done

# 6. The user's own key for Quick Look (or none) is kept.
setup_case own dolphin quicklook
mkdir -p "$(dirname "$RC")"
printf '<!DOCTYPE gui>\n<gui name="dolphin" version="38"><ActionProperties scheme="Default"><Action name="%s" shortcut="F3"/></ActionProperties></gui>\n' "$ACTION" >"$RC"
before=$(cat "$RC")
out=$(run_step)
[ "$(cat "$RC")" = "$before" ] && case $out in *"(kept)"*) true ;; *) false ;; esac && ok "the user's own key for Quick Look (F3) is kept" ||
  bad "own key: $out"

# 7. A file that is not XML: left alone, with a warning.
setup_case broken dolphin quicklook
mkdir -p "$(dirname "$RC")"
printf 'not xml <' >"$RC"
out=$(run_step)
[ "$(cat "$RC")" = "not xml <" ] && case $out in *"could not be read"*) true ;; *) false ;; esac &&
  ok "an unreadable file is left alone, with a warning" || bad "broken: $out"

echo "quicklook-keys-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
