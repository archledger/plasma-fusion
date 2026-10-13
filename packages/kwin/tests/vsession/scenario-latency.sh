#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The touch path's latency re-run (survey item 6, 2026-10-13): the quick settings pill's touch tap
# to the sheet's first frame - the widget's own line, which is the input-to-visual number the
# 2026-10-12 audit could not take - the launcher by its request (the same path the audit's 75-91 ms
# came from), and the clipboard sheet by Meta+V (the kept page, PR #33); each a few times.
# Run on the ThinkPad with a fusion-config seed (the KWIN-2 recipe):
#   tools/vsession/remote.sh lat-1 packages/kwin/tests/vsession/scenario-latency.sh SEED 1920x1200 300
set -euo pipefail
PLOG=$OUT/plasmashell.log
CHK=$OUT/checks.txt
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }

# The shell's own widgets through the desktop scripting; the script prints its result (the
# fusion-config.sh pattern: busctl's reply carries the print() output).
script() {
  # A failed call is the caller's to notice (its section fails): tolerate it here.
  busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$1" 2>/dev/null |
    python3 -c 'import sys,shlex; s=sys.stdin.read().strip(); print(shlex.split(s[2:])[0] if s.startswith("s ") else "")' || true
}

# The Fusion layout first (the KWIN-2 recipe): without it the session keeps the seed's stock
# panels, the launcher applet does not exist and the pill sits in a different bar.
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1
info "fusion-config rc=$?"
pfv_restart_shell 12
sleep 6

# ---- The quick settings pill: a pointer click and a one-finger touch tap (pfinput), the sheet's
# own first-frame line each.
pill=$(script '
var ps = panels();
for (var p = 0; p < ps.length; ++p) {
    var ws = ps[p].widgets();
    for (var w = 0; w < ws.length; ++w) {
        if (ws[w].type === "org.plasmafusion.quicksettings") {
            var g = ws[w].geometry;
            print(JSON.stringify({x: g.x, y: g.y, width: g.width, height: g.height}));
        }
    }
}')
info "quick settings pill: ${pill:-not found}"
if [ -n "$pill" ]; then
  read -r PX PY PW PH <<<"$(python3 -c "import json,sys; g=json.loads(sys.argv[1]); print(int(g['x']), int(g['y']), int(g['width']), int(g['height']))" "$pill")"
  TX=$((PX + PW / 2)); TY=$((PY + PH / 2))
  info "pill centre: $TX $TY"
  for _ in 1 2 3; do
    pfinput "click $TX $TY left"
    sleep 1.5
    pfinput "click 600 700 left"   # outside the sheet: it closes on deactivation
    sleep 1.2
  done
  clicks=$(grep -c 'quicksettings: sheet .*first frame after' "$PLOG" || true)
  info "sheet first-frame lines after clicks: $clicks"
  [ "$clicks" -ge 2 ] && pass "the sheet's pointer clicks measured first frames ($clicks)" || fail "only $clicks sheet opens by click were measured"
  for _ in 1 2 3; do
    pfinput "tap $TX $TY 0.15"
    sleep 1.5
    pfinput "tap 600 700 0.15"   # outside the sheet: it closes on deactivation
    sleep 1.2
  done
  opens=$(grep -c 'quicksettings: sheet .*first frame after' "$PLOG" || true)
  info "sheet first-frame lines after taps: $opens"
  [ "$opens" -gt "$clicks" ] && pass "the sheet's touch taps measured first frames ($((opens - clicks)))" || fail "the touch taps added no sheet opens"
  info "sheet first frames: $(grep -o 'first frame after [0-9]* ms' "$PLOG" | tail -5 | tr '\n' ' ' || true)"
  info "sheet settled: $(grep -o 'sheet settled, [0-9]* frames in 500 ms' "$PLOG" | tail -3 | tr '\n' ' ' || true)"
else
  fail "the quick settings pill's geometry was not found"
fi

# ---- The launcher by its request (the audit's path), then Escape.
for _ in 1 2 3; do
  # The launcher is a desktop widget, not a panel one (the dock's icon is the dock's own).
  script '
var ds = desktops(), ps = panels(), out = 0;
for (var d = 0; d < ds.length; ++d) {
    var ws = ds[d].widgets();
    for (var w = 0; w < ws.length; ++w) {
        if (ws[w].type === "org.plasmafusion.launcher") {
            ws[w].currentConfigGroup = ["General"];
            ws[w].writeConfig("openRequest", "home:" + Date.now());
            out++;
        }
    }
}
for (var p = 0; p < ps.length; ++p) {
    var pw = ps[p].widgets();
    for (var q = 0; q < pw.length; ++q) {
        if (pw[q].type === "org.plasmafusion.launcher") {
            pw[q].currentConfigGroup = ["General"];
            pw[q].writeConfig("openRequest", "home:" + Date.now());
            out++;
        }
    }
}
print("launchers: " + out);' >>"$CHK"
  sleep 1.5
  pfinput 'key esc'
  sleep 1
done
lopens=$(grep -c 'launcher: .*first frame after' "$PLOG" || true)
info "launcher first-frame lines: $lopens"
[ "$lopens" -ge 2 ] && pass "the launcher's requests measured first frames ($lopens)" || fail "only $lopens launcher opens were measured"
info "launcher first frames: $(grep -o 'launcher: [a-z ]*, first frame after [0-9]* ms' "$PLOG" | tail -4 | tr '\n' ' ' || true)"

# ---- The clipboard sheet (Meta+V, the kept page): its first frame and settle.
before=$(grep -c 'first frame after' "$PLOG" || true)
for _ in 1 2 3; do
  pfinput 'key meta+v'
  sleep 1.5
  pfinput 'key esc'
  sleep 1
done
copens=$(( $(grep -c 'first frame after' "$PLOG" || true) - before ))
info "clipboard opens: $copens"
[ "$copens" -ge 1 ] && pass "the clipboard sheet's Meta+V opens were measured ($copens)" \
  || fail "only $copens clipboard opens were measured"
info "clipboard settles: $(grep -o 'sheet settled, [0-9]* frames in 500 ms' "$PLOG" | tail -3 | tr '\n' ' ' || true)"
info "scenario done"
