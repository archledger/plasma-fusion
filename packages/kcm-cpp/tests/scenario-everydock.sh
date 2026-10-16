# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Test tooling (not installed). "Dock on every screen" on and off with two screens, through
# tests/kcmctl, against the real plasmashell and the layout part's ensure-topbars.js:
#   1. after the setup: one dock, on screen 0, listing every screen's windows;
#   2. on: a dock on each screen; the new one is a copy with a launcher of its own, and both list
#      only their own screen's windows;
#   3. off: the copy's panel goes, and the dock left lists every screen's windows again.
# Run with PFV_OUTPUTS=2 (make-seed.sh ... dark, PF_KCMCTL set; the stage holds this change's
# look-and-feel part):
#   PFV_OUTPUTS=2 tools/vsession/remote.sh ed-1 packages/kcm-cpp/tests/scenario-everydock.sh SEED 1440x900 300
exec 2>&1
set -euo pipefail
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
export OUT
info() { echo "INFO $*" >>"$OUT/checks.txt"; }
# A step that fails stops the scenario (strict mode); the reason lands in the checks.
trap 'echo "FAIL the scenario stopped at line $LINENO: $BASH_COMMAND" >>"$OUT/checks.txt"' ERR
# The dock panels: "screenN:LOCATION:copy|own:only|all[:launcher]" each, in panel order.
docks() {
  evaljs - <<'JS'
var ps = panels(), out = [];
for (var i = 0; i < ps.length; ++i) {
    var ds = ps[i].widgets("org.plasmafusion.dock");
    if (ds.length === 0) continue;
    var d = ds[0];
    d.currentConfigGroup = ["PlasmaFusion"];
    var copy = String(d.readConfig("everyScreenCopy", "")) === "true";
    d.currentConfigGroup = ["General"];
    var only = String(d.readConfig("showOnlyCurrentScreen", "false")) === "true";
    d.currentConfigGroup = [];
    out.push("screen" + ps[i].screen + ":" + ps[i].location + ":" + (copy ? "copy" : "own") + ":" + (only ? "only" : "all")
             + (ps[i].widgets("org.plasmafusion.launcher").length > 0 ? ":launcher" : ""));
}
print(out.join(" "));
JS
}

fusion_setup
info "screens: $(evaljs - <<<'print(screenCount);')"
check "setup: one dock, on screen 0, every screen's windows" "$(docks)" "screen0:bottom:own:all:launcher"
shot e00-one-dock

# 2. On.
kcm <<'K'
waitshell
get everyDock
set everyDock true
save
wait 1500
get errorText
K
sleep 3
check "on: the key" "$(ck plasmafusionrc Dock EveryScreen)" true
check "on: a dock on each screen, the new one a copy with its launcher, both their own screen only" \
  "$(docks)" "screen0:bottom:own:only:launcher screen1:bottom:copy:only:launcher"
check "on: no error" "$(lastget errorText)" ""
shot e01-every-dock

# 3. Off.
kcm <<'K'
waitshell
set everyDock false
save
wait 1500
get errorText
K
sleep 3
check "off: the key" "$(ck plasmafusionrc Dock EveryScreen)" false
check "off: the copy's panel is gone, the dock left lists every screen's windows" "$(docks)" "screen0:bottom:own:all:launcher"
check "off: no error" "$(lastget errorText)" ""
shot e02-one-dock-again
info "done"
# A failed check fails the scenario (scenario rc), as the KWin scenarios do.
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$OUT/checks.txt" || true)" = 0 ]
