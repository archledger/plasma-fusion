# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Test tooling (not installed). The dock on the left or right (board DockPosition.dc.html) through
# tests/kcmctl, against the real plasmashell with the dock, launcher and Plasma style of this
# change, at 1440x900:
#   1. after the setup: the dock at the bottom;
#   2. Left: the panel on the left; the row upright (Start and Search 56 px apart down the same
#      column), 16 px from the screen's edge, centred on the screen's height (the compositor's
#      place for a panel that reserves no room) and clear of the top bar; magnified 62 px; the
#      launcher's card 8 px beside the plate, centred on the dock; the name pill of the app under
#      the pointer 12 px beside its magnified icon, centred on it;
#   3. Right: the same mirrored (the plate 16 px from the right edge, the card 8 px left of it);
#   4. Bottom again: the row where the setup had it.
# Each step's screenshot is for the comparison with the board. Run (make-seed.sh ... dark,
# PF_KCMCTL set; the stage holds this change's dock, launcher and Plasma style):
#   tools/vsession/remote.sh dockedge-1 packages/kcm-cpp/tests/scenario-dockedge.sh SEED 1440x900 420
exec 2>&1
set -euo pipefail
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
export OUT
info() { echo "INFO $*" >>"$OUT/checks.txt"; }
# A step that fails stops the scenario (strict mode); the reason lands in the checks.
trap 'echo "FAIL the scenario stopped at line $LINENO: $BASH_COMMAND" >>"$OUT/checks.txt"' ERR
PLOG=$OUT/plasmashell2.log

