# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Test tooling (not installed). The top bar hidden and the island (board Island.dc.html) through
# tests/kcmctl, against the real plasmashell and KWin with the stage of this change (live chips,
# the tablet KWin script, the layout scripts), at 1440x900:
#   1. after the setup: the bar shows;
#   2. "Hide the top bar automatically" on: the bar's panel hides, KWin hides its window, the
#      tablet script tells the live chips (barHidden); the harness's own SSH login (it reaches
#      the host over SSH) is in the island, its blue dot;
#   3. screen sharing (the portal's item, fake_status_items.py): the island, compact, 4 px from the
#      top and centred on the screen;
#   4. opened (the widget's islandRequest, as a click), 400 px wide and still centred; closed;
#   5. a recording too: the bubble 6 px beside the island, the island still centred;
#   6. the pointer pushed against the top of the screen (KWin pushes it back once, then shows the
#      bar after its activation delay): the bar shows, the island goes; the pointer away: the bar
#      hides again, the island is back;
#   7. tablet posture: the bar shows, no island; laptop again: hidden, the island back;
#   8. off: the bar shows again, no island.
# Each step's screenshot is for the comparison with the board. The seed (make-seed.sh ... dark,
# PF_KCMCTL set) also holds ~/pf-chips/fake_status_items.py, and its .config/pfv-env sets
# QT_LOGGING_RULES=org.plasmafusion.livechips.debug=true. Run:
#   tools/vsession/remote.sh island-1 packages/kcm-cpp/tests/scenario-island.sh SEED 1440x900 480
exec 2>&1
set -euo pipefail
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
export OUT
info() { echo "INFO $*" >>"$OUT/checks.txt"; }
trap 'echo "FAIL the scenario stopped at line $LINENO: $BASH_COMMAND" >>"$OUT/checks.txt"' ERR
PLOG=$OUT/plasmashell2.log
FAKE=$HOME/pf-chips/fake_status_items.py
FAKES=()

# The first top bar's hiding (the panel with the app name).
top_hiding() {
  evaljs - <<'JS'
var ps = panels(), v = "<none>";
for (var i = 0; i < ps.length; ++i) if (ps[i].widgets("org.plasmafusion.appname").length > 0) { v = String(ps[i].hiding); break; }
print(v);
JS
}
# The live chips' [General] KEY set to VALUE (their test hooks).
chips_key() {
  evaljs - >/dev/null <<JS
panels().forEach(function (p) { p.widgets("org.plasmafusion.livechips").forEach(function (w) { w.currentConfigGroup = ["General"]; w.writeConfig("$1", $2); }); });
JS
}
# The island's last report ("compact privacy at X,Y WxH; bubble ..." or "none").
island() { { grep -a "livechips: island " "$PLOG" || true; } | grep -av "islandRequest" | tail -1 | sed 's/.*livechips: island //'; }
# Until the island's last report matches PATTERN (SECONDS): 0, else 1.
wait_island() {
  local i
  for ((i = 0; i < $2 * 4; i++)); do
    island | grep -qE "$1" && return 0
    sleep 0.25
  done
  return 1
}
# X Y W H of the island's shape, and BX BW of the bubble, from a report.
shape() { sed -n 's/.* at \([0-9-]*\),\([0-9-]*\) \([0-9]*\)x\([0-9]*\).*/\1 \2 \3 \4/p' <<<"$1"; }
# X Y W H of the island's window (its QWindow geometry: what KWin configured).
win() { sed -n 's/.*; window \([0-9-]*\),\([0-9-]*\) \([0-9]*\)x\([0-9]*\).*/\1 \2 \3 \4/p' <<<"$1"; }
bubble() { sed -n 's/.*; bubble \([0-9-]*\),[0-9-]* \([0-9]*\)x[0-9]*.*/\1 \2/p' <<<"$1"; }
centred() { local x y w h; read -r x y w h <<<"$(shape "$1")"; [ $((2 * x + w - 1440)) -le 2 ] && [ $((1440 - 2 * x - w)) -le 2 ] && echo yes || echo no; }
set_hide() {
  kcm <<K
waitshell
set topBarAutoHide $1
save
wait 2500
get errorText
K
  sleep 3
}
# The tablet script's last word on the bars (KWin's log).
bars() { { grep -a "plasmafusion-tablet: top bars" "$OUT/kwin.log" || true; } | tail -1 | sed 's/.*top bars //'; }
wait_bars() {
  local i
  for ((i = 0; i < $2 * 4; i++)); do
    bars | grep -qF "$1" && return 0
    sleep 0.25
  done
  return 1
}

fusion_setup
pfinput "move 720 450"
check "setup: the top bar shows" "$(top_hiding)" none
shot i-setup

