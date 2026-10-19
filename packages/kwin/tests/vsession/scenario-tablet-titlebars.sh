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
#   4. KCalc and Ark, which "apply initially" no-titlebar rules make borderless as they appear
#      (KWin shows their bars again on the un-maximize), and KCharSelect, which a forced one keeps
#      borderless: quick-tiled out of full screen, then out of their tiles. KCalc's rule is a
#      system-wide one (the session's XDG config directory ~/.config/kdedefaults, read as KWin reads
#      /etc/xdg), locked ([$i]) against the user's file, which tries to turn it off; Ark's names
#      its class with a regular expression only PCRE reads ("\A", "\z");
#   5. left maximized until tablet posture ends: Okular, made borderless by the user before tablet
#      posture (the policy maximizes it), and Gwenview, opened in tablet posture under an "apply
#      initially" no-titlebar rule;
# after leaving tablet posture Dolphin, KWrite and Konsole (under a rule that is off) have their
# title bars again, and KCalc, Ark, KCharSelect, Okular and Gwenview still have none; the script,
# loaded again once the rules exist, leaves both rules files as they were.
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
# The no-title-bar rules, the user's whatever the posture does:
# - KCalc "apply initially" (Rules::Apply, substring), from the system's configuration, its group
#   locked ([$i]): the user's file turning it off (noborderrule 1) does not count for KWin;
# - KCharSelect forced (Rules::Force, exact), the user's own;
# - Konsole "apply initially", but off (Enabled=false): KWin skips it;
# - Ark "apply initially", a regular expression with PCRE's \A and \z;
# - Gwenview "apply initially" (substring).
# The user's file lists them all, as the KCM writes it when rules are added beside a system-wide
# one (KConfig saves only the keys that differ from the system's).
mkdir -p "$HOME/.config/kdedefaults"
cat >"$HOME/.config/kdedefaults/kwinrulesrc" <<'RULES'
[1][$i]
Description=Test: no title bar for kcalc (system-wide, locked)
noborder=true
noborderrule=3
wmclass=kcalc
wmclassmatch=2

[General]
count=1
rules=1
RULES
# The user's file by hand: KConfig refuses to write into the locked group (kwriteconfig6 rc 2), and
# reads the locked values whatever the user's file says. Backslashes as KConfig writes them.
cat >"$HOME/.config/kwinrulesrc" <<'RULES'
[1]
noborderrule=1

[2]
Description=Test: no title bar for kcharselect
noborder=true
noborderrule=2
wmclass=org.kde.kcharselect
wmclassmatch=1

[3]
Description=Test: no title bar for konsole (off)
Enabled=false
noborder=true
noborderrule=3
wmclass=konsole
wmclassmatch=2

[4]
Description=Test: no title bar for ark (PCRE)
noborder=true
noborderrule=3
wmclass=(?:\\A|\\.)ark\\z
wmclassmatch=3

[5]
Description=Test: no title bar for gwenview
noborder=true
noborderrule=3
wmclass=gwenview
wmclassmatch=2

[General]
count=5
rules=1,2,3,4,5
RULES
pfv_restart_shell 12
qdbus org.kde.KWin /KWin reconfigure; sleep 3
# The script only reads the rules: neither file changes from here to the end, and none gains a key
# (a Settings object writes the properties declared on it into its file). It is loaded again now
# that the files exist (it opens them as it starts), as the setup's snap_script_reload does.
RULE_FILES=("$HOME/.config/kwinrulesrc" "$HOME/.config/kdedefaults/kwinrulesrc")
rules_sum() { sha256sum "${RULE_FILES[@]}" | cut -d' ' -f1 | tr '\n' ' '; }
RULES_SUM=$(rules_sum)
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript plasmafusion-tablet >/dev/null
for _ in $(seq 1 20); do
  [ "$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-tablet)" = true ] || break
  sleep 0.1
