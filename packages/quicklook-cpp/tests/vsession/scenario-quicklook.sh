#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Quick Look from Dolphin in a private session (real Dolphin, KWin's emulated keys). The HOME holds
# Quick Look installed below ~/.local (bin/, share/kio/servicemenus, share/applications), the stage
# in ~/pf-stage and tools/ in ~/pf-tools. The Fusion setup runs (its Quick Look step writes
# Dolphin's interface file), then in a folder of three files:
#   1. after Dolphin's start its interface file is Dolphin's own (menus, toolbars, its version)
#      with Space for Quick Look and none for "Select Files and Folders";
#   2. the first file selected, Space opens Quick Look on it; Space closes it;
#   3. Ctrl+A, Space: the three files, "1 of 3"; Right shows the second; Esc closes;
#   4. Space again in Dolphin on the same selection closes the open preview;
#   5. fusion-restore.sh removes the file, and after Dolphin starts again Space opens nothing.
# In step 3, with the text file shown, its text selected with the mouse and Ctrl+C put it on the
# clipboard.
# ~/ql-mode selects a red run: "none" (no setup: Dolphin's own keys), "ambiguous" (Space on both
# actions: neither runs). "removed": after step 1 Quick Look is removed and the setup runs again:
# Dolphin's file has neither entry left, and after Dolphin starts again Space toggles selection mode
# (Dolphin's view changes: its selection bars). "removed-red": Quick Look removed, no second setup:
# Space does nothing.
# Run: tools/vsession/vsession.sh ql-1 packages/quicklook-cpp/tests/vsession/scenario-quicklook.sh 1440x900 420
exec 2>&1
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }
# As a login shell on Fedora: the user's ~/.local/bin first (Quick Look's program is there).
export PATH=$HOME/.local/bin:$PATH
MODE=$(cat "$HOME/ql-mode" 2>/dev/null || true)
info "mode: ${MODE:-normal}"
RC=$HOME/.local/share/kxmlgui5/dolphin/dolphinui.rc
ACTION=servicemenu_plasma-fusion-quicklook.desktop::quicklook

