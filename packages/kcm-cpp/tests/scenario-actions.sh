# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed). "Top bar on every screen" off and on, "Reset Fusion layout" twice
# (the widgets' global shortcuts carried over, the default ones given, dead entries released,
# the glass level applied to the new panels, keys pressed afterwards open the widgets) and
# "Restore my previous desktop", all through tests/kcmctl. Run with PFV_OUTPUTS=2 at 1920x1200 and
# PFV_SCALE=1.3333333 (make-seed.sh ... dark, PF_KCMCTL set).
#
# The pen widget does not exist yet at this revision (the pen part builds it and the layout part
# adds it to the top bar), so a stand-in org.plasmafusion.pen widget is installed in this HOME
# and the HOME's copy of the layout script adds it, as the layout part will.
exec 2>&1
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
export OUT
META=$((0x10000000))
KEY_A=$((META + 0x41)) KEY_N=$((META + 0x4e)) KEY_SHIFT_W=$((META + 0x02000000 + 0x57))
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
print(n.join(" "));
JS
}

fusion_setup

# Stand-in pen widget and the layout script copy that adds it (test HOME only).
PEN=$HOME/.local/share/plasma/plasmoids/org.plasmafusion.pen
mkdir -p "$PEN/contents/ui"
cat >"$PEN/metadata.json" <<'EOF'
{
    "KPackageStructure": "Plasma/Applet",
    "KPlugin": {
        "Authors": [{ "Email": "archledger236@gmail.com", "Name": "Wisbendji Fimerlus" }],
        "Category": "Utilities",
        "Id": "org.plasmafusion.pen",
        "License": "GPL-2.0-or-later",
        "Name": "Pen (test stand-in)",
        "Version": "0.0"
    },
    "X-Plasma-API-Minimum-Version": "6.0"
}
EOF
cat >"$PEN/contents/ui/main.qml" <<'EOF'
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
PlasmoidItem {
    compactRepresentation: PC3.Label { text: "PEN" }
    fullRepresentation: PC3.Label {
        text: "PEN MENU (stand-in)"
        Layout.minimumWidth: 220
        Layout.minimumHeight: 80
    }
}
EOF
LAYOUT=$HOME/.local/share/plasma/look-and-feel/org.plasmafusion.dark.desktop/contents/layouts/org.kde.plasma.desktop-layout.js
cat >>"$LAYOUT" <<'EOF'

// o1km test stand-in: the pen widget in the top bar, as the layout part will add it.
(function () {
    var ps = panels();
    for (var i = 0; i < ps.length; ++i) {
        if (ps[i].widgets("org.plasmafusion.quicksettings").length > 0) {
            ps[i].addWidget("org.plasmafusion.pen");
            break;
        }
    }
})();
EOF
evaljs - >/dev/null <<'JS'
var ps = panels();
for (var i = 0; i < ps.length; ++i) if (ps[i].widgets("org.plasmafusion.quicksettings").length > 0) { ps[i].addWidget("org.plasmafusion.pen"); break; }
JS
# A second top bar on the second screen, as decision 8's ensure-topbars.js adds one.
evaljs - >"$OUT/second-bar.txt" <<'JS'
var p = new Panel;
p.location = "top";
p.screen = 1;
p.height = 34;
p.addWidget("org.plasmafusion.appname");
p.addWidget("org.plasmafusion.clockpill");
print("panel " + p.id + " screen " + p.screen);
JS
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

# 2. Reset Fusion layout with the shortcuts of this revision's fusion-config.sh (quick settings
#    Meta+N) and a pen widget without a shortcut.
QS_OLD=$(widget_id org.plasmafusion.quicksettings)
check "before reset 1: quick settings key" "$(wshortcut org.plasmafusion.quicksettings)" Meta+N
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
PEN_ID=$(widget_id org.plasmafusion.pen)
check "reset 1: new quick settings widget" "$([ "$QS_NEW" != "$QS_OLD" ] && [ "$QS_NEW" != "<none>" ] && echo new)" new
check "reset 1: quick settings key carried over" "$(wshortcut org.plasmafusion.quicksettings)" Meta+N
check "reset 1: pen key given" "$(wshortcut org.plasmafusion.pen)" Meta+Shift+W
check "reset 1: Meta+N held by the new widget" "$(holder $KEY_N)" "plasmashell/activate widget $QS_NEW"
check "reset 1: Meta+Shift+W held by the pen" "$(holder $KEY_SHIFT_W)" "plasmashell/activate widget $PEN_ID"
check "reset 1: no error" "$(lastget errorText)" ""
pfinput 'move 700 450' 'sleep 0.5' 'key meta+n' 'sleep 1.5'
shot b02-meta-n
pfinput 'key esc' 'sleep 1'
pfinput 'key meta+shift+w' 'sleep 1.5'
shot b02-meta-shift-w
pfinput 'key esc' 'sleep 1'

# 3. The Windows-style set (decision 6: DEVICE-1 gives quick settings Meta+A), Reduced glass
#    with an always-translucent top bar; then a second reset.
H=$(holder $KEY_A)
echo "Meta+A before: $H" >>"$OUT/shortcuts.txt"
if [ "$H" != "<none>" ]; then
  busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel setForeignShortcut asai 4 "${H%%/*}" "${H#*/}" "" "" 0 >>"$OUT/busctl.log" 2>&1
fi
evaljs - >/dev/null <<'JS'
var ps = panels();
for (var i = 0; i < ps.length; ++i) { var q = ps[i].widgets("org.plasmafusion.quicksettings"); if (q.length > 0) q[0].globalShortcut = "Meta+A"; }
JS
check "before reset 2: quick settings key" "$(wshortcut org.plasmafusion.quicksettings)" Meta+A
kcm <<'K'
waitshell
set glass 1
set solidTopBar false
save
K
QS_OLD=$(widget_id org.plasmafusion.quicksettings)
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
check "reset 2: quick settings key carried over" "$(wshortcut org.plasmafusion.quicksettings)" Meta+A
check "reset 2: pen key carried over" "$(wshortcut org.plasmafusion.pen)" Meta+Shift+W
check "reset 2: Meta+A held by the new widget" "$(holder $KEY_A)" "plasmashell/activate widget $QS_NEW"
check "reset 2: glass applied to the new panels" "$(popacity top) $(popacity dock) $(wkey org.plasmafusion.dock glass)" "opaque opaque reduced"
check "reset 2: page after the reset" "$(lastget glass) $(lastget solidTopBar)" "1 false"
check "reset 2: no error" "$(lastget errorText)" ""
pfinput 'move 700 450' 'sleep 0.5' 'key meta+a' 'sleep 1.5'
shot b03-meta-a
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
