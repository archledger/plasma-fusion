# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Test tooling (not installed). "Top bar on every screen" off and on, "Reset Fusion layout" twice
# (widget shortcuts carried over, unbound pen kept unbound, notification binding preserved,
# the glass level applied to the new panels, keys pressed afterwards open the widgets) and
# "Restore my previous desktop", all through tests/kcmctl. Run with PFV_OUTPUTS=2 at 1920x1200 and
# PFV_SCALE=1.3333333 (make-seed.sh ... dark, PF_KCMCTL set).
#
# Uses the real staged pen widget and the top bars created by fusion_setup.
exec 2>&1
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
export OUT
META=$((0x10000000))
KEY_A=$((META + 0x41)) KEY_N=$((META + 0x4e)) KEY_SHIFT_W=$((META + 0x02000000 + 0x57))
KEY_CUSTOM=$((META + 0x04000000 + 0x59)) # Meta+Ctrl+Y
# The action holding a key, as "component/action".
holder() {
  busctl --user --json=short call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel actionList "(ai)" 4 "$1" 0 0 0 2>>"$OUT/busctl.log" |
    python3 -c 'import json,sys; d=json.load(sys.stdin)["data"][0]; print("/".join(d[:2]) if d else "<none>")'
}
widget_id() {
  evaljs - <<JS
var ps = panels(), v = "<none>";
for (var i = 0; i < ps.length && v === "<none>"; ++i) { var ws = ps[i].widgets("$1"); if (ws.length > 0) v = String(ws[0].id); }
print(v);
JS
}
top_bars() {
  evaljs - <<'JS'
var ps = panels(), n = [];
for (var i = 0; i < ps.length; ++i) if (ps[i].widgets("org.plasmafusion.appname").length > 0) n.push("screen" + ps[i].screen);
print(n.sort().join(" "));
JS
}

fusion_setup

# The current layout provides both the real pen widget and the second screen's
# bar. Adding historical stand-ins here duplicates that setup and QML may still
# use the already-loaded real widget rather than the replacement file.
if [ "$(widget_id org.plasmafusion.pen)" = "<none>" ]; then
  check "setup: real staged pen widget" missing present
  return 1
fi
check "setup: real staged pen widget" present present
sleep 4
dump_state b00-initial
shot b00-two-screens
check "setup: top bars" "$(top_bars)" "screen0 screen1"

# 1. Top bar on every screen: off removes the second screen's bar; on keeps the choice.
kcm <<'K'
waitshell
get everyScreen
get topBarScriptAvailable
set everyScreen false
save
K
sleep 2
check "every screen off: key" "$(ck plasmafusionrc TopBar EveryScreen)" false
check "every screen off: bars" "$(top_bars)" screen0
shot b01-every-screen-off
kcm <<'K'
waitshell
set everyScreen true
save
K
check "every screen on: key" "$(ck plasmafusionrc TopBar EveryScreen)" true

# 2. Reset with current setup defaults: quick settings uses Meta+A, notifications
#    owns Meta+N independently of widgets, and the pen key is opt-in.
QS_OLD=$(widget_id org.plasmafusion.quicksettings)
check "before reset 1: quick settings key" "$(wshortcut org.plasmafusion.quicksettings)" Meta+A
check "before reset 1: pen is unbound" "$(wshortcut org.plasmafusion.pen)" ""
check "before reset 1: notifications owns Meta+N" "$(holder $KEY_N)" "org.plasmafusion.notifications.desktop/_launch"
kcm <<'K'
waitshell
call resetLayout
waitidle
get infoText
get errorText
K
sleep 3
dump_state b02-reset-1
shot b02-after-reset-1
QS_NEW=$(widget_id org.plasmafusion.quicksettings)
check "reset 1: new quick settings widget" "$([ "$QS_NEW" != "$QS_OLD" ] && [ "$QS_NEW" != "<none>" ] && echo new)" new
check "reset 1: quick settings key carried over" "$(wshortcut org.plasmafusion.quicksettings)" Meta+A
check "reset 1: pen stays unbound" "$(wshortcut org.plasmafusion.pen)" ""
check "reset 1: Meta+A held by the new widget" "$(holder $KEY_A)" "plasmashell/activate widget $QS_NEW"
check "reset 1: Meta+N still belongs to notifications" "$(holder $KEY_N)" "org.plasmafusion.notifications.desktop/_launch"
check "reset 1: Meta+Shift+W stays free" "$(holder $KEY_SHIFT_W)" "<none>"
check "reset 1: no error" "$(lastget errorText)" ""
pfinput 'move 700 450' 'sleep 0.5' 'key meta+a' 'sleep 1.5'
shot b02-meta-a
pfinput 'key esc' 'sleep 1'
pfinput 'key meta+n' 'sleep 1.5'
shot b02-meta-n
pfinput 'key esc' 'sleep 1'