# Quick Look's window: its caption ("NAME — Quick Look"), empty when there is none.
ql_caption() {
  K run "var l = workspace.windowList(), c = ''; for (var i = 0; i < l.length; ++i) {
    if (String(l[i].caption).indexOf('— Quick Look') >= 0) { c = String(l[i].caption); } } report(c);" |
    python3 -c 'import json, sys; print(json.load(sys.stdin))'
}
wait_caption() { # PATTERN SECONDS: until Quick Look's caption matches (empty pattern: until it is gone)
  local i c
  for ((i = 0; i < $2 * 4; i++)); do
    c=$(ql_caption)
    if [ -z "$1" ] && [ -z "$c" ]; then return 0; fi
    if [ -n "$1" ] && [[ $c == *"$1"* ]]; then return 0; fi
    sleep 0.25
  done
  return 1
}
ql_running() { pgrep -u "$(id -u)" -f 'plasma-fusion-quicklook' >/dev/null 2>&1; }
dolphin_active() { # gives Dolphin the keyboard (the window KWin shows in front)
  K run "var l = workspace.windowList(); for (var i = 0; i < l.length; ++i) {
    if (String(l[i].resourceClass).indexOf('dolphin') >= 0 && l[i].normalWindow) { workspace.activeWindow = l[i]; } } report(1);" >/dev/null
  sleep 1
}
# Selects the first file only. Dolphin starts with the first file current but nothing selected,
# and a key selects only when it moves the current item (KItemListController::keyPressEvent):
# Ctrl+A selects all (the keyboard in the file view), End and Home leave the first file alone.
select_first() {
  dolphin_active
  pfinput 'key ctrl+a' 'sleep 1' 'key end' 'sleep 0.5' 'key home' 'sleep 1.5'
}
# A window's frame (x y width height) by its resource class or caption part.
frame() {
  K run "var l = workspace.windowList(), g = ''; for (var i = 0; i < l.length; ++i) {
    if ((String(l[i].resourceClass).indexOf('$1') >= 0 || String(l[i].caption).indexOf('$1') >= 0) && l[i].normalWindow) {
      var r = l[i].frameGeometry; g = [r.x, r.y, r.width, r.height].map(Math.round).join(' '); } } report(g);" |
    python3 -c 'import json, sys; print(json.load(sys.stdin))'
}
# The share of pixels that differ between two screenshots in a frame (x y width height).
changed() {
  python3 - "$OUT/$1.png" "$OUT/$2.png" "$3" <<'PY'
import sys
from PIL import Image, ImageChops
x, y, w, h = map(int, sys.argv[3].split())
a, b = (Image.open(f).convert("RGB").crop((x, y, x + w, y + h)) for f in sys.argv[1:3])
diff = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 16 else 0)
print("%.4f" % (sum(1 for v in diff.getdata() if v) / float(w * h)))
PY
}
xml() { python3 - "$RC" "$1" <<'PY'
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

# ---- the files: a picture, a text and a note
mkdir -p "$HOME/QL"
python3 - "$HOME/QL" <<'PY'
import struct, sys, zlib
d = sys.argv[1]
w, h = 320, 200
raw = b"".join(b"\x00" + bytes((47, 111, 223)) * w for _ in range(h))
chunk = lambda t, b: struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
open(d + "/alpha.png", "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                                    + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
open(d + "/beta.txt", "w").write("Plasma Fusion Quick Look\nsecond line\n")
open(d + "/gamma.py", "w").write("def gamma():\n    return 'Quick Look'\n")
PY

# ---- the setup (its Quick Look step), or a red run's file
if [ "$MODE" != none ]; then
  fc_rc=0
  bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || fc_rc=$?
  info "fusion-config rc=$fc_rc"
  grep -a -x -A2 'Quick Look' "$OUT/fc.log" >>"$CHK" || true
fi
if [ "$MODE" = ambiguous ]; then
  mkdir -p "$(dirname "$RC")"
  printf '<!DOCTYPE gui SYSTEM "kpartgui.dtd">\n<gui name="dolphin" version="0"><ActionProperties scheme="Default"><Action name="%s" shortcut="Space"/></ActionProperties></gui>\n' \
    "$ACTION" >"$RC"
fi
[ -f "$RC" ] && cp "$RC" "$OUT/dolphinui-before.rc"
if [ -z "$MODE" ]; then
  [ "$(xml "version, actions.get('$ACTION'), actions.get('toggle_selection_mode')")" = "('0', 'Space', '')" ] &&
    pass "the setup wrote Dolphin's file: version 0, Space for Quick Look, none for selection mode" ||
    fail "the setup's file: $(cat "$RC" 2>&1)"
fi

# ---- 1. Dolphin merges it into its own interface
dolphin "$HOME/QL" >"$OUT/dolphin.log" 2>&1 &
sleep 6
shot 10-dolphin
if [ -f "$RC" ]; then
  cp "$RC" "$OUT/dolphinui-after.rc"
  info "Dolphin's file after its start: version $(xml version), $(wc -c <"$RC") bytes"
fi
if [ -z "$MODE" ]; then
  [ "$(xml "version != '0' and '<MenuBar' in text and 'mainToolBar' in text")" = True ] &&
    [ "$(xml "actions.get('$ACTION'), actions.get('toggle_selection_mode')")" = "('Space', '')" ] &&
    pass "1: Dolphin merged it into its own interface (version $(xml version), menus and toolbars) and kept the two keys" ||
    fail "1: after Dolphin's start: version $(xml version), keys $(xml "actions.get('$ACTION'), actions.get('toggle_selection_mode')")"
fi

# ---- removed: Quick Look uninstalled after the setup gave Space
if [ "$MODE" = removed ] || [ "$MODE" = removed-red ]; then
  [ "$(xml "actions.get('$ACTION'), actions.get('toggle_selection_mode')")" = "('Space', '')" ] &&
    info "the two keys are set (version $(xml version))" || fail "removed: the setup did not give the keys"
  pkill -u "$(id -u)" -x dolphin || true
  sleep 2
  rm -f "$HOME/.local/bin/plasma-fusion-quicklook" "$HOME/.local/share/kio/servicemenus/plasma-fusion-quicklook.desktop" \
    "$HOME/.local/share/applications/org.plasmafusion.quicklook.desktop"
  if [ "$MODE" = removed ]; then
    fc_rc=0
    bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc2.log" 2>&1 || fc_rc=$?
    info "fusion-config (Quick Look removed) rc=$fc_rc"
    grep -a -x -A2 'Quick Look' "$OUT/fc2.log" >>"$CHK" || true
  fi
  cp "$RC" "$OUT/dolphinui-removed.rc" 2>/dev/null || true
  [ -f "$RC" ] && [ "$(xml "version != '0' and '<MenuBar' in text, '$ACTION' in actions, 'toggle_selection_mode' in actions")" = "(True, False, False)" ] &&
    pass "removed: Dolphin's file keeps its own interface (version $(xml version)) without the two entries" ||
    fail "removed: Dolphin's file: $(xml "version, actions.get('$ACTION'), actions.get('toggle_selection_mode')" 2>/dev/null)"
  dolphin "$HOME/QL" >>"$OUT/dolphin.log" 2>&1 &
  sleep 6
  select_first
  geo=$(frame dolphin)
  info "Dolphin's window at $geo"
  shot 60-before-space
  pfinput 'key space' 'sleep 2'
  shot 61-after-space
  part=$(changed 60-before-space 61-after-space "$geo")
  info "Dolphin's window changed by $part after Space"
  python3 -c "import sys; sys.exit(0 if float('$part') > 0.01 else 1)" &&
    pass "removed: Space toggles selection mode again (Dolphin's view changed by $part, 61-after-space.png)" ||
    fail "removed: Space changed nothing in Dolphin ($part)"
  pkill -u "$(id -u)" -x dolphin || true
  info "done"
  exit 0
fi

# ---- 2. one file
select_first
pfinput 'key space'
if [ -z "$MODE" ]; then
  wait_caption "alpha.png" 10 && [ "$(ql_caption)" = "alpha.png — Quick Look" ] &&
    pass "2: the first file selected, Space opens Quick Look on it alone ($(ql_caption))" ||
    fail "2: no Quick Look window (caption '$(ql_caption)')"
  sleep 1
  shot 20-picture
  pfinput 'key space'
  wait_caption "" 10 && pass "2: Space closes it" || fail "2: Space did not close it ($(ql_caption))"
  sleep 1
  ql_running && fail "2: the program still runs" || pass "2: the program ended"
else
  sleep 4
  [ -z "$(ql_caption)" ] && ! ql_running && pass "red ($MODE): Space opens no Quick Look" || fail "red ($MODE): Quick Look opened ($(ql_caption))"
  shot 20-red
  info "done"
  exit 0
fi

# ---- 3. three files
dolphin_active
pfinput 'key ctrl+a' 'sleep 1.5' 'key space'
wait_caption "alpha.png (1 of 3)" 10 && pass "3: Ctrl+A and Space show the three files, the first one first ($(ql_caption))" ||
  fail "3: '$(ql_caption)'"
sleep 1
shot 30-three
pfinput 'key right'
wait_caption "beta.txt (2 of 3)" 5 && pass "3: Right shows the second file ($(ql_caption))" || fail "3: Right: '$(ql_caption)'"
# The text selected with the mouse as a user does, from the start of its first line to past the
# end of the second (111 and 127 px below the window's corner at 1440x900 and scale 1), then Ctrl+C:
# the window's Copy key (the text area keeps no focus).
read -r qx qy qw qh <<<"$(frame '— Quick Look')"
info "Quick Look's window at $qx $qy $qw $qh"
pfinput "drag $((qx + 8)) $((qy + 111)) $((qx + 600)) $((qy + 127)) 20" 'sleep 0.5' 'key ctrl+c' 'sleep 1'
shot 31-text-selected
copied=$(timeout 5 wl-paste -n 2>>"$OUT/errors.log" || true)
[ "$copied" = "$(printf 'Plasma Fusion Quick Look\nsecond line')" ] &&
  pass "3: the text selected with the mouse and Ctrl+C: on the clipboard" ||
  fail "3: the clipboard after Ctrl+C: '$copied'"
sleep 1
shot 31-text
pfinput 'key right'
wait_caption "gamma.py (3 of 3)" 5 && pass "3: Right again shows the third ($(ql_caption))" || fail "3: Right again: '$(ql_caption)'"
sleep 1
shot 32-code
pfinput 'key escape'
wait_caption "" 10 && pass "3: Esc closes it" || fail "3: Esc: '$(ql_caption)'"

# ---- 4. Space in Dolphin again on the same selection closes the preview
dolphin_active
pfinput 'key space'
wait_caption "alpha.png" 10 || fail "4: no preview to close"
dolphin_active
pfinput 'key space'
wait_caption "" 10 && pass "4: Space again in Dolphin on the same files closes the preview" || fail "4: still open: '$(ql_caption)'"

# The context menu (a look, in the screenshot): right-click on the first file, the icon view's
# first cell (219, 127 from the window's corner at 1440x900 and scale 1).
dolphin_active
geo=$(K run "var l = workspace.windowList(), g = ''; for (var i = 0; i < l.length; ++i) { if (String(l[i].resourceClass).indexOf('dolphin') >= 0 && l[i].normalWindow) { var r = l[i].frameGeometry; g = Math.round(r.x) + ' ' + Math.round(r.y); } } report(g);" |
  python3 -c 'import json, sys; print(json.load(sys.stdin))')
info "Dolphin's window at $geo"
read -r gx gy <<<"$geo"
pfinput "click $((gx + 219)) $((gy + 127)) right" 'sleep 1.5'
shot 41-context-menu
pfinput 'key escape' 'sleep 1'

# ---- 5. the restore
pkill -u "$(id -u)" -x dolphin || true
sleep 2
undo_rc=0
bash "$HOME/pf-tools/device/fusion-restore.sh" >"$OUT/restore.log" 2>&1 || undo_rc=$?
info "fusion-restore rc=$undo_rc"
[ ! -e "$RC" ] && pass "5: the restore removed Dolphin's file (there was none before)" || fail "5: the file is still there"
dolphin "$HOME/QL" >>"$OUT/dolphin.log" 2>&1 &
sleep 6
select_first
pfinput 'key space'
sleep 4
[ -z "$(ql_caption)" ] && pass "5: after the restore Space opens no Quick Look (Dolphin's own key again)" || fail "5: Quick Look opened ($(ql_caption))"
shot 50-restored
pkill -u "$(id -u)" -x dolphin || true
info "done"