set_hide true
check "on: the top bar's panel hides" "$(top_hiding)" autohide
check "  no error" "$(lastget errorText)" ""
check "  KWin hid its window and the tablet script told the chips" \
  "$(wait_bars '"hidden":true' 15 && echo yes || echo no) $(wkey org.plasmafusion.livechips barHidden)" "yes true"
info "bars: $(bars)"
wait_island "^compact privacy at" 10 || true
check "  the harness's SSH login: the island, compact" "$(island | cut -d' ' -f1-2)" "compact privacy"
shot i-hidden

python3 "$FAKE" screen Firefox screen >"$OUT/fake-screen.log" 2>&1 &
FAKES+=($!)
wait_island "^compact privacy at" 15 || true
r=$(island)
info "screen sharing: $r"
read -r x y w h <<<"$(shape "$r")"
check "screen sharing: the island, compact" "$(cut -d' ' -f1-2 <<<"$r")" "compact privacy"
check "  4 px from the top" "${y:-}" 4
check "  centred on the screen" "$(centred "$r")" yes
shot i-compact

chips_key islandRequest "\"open:$(date +%s%N)\""
wait_island "opened privacy" 10 || true
r=$(island)
info "opened: $r"
read -r x y w h <<<"$(shape "$r")"
check "opened in place: wider, still at the top and centred" \
  "$([ "${w:-0}" -ge 360 ] && echo wide) ${y:-} $(centred "$r")" "wide 4 yes"
read -r wx wy ww wh <<<"$(win "$r")"
check "  its window holds it (the size KWin configured)" \
  "$([ "${wx:-9999}" -le "${x:-0}" ] && [ $((${wx:-0} + ${ww:-0})) -ge $((${x:-0} + ${w:-0})) ] && [ "${wh:-0}" -ge "${h:-1}" ] && echo yes || echo no)" yes
shot i-opened
chips_key islandRequest "\"close:$(date +%s%N)\""
wait_island "^compact privacy at" 10 || true
check "  closed: compact again" "$(island | cut -d' ' -f1-2)" "compact privacy"

python3 "$FAKE" recording 120 >"$OUT/fake-recording.log" 2>&1 &
FAKES+=($!)
wait_island "privacy,recording .*; bubble" 15 || true
r=$(island)
info "two at once: $r"
read -r x y w h <<<"$(shape "$r")"
read -r bx bw <<<"$(bubble "$r")"
check "a recording too: the bubble 6 px beside the island" "$((${bx:-0} - ${x:-0} - ${w:-0}))" 6
check "  the island still centred" "$(centred "$r")" yes
shot i-two

# The pointer pushed against the top edge: KWin shows the bar (its auto-hide screen edge; the
# first touch only pushes the pointer back, and the next must come 75 to 350 ms later, KWin
# 6.7.5 Edge::check with ElectricBorderDelay 75 and ElectricBorderCooldown 350): one pfinput run.
pfinput "move 720 0" "sleep 0.15" "move 720 0" "sleep 0.15" "move 720 0" "sleep 0.15" "move 720 0"
check "the pointer at the top: KWin shows the bar" "$(wait_bars '"hidden":false' 10 && echo shown || echo hidden)" shown
check "  the island goes" "$(wait_island '^none' 10 && echo none || island)" none
shot i-bar
# Down through the bar and away (the bar sees the pointer come and go, as with a person's).
pfinput "move 720 8" "sleep 0.1" "move 720 20" "sleep 0.1" "move 720 60" "sleep 0.1" "move 720 500"
check "the pointer away: the bar hides again" "$(wait_bars '"hidden":true' 15 && echo hidden || echo shown)" hidden
check "  the island is back" "$(wait_island '^compact' 10 && echo back || island)" back

pfv_tablet on
sleep 6
check "tablet posture: the bar always shows, no island" \
  "$(top_hiding) $(wait_island '^none' 10 && echo none || island)" "none none"
shot i-tablet
pfv_tablet off
sleep 6
check "laptop again: the bar hides, the island is back" \
  "$(top_hiding) $(wait_bars '"hidden":true' 15 && echo hidden || echo shown) $(wait_island '^compact' 10 && echo back || island)" \
  "autohide hidden back"

set_hide false
check "off: the bar shows" "$(top_hiding) $(wait_bars '"hidden":false' 10 && echo shown || echo hidden)" "none shown"
check "  no island" "$(wait_island '^none' 10 && echo none || island)" none
shot i-off

for pid in "${FAKES[@]}"; do kill "$pid" 2>/dev/null || true; done
info "done"
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$OUT/checks.txt" || true)" = 0 ]
