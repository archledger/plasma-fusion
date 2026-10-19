#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Title bars after tablet posture (docs/parts/kwin-tablet.md "Windows opened in tablet posture get
# their title bar back"): windows opened in tablet posture, so maximized and borderless as they
# appear, in a private session:
#   1. Dolphin taken out of full screen (it takes a half);
#   2. KWrite quick-tiled out of full screen (the dock's and the pill's split);
#   3. Konsole quick-tiled and taken out of its tile again (it floats);
#   4. KCalc, which an "apply initially" no-titlebar rule makes borderless as it appears (KWin
#      shows its bar again on the un-maximize), and KCharSelect, which a forced one keeps
#      borderless: both quick-tiled out of full screen, then out of their tiles. KCalc's rule is a
#      system-wide one (the session's XDG config directory ~/.config/kdedefaults, read as KWin reads
#      /etc/xdg), listed in the user's rules as the KCM saves them beside one of their own;
# after leaving tablet posture Dolphin, KWrite and Konsole have their title bars again, and KCalc
# and KCharSelect still have none.
# Run: tools/vsession/remote.sh tb-1 packages/kwin/tests/vsession/scenario-tablet-titlebars.sh SEED 1440x900 420
exec 2>&1
export OUT
set -euo pipefail
set -x
CHK=$OUT/checks.txt
KLOG=$OUT/kwin.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
trap 'fail "the scenario stopped at line $LINENO: $BASH_COMMAND"' ERR
K() { python3 "$HOME/pf-tools/tests/lib/pfkwin.py" "$@" 2>>"$OUT/errors.log"; }
# CLASS JS: run JS with w the newest normal window whose class contains CLASS.
on() { K run "var l = workspace.windowList(), w = null; for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('$1') >= 0) { w = l[i]; } } if (w) { $2 } report(w ? 1 : 0);" >/dev/null; }
tile() { on "$1" "workspace.activeWindow = w;"; sleep 0.6; qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Window Quick Tile $2"; sleep 1.5; }
# CLASS: "tiled noBorder maximized"
state() {
  K run "var l = workspace.windowList(), w = null; for (var i = 0; i < l.length; ++i) { if (l[i].normalWindow && String(l[i].resourceClass).indexOf('$1') >= 0) { w = l[i]; } }
    report(w ? [!!w.tile, w.noBorder, w.maximizeMode === 3].join(' ') : 'none');" | python3 -c 'import json,sys; print(json.load(sys.stdin))'
}

bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1 || info "fusion-config rc=$?"
kwriteconfig6 --file kwinrc --group Script-plasmafusion-snap --key Gap 6
kwriteconfig6 --file kwinrc --group Script-plasmafusion-tablet --key InternalOutputs "eDP,LVDS,DSI,Virtual"
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardShown true
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardVersion 99
# The no-title-bar rules, the user's whatever the posture does: KCalc "apply initially"
# (Rules::Apply, substring) from the system's configuration, KCharSelect forced (Rules::Force,
# exact) from the user's own. The user's file lists both, as the KCM writes it when a rule is added
# beside a system-wide one (KConfig saves only the keys that differ from the system's).
mkdir -p "$HOME/.config/kdedefaults"
cat >"$HOME/.config/kdedefaults/kwinrulesrc" <<'RULES'
[1]
Description=Test: no title bar for kcalc (system-wide)
noborder=true
noborderrule=3
wmclass=kcalc
wmclassmatch=2

[General]
count=1
rules=1
RULES
kwriteconfig6 --file kwinrulesrc --group General --key count 2
kwriteconfig6 --file kwinrulesrc --group General --key rules 1,2
kwriteconfig6 --file kwinrulesrc --group 2 --key Description "Test: no title bar for kcharselect"
kwriteconfig6 --file kwinrulesrc --group 2 --key wmclass org.kde.kcharselect
kwriteconfig6 --file kwinrulesrc --group 2 --key wmclassmatch 1
kwriteconfig6 --file kwinrulesrc --group 2 --key noborder true
kwriteconfig6 --file kwinrulesrc --group 2 --key noborderrule 2
pfv_restart_shell 12
qdbus org.kde.KWin /KWin reconfigure; sleep 3
# KWin reads the system-wide rule: KCalc opens on the laptop without a title bar.
kcalc >/dev/null 2>&1 &
sleep 4
case "$(state kcalc)" in "false true false") pass "0: KWin applies the system-wide rule: KCalc opens without a title bar on the laptop" ;; *) fail "0: KCalc on the laptop $(state kcalc)" ;; esac
on kcalc "w.closeWindow();"
sleep 2
[ "$(state kcalc)" = none ] || info "KCalc still open: $(state kcalc)"
pfv_tablet on; sleep 8

# Every window opened in tablet posture.
for app in dolphin kwrite konsole kcalc kcharselect; do
  "$app" >/dev/null 2>&1 &
  sleep 4
done
info "opened in tablet: dolphin $(state dolphin), kwrite $(state kwrite), konsole $(state konsole), kcalc $(state kcalc), kcharselect $(state kcharselect)"

# ---- 1. Dolphin out of full screen: it takes a half
on dolphin "workspace.activeWindow = w; w.setMaximize(false, false);"
sleep 2
case "$(state dolphin)" in "true true false") pass "1: Dolphin out of full screen takes a half without a title bar" ;; *) fail "1: Dolphin $(state dolphin)" ;; esac
# ---- 2. KWrite quick-tiled out of full screen
tile kwrite Left
case "$(state kwrite)" in "true true false") pass "2: KWrite quick-tiled, no title bar" ;; *) fail "2: KWrite $(state kwrite)" ;; esac
# ---- 3. Konsole quick-tiled, then out of its tile: it floats
tile konsole Right
on konsole "if (w.tile) { w.tile.unmanage(w); }"
sleep 1.5
case "$(state konsole)" in "false true false") pass "3: Konsole out of its tile floats without a title bar" ;; *) fail "3: Konsole $(state konsole)" ;; esac
# ---- 4. KCalc and KCharSelect under their rules: quick-tiled out of full screen, then untiled
for app in kcalc kcharselect; do
  tile "$app" Left
  info "$app tiled: $(state "$app")"
  on "$app" "if (w.tile) { w.tile.unmanage(w); }"
  sleep 1.5
  info "$app untiled in tablet: $(state "$app")"
done

pfv_tablet off; sleep 6
shot tb-laptop
grep -a 'plasmafusion-tablet: leave' "$KLOG" | tail -n 1 >>"$CHK" || true
for app in dolphin kwrite konsole; do
  s=$(state "$app"); read -r _ nb _ <<<"$s"
  if [ "$nb" = false ]; then pass "after tablet posture $app has its title bar: $s"; else fail "after tablet posture $app has no title bar: $s"; fi
done
for app in kcalc kcharselect; do
  s=$(state "$app"); read -r _ nb _ <<<"$s"
  if [ "$nb" = true ]; then pass "after tablet posture $app keeps no title bar (its rule): $s"; else fail "$app got a title bar against its rule: $s"; fi
done
errs=$(grep -aE 'plasmafusion-tablet' "$KLOG" | grep -aiE 'error|TypeError|ReferenceError|is not defined|Cannot' || true)
if [ -z "$errs" ]; then pass "no QML errors from plasmafusion-tablet"; else fail "plasmafusion-tablet: $(echo "$errs" | head -3 | tr '\n' ' ')"; fi
info "done"
# A failed check fails the scenario (scenario rc), as the other KWin scenarios do: without the trap
# and errexit, so the last test sets the status vsession.sh records instead of ending its shell.
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$CHK" || true)" = 0 ]
