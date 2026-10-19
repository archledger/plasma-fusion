#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Saved app pairs with two screens and a dock on each (docs/parts/apppairs.md, "Opening"), where
# every dock lists only its own screen's windows (ensure-topbars.js, showOnlyCurrentScreen):
#   1. "Dock on every screen" on: two docks, each listing only its own screen's windows;
#   2. KWrite open on the second screen, Dolphin not running;
#   3. the first screen's dock asked to open Dolphin | KWrite (its pairRequest, as the home screen
#      writes it): Dolphin is started on the left half of the first screen and KWrite comes over
#      from the second screen to its right half;
# and no QML errors from the dock.
# Run with PFV_OUTPUTS=2 (seed: make-seed.sh, the navigation effect not needed):
#   PFV_OUTPUTS=2 tools/vsession/remote.sh aps-1 packages/apppairs/tests/vsession/scenario-apppairs-screens.sh SEED 1440x900 420
exec 2>&1
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
PLOG=$OUT/plasmashell.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }
# The two apps and the screens: JSON {screens: [[x, y, w, h]...], dolphin: [x, y, w, h] | null, kwrite: ...}
where() {
  K run "var l = workspace.windowList(), out = {screens: [], dolphin: null, kwrite: null};
    for (var s = 0; s < workspace.screens.length; ++s) { var g = workspace.screens[s].geometry; out.screens.push([g.x, g.y, g.width, g.height]); }
    for (var i = 0; i < l.length; ++i) { var c = l[i]; if (!c.normalWindow || c.minimized) { continue; } var f = c.frameGeometry;
      if (String(c.resourceClass).indexOf('dolphin') >= 0) { out.dolphin = [f.x, f.y, f.width, f.height]; }
      if (String(c.resourceClass).indexOf('kwrite') >= 0) { out.kwrite = [f.x, f.y, f.width, f.height]; } }
    report(out);" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)))'
}

bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || info "fusion-config rc=$?"
kwriteconfig6 --file kwinrc --group Script-plasmafusion-snap --key Gap 6
kwriteconfig6 --file plasmafusionrc --group Dock --key EveryScreen true
pfv_restart_shell 12
qdbus org.kde.KWin /KWin reconfigure; sleep 3

# ---- 1. a dock on every screen
lnf=$(find "$HOME/.local/share/plasma/look-and-feel" "$HOME/pf-stage/.local/share/plasma/look-and-feel" -path '*org.plasmafusion.dark.desktop/contents/layouts/ensure-topbars.js' 2>/dev/null | head -n 1)
evaljs "$lnf" >"$OUT/ensure.log" 2>&1 || info "ensure-topbars rc=$?"
sleep 4
docks=$(evaljs - <<'JS'
var ps = panels(), out = [];
for (var i = 0; i < ps.length; ++i) {
    var ds = ps[i].widgets("org.plasmafusion.dock");
    if (ds.length === 0) continue;
    ds[0].currentConfigGroup = ["General"];
    out.push("screen" + ps[i].screen + ":" + (String(ds[0].readConfig("showOnlyCurrentScreen", "false")) === "true" ? "only" : "all"));
}
print(out.join(" "));
JS
)
info "docks: $docks ($(grep -a 'docks:' "$OUT/ensure.log" | tail -n 1))"
case "$docks" in *screen0:only*screen1:only* | *screen1:only*screen0:only*) pass "1: a dock on each screen, each listing its own screen's windows: $docks" ;;
  *) fail "1: docks: $docks" ;; esac

# ---- 2. KWrite on the second screen
kwrite >/dev/null 2>&1 &
sleep 4
K run "var l = workspace.windowList(); for (var i = 0; i < l.length; ++i) { var c = l[i];
  if (c.normalWindow && String(c.resourceClass).indexOf('kwrite') >= 0) { workspace.sendClientToScreen(c, workspace.screens[1]); } } report(1);" >/dev/null
sleep 2
w=$(where)
info "2: $w"
if python3 -c 'import json,sys; d = json.loads(sys.argv[1]); s = d["screens"][1]; k = d["kwrite"]; sys.exit(0 if k and s[0] <= k[0] < s[0] + s[2] and d["dolphin"] is None else 1)' "$w"; then
  pass "2: KWrite on the second screen, Dolphin not running"
else
  fail "2: $w"
fi

# ---- 3. the first screen's dock opens Dolphin | KWrite
before=$(grep -ac 'dock: pair:' "$PLOG" || true)
evaljs - >/dev/null <<'JS'
panels().forEach(function (p) { if (p.screen !== 0) return; p.widgets("org.plasmafusion.dock").forEach(function (w) {
    w.currentConfigGroup = ["General"]; w.writeConfig("pairRequest", Date.now() + ":org.kde.dolphin.desktop:org.kde.kwrite.desktop:0.5"); }); });
JS
sleep 12
w=$(where)
info "3: $w"
if [ "$(grep -ac 'dock: pair:' "$PLOG" || true)" -gt "$before" ]; then pass "3: the first screen's dock took the request"; else fail "3: no dock took the pair request"; fi
if python3 - "$w" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
s = d["screens"][0]
dl, kw = d["dolphin"], d["kwrite"]
on0 = lambda g: g is not None and s[0] <= g[0] and g[0] + g[2] <= s[0] + s[2] + 1
half = s[2] / 2
ok = on0(dl) and on0(kw) and abs(dl[0] - s[0]) <= 16 and dl[0] < kw[0] and abs(kw[0] + kw[2] - (s[0] + s[2])) <= 16 \
    and abs(dl[0] + dl[2] - (s[0] + half)) <= 20
sys.exit(0 if ok else 1)
PY
then
  pass "3: Dolphin on the left half and KWrite, come from the second screen, on the right half of the first screen"
else
  fail "3: not side by side on the first screen: $w"
fi

errs=$( { grep -aE 'org\.plasmafusion\.dock' "$PLOG" || true; } | grep -aiE 'error|TypeError|ReferenceError|is not defined|Cannot' || true)
if [ -z "$errs" ]; then pass "no QML errors from the dock"; else fail "dock: $(echo "$errs" | head -3 | tr '\n' ' ')"; fi
info "done"
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$CHK" || true)" = 0 ]