# The dock panel's location.
dock_location() {
  evaljs - <<'JS'
var ps = panels(), v = "<none>";
for (var i = 0; i < ps.length; ++i) if (ps[i].widgets("org.plasmafusion.dock").length > 0) { v = String(ps[i].location); break; }
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
# From a targets line: the edge, the magnified size, and NAME's global x and y ("x y").
edge_of() { sed -n 's/.* edge=\([a-z]*\) .*/\1/p' <<<"$1"; }
zoom_of() { sed -n 's/.* zoom=\([0-9]*\) .*/\1/p' <<<"$1"; }
at_of() { grep -o "$2@[0-9-]*,[0-9-]*" <<<"$1" | head -1 | sed 's/.*@//; s/,/ /'; }
# The launcher's card after it opened: "X Y W H" from its log.
card() {
  local before
  before=$(grep -c "launcher: frames .*open true, card" "$PLOG" || true)
  dock_key debugAction "\"start\""
  sleep 2
  # the launcher's testing hook: its card's place in the log
  evaljs - >/dev/null <<'JS'
panels().forEach(function (p) { p.widgets("org.plasmafusion.launcher").forEach(function (w) { w.currentConfigGroup = ["General"]; w.writeConfig("openRequest", "frames:" + Date.now()); }); });
JS
  for _ in $(seq 1 40); do
    [ "$(grep -c "launcher: frames .*open true, card" "$PLOG" || true)" -gt "$before" ] && break
    sleep 0.25
  done
  { grep "launcher: frames .*open true, card" "$PLOG" || true; } | tail -1 | sed -n 's/.*card \([0-9-]*\),\([0-9-]*\) \([0-9]*\)x\([0-9]*\).*/\1 \2 \3 \4/p'
}
close_launcher() { dock_key debugAction "\"start\""; sleep 1.5; }
set_position() {
  kcm <<K
waitshell
set dockPosition $1
save
wait 2500
get errorText
K
  sleep 3
}
# The checks for the dock on SIDE (left or right): PLATE_X is where its plate starts.
side_checks() {
  local side=$1 plate_x=$2 t start search trash sx sy qx qy ty top bottom c cx cy cw ch px py pw ph kx ky kh
  check "$side: the panel" "$(dock_location)" "$side"
  check "$side: no error" "$(lastget errorText)" ""
  t=$(targets)
  start=$(at_of "$t" Start); search=$(at_of "$t" Search); trash=$(at_of "$t" Trash)
  read -r sx sy <<<"$start"; read -r qx qy <<<"$search"; read -r _ ty <<<"$trash"
  check "  the dock lays out for the $side edge, magnified 62 px" "$(edge_of "$t") $(zoom_of "$t")" "$side 62"
  check "  upright: Search 56 px below Start in the same column" "$((qx - sx)) $((qy - sy))" "0 56"
  check "  the plate 16 px from the screen's edge" "$sx" "$plate_x"
  # centred on the screen's height (Start's top and Trash's bottom: the row's ends), the plate
  # (12 px past the row's ends) clear of the 34 px top bar
  top=$sy; bottom=$((900 - ty - 48))
  check "  centred on the screen's height (within 2 px: $top above, $bottom below)" \
    "$([ $((top - bottom)) -le 2 ] && [ $((bottom - top)) -le 2 ] && echo yes || echo no)" yes
  check "  the plate clear of the top bar" "$([ $((sy - 12)) -ge 34 ] && echo yes || echo no)" yes
  shot "e-$side"
  dock_key debugHoverIndex 2
  sleep 1.5
  t=$(targets)
  read -r px py pw ph <<<"$(grep -o 'pill@[0-9-]*,[0-9-]*:[0-9]*x[0-9]*' <<<"$t" | sed 's/pill@//; s/[,:x]/ /g')"
  # task 2's place and its icon's rest size (the icons shrink when the apps do not fit)
  read -r kx ky kh <<<"$(grep -o 'task2-[^@ ]*@[0-9-]*,[0-9-]*:[0-9]*x[0-9]*' <<<"$t" | sed 's/.*@//; s/[,:]/ /g; s/ [0-9]*x/ /')"
  info "$side: pill $px,$py ${pw}x$ph, task2 at $kx,$ky, its icon $kh px"
  # the magnified icon: 62 px (zoom), 14 px from the plate's edge side (Medium); the pill 12 px
  # beside it
  if [ "$side" = left ]; then
    check "  the name pill 12 px beside the magnified icon (within 2 px)" \
      "$(d=$((px - (plate_x + 14 + 62 + 12))); [ "${d#-}" -le 2 ] && echo yes || echo no)" yes
  else
    check "  the name pill 12 px beside the magnified icon (within 2 px)" \
      "$(d=$((px + pw - (plate_x + 72 - 14 - 62 - 12))); [ "${d#-}" -le 2 ] && echo yes || echo no)" yes
  fi
  check "  centred on the icon (within 3 px)" \
    "$(d=$(( (2 * py + ph) - (2 * ky + kh) )); [ "${d#-}" -le 6 ] && echo yes || echo no)" yes
  shot "e-$side-hover"
  dock_key debugHoverIndex -1
  sleep 1
  c=$(card)
  read -r cx cy cw ch <<<"$c"
  info "$side: launcher card $c"
  if [ "$side" = left ]; then
    check "  the launcher's card 8 px beside the plate" "$cx" "$((plate_x + 72 + 8))"
  else
    check "  the launcher's card 8 px beside the plate" "$((cx + cw))" "$((plate_x - 8))"
  fi
  check "  centred on the dock (within 2 px)" \
    "$(d=$(( (2 * cy + ch) - (sy + ty + 48) )); [ "${d#-}" -le 4 ] && echo yes || echo no)" yes
  shot "e-$side-launcher"
  close_launcher
}

fusion_setup
check "setup: the dock at the bottom" "$(dock_location)" bottom
t=$(targets)
check "  laid out for the bottom" "$(edge_of "$t")" bottom
setup_start=$(at_of "$t" Start)
shot e-bottom

set_position 1
side_checks left 16
set_position 2
side_checks right 1352

set_position 0
check "Bottom again: the panel" "$(dock_location)" bottom
t=$(targets)
check "  the row where the setup had it" "$(edge_of "$t") $(at_of "$t" Start)" "bottom $setup_start"
shot e-bottom-again
info "done"
# A failed check fails the scenario (scenario rc), as the KWin scenarios do.
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$OUT/checks.txt" || true)" = 0 ]
