# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Test tooling (not installed). The dock's size and window grouping (board DockSize.dc.html)
# through tests/kcmctl, against the real plasmashell with the dock of this change:
#   1. after the setup: Medium, its panel 72 px, 48 px tiles 56 px apart, magnified 62 px;
#   2. Small: the panel 60 px, 40 px tiles 47 px apart, the icon under the pointer 52 px (the
#      dock's zoomSize, and a screenshot with the third app under the pointer);
#   3. Large: the panel 78 px, 56 px tiles 68 px apart, the icon under the pointer 70 px;
#   4. two Konsole windows: one icon while grouped, with two marks under it (the window count),
#      two side by side at Konsole's pin, one mark each, when "Group an app's windows" is off, back
#      to one icon with two marks when it is on again;
#   5. Medium again.
# Each step's screenshot is for the comparison with the board. Run (make-seed.sh ... dark, PF_KCMCTL
# set; the stage holds this change's dock):
#   tools/vsession/remote.sh docksize-1 packages/kcm-cpp/tests/scenario-docksize.sh SEED 1440x900 360
exec 2>&1
set -euo pipefail
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
export OUT
info() { echo "INFO $*" >>"$OUT/checks.txt"; }
# A step that fails stops the scenario (strict mode); the reason lands in the checks.
trap 'echo "FAIL the scenario stopped at line $LINENO: $BASH_COMMAND" >>"$OUT/checks.txt"' ERR
PLOG=$OUT/plasmashell2.log

# The dock panel's height.
dock_height() {
  evaljs - <<'JS'
var ps = panels(), v = "<none>";
for (var i = 0; i < ps.length; ++i) if (ps[i].widgets("org.plasmafusion.dock").length > 0) { v = String(ps[i].height); break; }
print(v);
JS
}
# The dock's [General] key KEY set to VALUE (its test hooks).
dock_key() {
  evaljs - >/dev/null <<JS
panels().forEach(function (p) { p.widgets("org.plasmafusion.dock").forEach(function (w) { w.currentConfigGroup = ["General"]; w.writeConfig("$1", $2); }); });
JS
}
# The dock's targets report (debugAction dump-targets): its last "dock: targets" line.
targets() {
  local before
  before=$(grep -c "dock: targets" "$PLOG" || true)
  dock_key debugAction "\"dump-targets\""
  for _ in $(seq 1 20); do
    [ "$(grep -c "dock: targets" "$PLOG" || true)" -gt "$before" ] && break
    sleep 0.25
  done
  grep "dock: targets" "$PLOG" | tail -1
}
# From a targets line: the tile, the magnified size (the dock's zoomSize: the size it gives the
# icon under the pointer, within its headroom), the distance from Start to Search (tile + gap),
# the number of Konsole icons and their rows.
tile_of() { sed -n 's/.* tile=\([0-9]*\) .*/\1/p' <<<"$1"; }
zoom_of() { sed -n 's/.* zoom=\([0-9]*\) .*/\1/p' <<<"$1"; }
step_of() {
  local s q
  s=$(grep -o 'Start@[0-9-]*,' <<<"$1" | head -1 | tr -dc '0-9-')
  q=$(grep -o 'Search@[0-9-]*,' <<<"$1" | head -1 | tr -dc '0-9-')
  echo $((q - s))
}
konsoles() { grep -o 'task[0-9]*-[^@ ]*konsole[^@ ]*@' <<<"$1" | wc -l; }
konsole_rows() { grep -o 'task[0-9]*-[^@ ]*konsole' <<<"$1" | sed 's/task\([0-9]*\)-.*/\1/' | tr '\n' ' ' | sed 's/ $//'; }
# The marks under each Konsole icon (the "|N" of its entry), space-separated.
konsole_marks() { grep -o 'task[0-9]*-[^@ ]*konsole[^@ ]*@' <<<"$1" | sed -n 's/.*|\([0-9]*\)@$/\1/p' | tr '\n' ' ' | sed 's/ $//'; }

