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
set -u
PLOG=$OUT/plasmashell.log
CHK=$OUT/checks.txt
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }

# The shell's own widgets through the desktop scripting; the script prints its result (the
# fusion-config.sh pattern: busctl's reply carries the print() output).
script() {
  busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "$1" 2>/dev/null |
    python3 -c 'import sys,shlex; s=sys.stdin.read().strip(); print(shlex.split(s[2:])[0] if s.startswith("s ") else "")'
}

sleep 8

# ---- The quick settings pill: a one-finger touch tap (pfinput), the sheet's own first-frame line.
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
  for _ in 1 2 3 4 5; do
    pfinput "tap $TX $TY 0.15"
    sleep 1.5
    pfinput "tap 600 700 0.15"   # outside the sheet: it closes on deactivation
    sleep 1.2
  done
  opens=$(grep -c 'quicksettings: sheet .*first frame after' "$PLOG")
  info "sheet first-frame lines: $opens"
  [ "$opens" -ge 3 ] && pass "the sheet's touch taps measured first frames ($opens)" || fail "only $opens sheet opens were measured"
  info "sheet first frames: $(grep -o 'first frame after [0-9]* ms' "$PLOG" | tail -5 | tr '\n' ' ')"
  info "sheet settled: $(grep -o 'sheet settled, [0-9]* frames in 500 ms' "$PLOG" | tail -3 | tr '\n' ' ')"
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
lopens=$(grep -c 'launcher: .*first frame after' "$PLOG")
info "launcher first-frame lines: $lopens"
[ "$lopens" -ge 2 ] && pass "the launcher's requests measured first frames ($lopens)" || fail "only $lopens launcher opens were measured"
info "launcher first frames: $(grep -o 'launcher: [a-z ]*, first frame after [0-9]* ms' "$PLOG" | tail -4 | tr '\n' ' ')"

# ---- The clipboard sheet (Meta+V, the kept page): its first frame and settle.
before=$(grep -c 'first frame after' "$PLOG")
for _ in 1 2 3; do
  pfinput 'key meta+v'
  sleep 1.5
  pfinput 'key esc'
  sleep 1
done
info "clipboard opens: $(( $(grep -c 'first frame after' "$PLOG") - before ))"
info "clipboard settles: $(grep -o 'sheet settled, [0-9]* frames in 500 ms' "$PLOG" | tail -3 | tr '\n' ' ')"
info "scenario done"