done
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript \
  "$HOME/.local/share/kwin/scripts/plasmafusion-tablet/contents/ui/main.qml" plasmafusion-tablet >/dev/null
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.start >/dev/null
sleep 3
info "tablet script loaded again: $(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-tablet)"
# How KWin reads the rules, on the laptop: KCalc (the locked system-wide rule), Ark (PCRE) and
# Gwenview open without a title bar, Konsole (its rule off) with one.
for app in kcalc ark konsole gwenview; do
  "$app" >/dev/null 2>&1 &
  sleep 4
done
case "$(state kcalc)" in "false true false") pass "0: KWin applies the locked system-wide rule: KCalc opens without a title bar on the laptop" ;; *) fail "0: KCalc on the laptop $(state kcalc)" ;; esac
case "$(state ark)" in "false true false") pass "0: KWin applies the PCRE rule: Ark opens without a title bar on the laptop" ;; *) fail "0: Ark on the laptop $(state ark)" ;; esac
case "$(state konsole)" in "false false false") pass "0: KWin skips the rule that is off: Konsole opens with a title bar on the laptop" ;; *) fail "0: Konsole on the laptop $(state konsole)" ;; esac
case "$(state gwenview)" in "false true false") pass "0: KWin applies Gwenview's rule: it opens without a title bar on the laptop" ;; *) fail "0: Gwenview on the laptop $(state gwenview)" ;; esac
for app in kcalc ark konsole gwenview; do
  on "$app" "w.closeWindow();"
done
sleep 2
for app in kcalc ark konsole gwenview; do
  [ "$(state "$app")" = none ] || info "$app still open: $(state "$app")"
done
# ---- 5. Okular, made borderless by the user on the laptop (as Alt+F3's "No titlebar and frame")
okular >/dev/null 2>&1 &
sleep 4
on okular "w.noBorder = true;"
sleep 0.5
info "okular on the laptop, borderless by the user: $(state okular)"
pfv_tablet on; sleep 8

# Every window opened in tablet posture.
for app in dolphin kwrite konsole kcalc kcharselect ark gwenview; do
  "$app" >/dev/null 2>&1 &
  sleep 4
done
info "opened in tablet: dolphin $(state dolphin), kwrite $(state kwrite), konsole $(state konsole), kcalc $(state kcalc), kcharselect $(state kcharselect), ark $(state ark), gwenview $(state gwenview), okular $(state okular)"

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
# ---- 4. KCalc, KCharSelect and Ark under their rules: quick-tiled out of full screen, then untiled
for app in kcalc kcharselect ark; do
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
for app in kcalc kcharselect ark; do
  s=$(state "$app"); read -r _ nb _ <<<"$s"
  if [ "$nb" = true ]; then pass "after tablet posture $app keeps no title bar (its rule): $s"; else fail "$app got a title bar against its rule: $s"; fi
done
# ---- 5. left maximized until the posture ended: un-maximized by leave(), still without a title bar
for app in okular gwenview; do
  s=$(state "$app")
  case "$s" in "false true false") pass "5: $app, maximized until tablet posture ended, keeps no title bar: $s" ;; *) fail "5: $app after tablet posture: $s" ;; esac
done
if [ "$(rules_sum)" = "$RULES_SUM" ] && ! grep -q 'modelData\|@Variant' "${RULE_FILES[@]}"; then
  pass "the script left the rules files as they were"
else
  fail "the rules files changed: $(grep -H 'modelData\|@Variant' "${RULE_FILES[@]}" | head -2 | tr '\n' ' ')"
fi
errs=$(grep -aE 'plasmafusion-tablet' "$KLOG" | grep -aiE 'error|TypeError|ReferenceError|is not defined|Cannot' || true)
if [ -z "$errs" ]; then pass "no QML errors from plasmafusion-tablet"; else fail "plasmafusion-tablet: $(echo "$errs" | head -3 | tr '\n' ' ')"; fi
info "done"
# A failed check fails the scenario (scenario rc), as the other KWin scenarios do: without the trap
# and errexit, so the last test sets the status vsession.sh records instead of ending its shell.
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$CHK" || true)" = 0 ]