# 3. User-assigned quick settings and pen keys, Reduced glass with an
#    always-translucent top bar; then a second reset. Never steal an occupied key.
H=$(holder $KEY_CUSTOM)
echo "Meta+Ctrl+Y before: $H" >>"$OUT/shortcuts.txt"
if [ "$H" != "<none>" ]; then
  check "test setup: custom key is free" "$H" "<none>"
  return 1
fi
H=$(holder $KEY_SHIFT_W)
if [ "$H" != "<none>" ]; then
  check "test setup: opt-in pen key is free" "$H" "<none>"
  return 1
fi
evaljs - >/dev/null <<'JS'
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    var q = ps[i].widgets("org.plasmafusion.quicksettings");
    if (q.length > 0) { q[0].globalShortcut = "Meta+Ctrl+Y"; break; }
}
for (var i = 0; i < ps.length; ++i) {
    var p = ps[i].widgets("org.plasmafusion.pen");
    if (p.length > 0) { p[0].globalShortcut = "Meta+Shift+W"; break; }
}
JS
check "before reset 2: quick settings key" "$(wshortcut org.plasmafusion.quicksettings)" Meta+Ctrl+Y
check "before reset 2: pen key assigned explicitly" "$(wshortcut org.plasmafusion.pen)" Meta+Shift+W
kcm <<'K'
waitshell
set glass 1
set solidTopBar false
save
K
QS_OLD=$(widget_id org.plasmafusion.quicksettings)
PEN_OLD=$(widget_id org.plasmafusion.pen)
kcm <<'K'
waitshell
call resetLayout
waitidle
get infoText
get errorText
get glass
get solidTopBar
K
sleep 3
dump_state b03-reset-2
shot b03-after-reset-2
QS_NEW=$(widget_id org.plasmafusion.quicksettings)
check "reset 2: quick settings widget was rebuilt" "$([ "$QS_NEW" != "$QS_OLD" ] && [ "$QS_NEW" != "<none>" ] && echo new)" new
check "reset 2: quick settings key carried over" "$(wshortcut org.plasmafusion.quicksettings)" Meta+Ctrl+Y
check "reset 2: pen key carried over" "$(wshortcut org.plasmafusion.pen)" Meta+Shift+W
PEN_ID=$(widget_id org.plasmafusion.pen)
check "reset 2: pen widget was rebuilt" "$([ "$PEN_ID" != "$PEN_OLD" ] && [ "$PEN_ID" != "<none>" ] && echo new)" new
check "reset 2: custom key held by the new widget" "$(holder $KEY_CUSTOM)" "plasmashell/activate widget $QS_NEW"
check "reset 2: pen key held by the new widget" "$(holder $KEY_SHIFT_W)" "plasmashell/activate widget $PEN_ID"
check "reset 2: notifications key remains unchanged" "$(holder $KEY_N)" "org.plasmafusion.notifications.desktop/_launch"
check "reset 2: glass applied to the new panels" "$(popacity top) $(popacity dock) $(wkey org.plasmafusion.dock glass)" "opaque opaque reduced"
check "reset 2: page after the reset" "$(lastget glass) $(lastget solidTopBar)" "1 false"
check "reset 2: no error" "$(lastget errorText)" ""
pfinput 'move 700 450' 'sleep 0.5' 'key meta+ctrl+y' 'sleep 1.5'
shot b03-custom-key
pfinput 'key esc' 'sleep 1'
pfinput 'key meta+shift+w' 'sleep 1.5'
shot b03-pen-key
pfinput 'key esc' 'sleep 1'
kcm <<'K'
waitshell
set glass 0
save
K
check "full again: top bar keeps the translucent choice" "$(popacity top)" translucent

# 4. Restore my previous desktop (the look saved by fusion-config.sh before Plasma Fusion).
kcm <<'K'
waitshell
get previousDesktopAvailable
call restorePreviousDesktop
waitidle
get style
get infoText
get errorText
K
sleep 4
dump_state b04-previous-desktop
shot b04-previous-desktop
check "restore: Global Theme" "$(ck kdeglobals KDE LookAndFeelPackage)" org.plasmafusion.previous.desktop
check "restore: page shows no Fusion style" "$(lastget style)" -1
check "restore: no error" "$(lastget errorText)" ""
kcm <<'K'
waitshell
get fusionLookAndFeel
K
check "restore: layout reset offered only with a Fusion theme" "$(lastget fusionLookAndFeel)" false