# Every window whose resource class contains CLASS small at the top of the screen, side by side,
# so the dock (it dodges windows) shows for the screenshot.
place_top() {
  local js=$PFV/placetop-$$.js
  cat >"$js" <<JS
var x = 60;
for (const w of workspace.windowList()) {
    if (w.normalWindow && String(w.resourceClass).indexOf("$1") >= 0) {
        w.setMaximize(false, false);
        w.frameGeometry = { x: x, y: 80, width: 560, height: 360 };
        x += 600;
    }
}
JS
  qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript pfdsplace >/dev/null 2>&1
  local id
  id=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$js" pfdsplace)
  qdbus org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null 2>&1
  sleep 1
  qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript pfdsplace >/dev/null 2>&1
}

fusion_setup
check "setup: Medium, its panel 72 px" "$(wkey org.plasmafusion.dock dockSize)|$(dock_height)" "|72"
t=$(targets)
check "  48 px tiles, 56 px from Start to Search, magnified 62 px" "$(tile_of "$t") $(step_of "$t") $(zoom_of "$t")" "48 56 62"
shot d00-medium

# 2. Small.
kcm <<'K'
waitshell
get dockSize
set dockSize 0
save
wait 1500
get errorText
K
sleep 2
check "Small: the key and its 60 px panel" "$(wkey org.plasmafusion.dock dockSize) $(dock_height)" "0 60"
check "Small: no error" "$(lastget errorText)" ""
t=$(targets)
check "  40 px tiles, 47 px from Start to Search, magnified 52 px" "$(tile_of "$t") $(step_of "$t") $(zoom_of "$t")" "40 47 52"
shot d01-small
dock_key debugHoverIndex 2
sleep 1.5
shot d02-small-magnified
dock_key debugHoverIndex -1

# 3. Large.
kcm <<'K'
waitshell
set dockSize 2
save
wait 1500
get errorText
K
sleep 2
check "Large: the key and its 78 px panel" "$(wkey org.plasmafusion.dock dockSize) $(dock_height)" "2 78"
check "Large: no error" "$(lastget errorText)" ""
t=$(targets)
check "  56 px tiles, 68 px from Start to Search, magnified 70 px" "$(tile_of "$t") $(step_of "$t") $(zoom_of "$t")" "56 68 70"
dock_key debugHoverIndex 2
sleep 1.5
shot d03-large-magnified
dock_key debugHoverIndex -1

# 4. Window grouping, at Medium (the board's grouping row).
kcm <<'K'
waitshell
set dockSize 1
save
wait 1500
K
konsole >"$OUT/konsole1.log" 2>&1 &
sleep 3
konsole >"$OUT/konsole2.log" 2>&1 &
sleep 4
place_top konsole
sleep 2
t=$(targets)
check "grouped: Konsole's two windows share one icon" "$(konsoles "$t")" 1
check "  with two marks under it" "$(konsole_marks "$t")" 2
shot d04-grouped
kcm <<'K'
waitshell
get groupWindows
set groupWindows false
save
wait 1500
get errorText
K
sleep 3
check "off: the key" "$(wkey org.plasmafusion.dock groupWindows)" false
t=$(targets)
rows=$(konsole_rows "$t")
check "  one icon for each window" "$(konsoles "$t")" 2
check "  one mark each" "$(konsole_marks "$t")" "1 1"
check "  side by side (rows next to each other)" "$(awk '{print ($2 - $1)}' <<<"$rows")" 1
check "  no error" "$(lastget errorText)" ""
shot d05-ungrouped
kcm <<'K'
waitshell
set groupWindows true
save
wait 1500
K
sleep 3
t=$(targets)
check "on again: one icon" "$(konsoles "$t")" 1
check "  two marks again" "$(konsole_marks "$t")" 2

# 5. Medium again (the setup's).
check "back to Medium: its 72 px panel" "$(wkey org.plasmafusion.dock dockSize) $(dock_height)" "1 72"
shot d06-medium-again
info "done"
# A failed check fails the scenario (scenario rc), as the KWin scenarios do.
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$OUT/checks.txt" || true)" = 0 ]
