# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Test tooling (not installed). Every control of 1.0.0-4 through the module itself (tests/kcmctl:
# the plugin loaded as System Settings loads it, properties set, Apply / Reset / Defaults called),
# with the written keys read back after each step (checks.txt, state-*.txt) and screenshots of the
# effect. Run at 1920x1200 with PFV_SCALE=1.3333333 (make-seed.sh ... dark, PF_KCMCTL set):
#   pending changes write nothing and Reset brings the loaded values back; snap layouts; glass
#   Reduced / Solid / Full; solid top bar; reduce motion (with a user factor and without);
#   magnified size and magnification; desktop icons off and on (Folder View positions identical,
#   also across a shell restart) and icon size; file drag; battery; tablet section; high
#   contrast (a stand-in scheme) with a style change; a pending change across a shell restart;
#   a stopped shell; the power service's critical tier; Defaults.
exec 2>&1
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
export OUT
FILES=("$HOME/.config/plasmafusionrc" "$HOME/.config/kwinrc" "$HOME/.config/kdeglobals")
snapshot() { cat "${FILES[@]}" 2>/dev/null; }

fusion_setup
folder_desktop 12
# A non-default arrangement (BACKLOG M2): two icons moved to other cells (cell c,r at
# 47 + 96c, 68 + 108r logical at 1440x900).
pfinput 'drag 47 68 527 500' 'sleep 1.5'
pfinput 'drag 143 500 335 284' 'sleep 1.5'
pfinput 'move 900 450' 'sleep 1'
sleep 3
positions >"$OUT/positions-00.txt"
shot c00-icons-arranged
dump_state c00-initial

# A stand-in for the style part's high-contrast scheme (only in this HOME).
mkdir -p "$HOME/.local/share/color-schemes"
sed 's/^Name=.*/Name=Plasma Fusion High Contrast/' "$HOME/.local/share/color-schemes/PlasmaFusionDark.colors" \
  >"$HOME/.local/share/color-schemes/PlasmaFusionHighContrast.colors"

# 1. Pending changes write nothing; Reset (load) brings back what was loaded.
snapshot >"$OUT/files-before-pending.txt"
kcm <<'K'
waitshell
set glass 1
set desktopIcons false
set tabletMode 1
set snapTrigger 1
set dndBehavior 1
get needsSave
sh cat ~/.config/plasmafusionrc ~/.config/kwinrc ~/.config/kdeglobals > "$OUT/files-pending.txt" 2>/dev/null
load
waitshell
get needsSave
get glass
get desktopIcons
get tabletMode
K
check "pending: files unchanged" "$(cmp -s "$OUT/files-before-pending.txt" "$OUT/files-pending.txt" && echo same)" same
check "pending: filterMode unchanged" "$(fkey filterMode)" ""
check "pending: page asked for Apply" "$(gets needsSave)" "true false"
# The tablet-mode choice as the session started (PFV_TABLET writes kwinrc [Input] TabletMode):
# auto 0, on 1, off 2.
case "$(kreadconfig6 --file kwinrc --group Input --key TabletMode --default auto)" in on) tm0=1 ;; off) tm0=2 ;; *) tm0=0 ;; esac
check "reset: values back" "$(lastget glass) $(lastget desktopIcons) $(lastget tabletMode)" "0 true $tm0"

# 2. Snap layouts.
kcm <<'K'
waitshell
set snapTrigger 1
save
K
check "snap hover" "$(ck plasmafusionrc Decoration SnapLayoutsOnHover)" true
kcm <<'K'
waitshell
set snapTrigger 0
save
K
check "snap hold" "$(ck plasmafusionrc Decoration SnapLayoutsOnHover)" false

# 3. Glass: Reduced, Solid, Full.
kcm <<'K'
waitshell
set glass 1
save
K
sleep 1
dump_state c03-glass-reduced
shot c03-glass-reduced
check "reduced: Glass" "$(ck plasmafusionrc Effects Glass)" Reduced
check "reduced: top bar" "$(popacity top)" opaque
check "reduced: dock" "$(popacity dock)" opaque
check "reduced: dock glass" "$(wkey org.plasmafusion.dock glass)" reduced
check "reduced: quick settings glass" "$(wkey org.plasmafusion.quicksettings glass)" reduced
check "reduced: launcher glass" "$(wkey org.plasmafusion.launcher glass)" reduced
check "reduced: system card glass" "$(wkey org.plasmafusion.systemcard glass)" reduced
check "reduced: blur loaded" "$(blur_loaded)" true
check "reduced: blurEnabled" "$(ck kwinrc Plugins blurEnabled)" ""
# The layout makes the top bar solid next to maximized windows (owner decision 5, LAYOUT-1).
check "reduced: top-bar choice kept" "$(ck plasmafusionrc TopBar SolidNextToWindows)" true
kcm <<'K'
waitshell
set glass 2
save
K
sleep 1
dump_state c03-glass-solid
shot c03-glass-solid
check "solid: Glass" "$(ck plasmafusionrc Effects Glass)" Solid
check "solid: blurEnabled" "$(ck kwinrc Plugins blurEnabled)" false
check "solid: blur loaded" "$(blur_loaded)" false
check "solid: top bar keeps the choice made before Reduced (the layout's adaptive)" "$(popacity top)" adaptive
check "solid: dock" "$(popacity dock)" translucent
check "solid: dock glass" "$(wkey org.plasmafusion.dock glass)" solid
kcm <<'K'
waitshell
set glass 0
save
K
sleep 1
check "full: Glass" "$(ck plasmafusionrc Effects Glass)" Full
check "full: blurEnabled" "$(ck kwinrc Plugins blurEnabled)" ""
check "full: blur loaded" "$(blur_loaded)" true
check "full: dock glass" "$(wkey org.plasmafusion.dock glass)" full
shot c03-glass-full

# 4. Solid top bar next to windows (adaptive).
kcm <<'K'
waitshell
get solidTopBar
set solidTopBar true
save
K
check "top bar adaptive" "$(popacity top)" adaptive
dolphin --new-window "$HOME" >"$OUT/dolphin.log" 2>&1 &
sleep 5
qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Window Maximize" >/dev/null 2>&1
sleep 2
shot c04-top-bar-solid-next-to-maximized
qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Window Close" >/dev/null 2>&1
sleep 2

# 5. Reduce motion: with a user factor (0.5, put back) and without one (key removed again).
kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor --notify 0.5
sleep 1
kcm <<'K'
waitshell
get reduceMotion
set reduceMotion true
save
K
check "motion on: factor" "$(ck kdeglobals KDE AnimationDurationFactor)" 0
check "motion on: previous kept" "$(ck plasmafusionrc Motion PreviousAnimationDurationFactor)" 0.5
kcm <<'K'
waitshell
get reduceMotion
set reduceMotion false
save
K
check "motion off: factor back" "$(ck kdeglobals KDE AnimationDurationFactor)" 0.5
check "motion off: previous removed" "$(ck plasmafusionrc Motion PreviousAnimationDurationFactor)" ""
kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor --notify --delete
sleep 1
kcm <<'K'
waitshell
set reduceMotion true
save
sh kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor --notify 1
wait 1500
get reduceMotion
sh kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor --notify 0
wait 1500
get reduceMotion
set reduceMotion false
save
K
check "motion: the switch shows the live factor (0.5, 0, 1, 0)" "$(gets reduceMotion)" "false true false true"
check "motion off without a previous factor: key removed" "$(ck kdeglobals KDE AnimationDurationFactor)" ""

# 6. Dock magnification size and switch.
kcm <<'K'
waitshell
set magnifiedSize 56
save
K
check "magnified 56" "$(wkey org.plasmafusion.dock magnifiedSize)" 56
kcm <<'K'
waitshell
set magnify false
save
K
check "magnify off" "$(wkey org.plasmafusion.dock magnify)" false
kcm <<'K'
waitshell
set magnify true
set magnifiedSize 62
save
K
check "magnify on, 62" "$(wkey org.plasmafusion.dock magnify) $(wkey org.plasmafusion.dock magnifiedSize)" "true 62"

# 7. Desktop icons off and on: positions stay (also across a shell restart); icon size.
kcm <<'K'
waitshell
set desktopIcons false
save
K
sleep 3
shot c07-icons-off
positions >"$OUT/positions-01-off.txt"
check "icons off: filterMode" "$(fkey filterMode)" 1
check "icons off: filterPattern" "$(fkey filterPattern)" /
check "icons off: positions unchanged" "$(same_positions "$OUT/positions-00.txt" "$OUT/positions-01-off.txt")" same
pfv_restart_shell
sleep 8
positions >"$OUT/positions-02-off-restarted.txt"
check "icons off, shell restarted: positions unchanged" "$(same_positions "$OUT/positions-00.txt" "$OUT/positions-02-off-restarted.txt")" same
shot c07-icons-off-restarted
kcm <<'K'
waitshell
get desktopIcons
set desktopIcons true
save
K
sleep 3
shot c07-icons-on
positions >"$OUT/positions-03-on.txt"
check "icons on: filterMode" "$(fkey filterMode)" 0
check "icons on: filterPattern" "$(fkey filterPattern)" "*"
check "icons on: positions unchanged" "$(same_positions "$OUT/positions-00.txt" "$OUT/positions-03-on.txt")" same
check "icons on: desktop looks as arranged (pixels differing)" "$(python3 - "$OUT/c00-icons-arranged.png" "$OUT/c07-icons-on.png" <<'PY'
import sys
from PIL import Image, ImageChops
a, b = (Image.open(p).convert("L").crop((0, 60, 1100, 1000)) for p in sys.argv[1:3])
print(sum(1 for v in ImageChops.difference(a, b).point(lambda v: 255 if v > 40 else 0).tobytes() if v))
PY
)" 0
kcm <<'K'
waitshell
set iconSize 3
save
K
sleep 3
shot c07-icons-large
check "icon size large" "$(fkey iconSize)" 3
kcm <<'K'
waitshell
set iconSize 2
save
K
sleep 2
positions >"$OUT/positions-04-size-back.txt"

# 8. File drag, battery.
kcm <<'K'
waitshell
set dndBehavior 1
set lighterOnCritical false
set fileContentIndexing false
save
K
check "drag: move" "$(ck kdeglobals KDE DndBehavior)" MoveIfSameDevice
check "battery off" "$(ck plasmafusionrc Power LighterOnCritical)" false
check "file contents not indexed" "$(ck baloofilerc General 'only basic indexing')" true
kcm <<'K'
waitshell
set dndBehavior 0
set lighterOnCritical true
set fileContentIndexing true
save
K
check "drag: ask (key removed)" "$(ck kdeglobals KDE DndBehavior)" ""
check "battery on" "$(ck plasmafusionrc Power LighterOnCritical)" true
check "file contents indexed" "$(ck baloofilerc General 'only basic indexing')" false

# 9. Tablet section.
kcm <<'K'
waitshell
set tabletMode 1
save
wait 1500
get tabletModeActive
K
check "tablet always: key" "$(ck kwinrc Input TabletMode)" on
check "tablet always: KWin" "$(qdbus org.kde.KWin /org/kde/KWin org.kde.KWin.TabletModeManager.tabletMode)" true
check "tablet always: page follows KWin" "$(lastget tabletModeActive)" true
shot c09-tablet-always
kcm <<'K'
waitshell
set tabletMode 2
set tabletApps 1
set tabletDock 1
set edgeLeft true
set edgeRight true
set keyboardPolicy 2
set homeIndicator false
save
K
check "tablet never: key" "$(ck kwinrc Input TabletMode)" off
check "tablet never: KWin" "$(qdbus org.kde.KWin /org/kde/KWin org.kde.KWin.TabletModeManager.tabletMode)" false
check "apps windowed" "$(ck kwinrc Script-plasmafusion-tablet WindowMode)" windowed
check "dock always" "$(ck kwinrc Script-plasmafusion-tablet DockHiding)" none
check "edge left" "$(ck kwinrc Script-plasmafusion-tablet EdgeLeft)" true
check "edge right" "$(ck kwinrc Script-plasmafusion-tablet EdgeRight)" true
check "keyboard never" "$(wkey org.plasmafusion.quicksettings keyboardPolicy)" never
check "home indicator off" "$(wkey org.plasmafusion.dock homeIndicator)" false
kcm <<'K'
waitshell
dump
set keyboardPolicy 1
save
K
check "keyboard on touch" "$(wkey org.plasmafusion.quicksettings keyboardPolicy)" touch
kcm <<'K'
waitshell
set tabletMode 0
set tabletApps 0
set tabletDock 0
set edgeLeft false
set edgeRight false
set keyboardPolicy 0
set homeIndicator true
save
K
check "tablet auto: key removed" "$(ck kwinrc Input TabletMode)" ""
check "apps full screen" "$(ck kwinrc Script-plasmafusion-tablet WindowMode)" fullscreen
check "dock hides" "$(ck kwinrc Script-plasmafusion-tablet DockHiding)" dodgewindows
check "keyboard tablet" "$(wkey org.plasmafusion.quicksettings keyboardPolicy)" tablet
check "home indicator on" "$(wkey org.plasmafusion.dock homeIndicator)" true

# 10. High contrast (stand-in scheme): selects Solid; turned off before Apply, the glass goes back;
#     kept through a style change; off again.
kcm <<'K'
waitshell
set highContrast true
get glass
set highContrast false
get glass
get needsSave
K
check "high contrast off before Apply: glass back, nothing pending" "$(gets glass | awk '{print $(NF-1), $NF}') $(lastget needsSave)" "2 0 false"
kcm <<'K'
waitshell
get highContrastAvailable
set highContrast true
get glass
save
K
sleep 2
shot c10-high-contrast
check "high contrast: scheme" "$(ck kdeglobals General ColorScheme)" PlasmaFusionHighContrast
check "high contrast: selects Solid on the page" "$(lastget glass)" 2
check "high contrast: glass solid" "$(ck plasmafusionrc Effects Glass) $(blur_loaded)" "Solid false"
kcm <<'K'
waitshell
set style 0
save
K
sleep 3
check "high contrast kept after Light" "$(ck kdeglobals KDE LookAndFeelPackage) $(ck kdeglobals General ColorScheme)" "org.plasmafusion.light.desktop PlasmaFusionHighContrast"
kcm <<'K'
waitshell
set highContrast false
set glass 0
set style 1
save
K
sleep 3
check "high contrast off, Dark" "$(ck kdeglobals General ColorScheme) $(ck plasmafusionrc Effects Glass) $(blur_loaded)" "PlasmaFusionDark Full true"
shot c10-back-to-dark

# 11. A pending change across a shell restart is kept and applied.
kcm <<'K'
waitshell
set magnifiedSize 56
set iconSize 1
sh kquitapp6 plasmashell; sleep 2; (plasmashell >>"$OUT/plasmashell-11.log" 2>&1 &); sleep 12
wait 5000
get shellRunning
get magnifiedSize
get iconSize
get needsSave
save
K
check "pending across restart: kept on the page" "$(lastget shellRunning) $(lastget magnifiedSize) $(lastget iconSize) $(lastget needsSave)" "true 56 1 true"
check "pending across restart: dock" "$(wkey org.plasmafusion.dock magnifiedSize)" 56
check "pending across restart: icon size" "$(fkey iconSize)" 1
kcm <<'K'
waitshell
set magnifiedSize 62
set iconSize 2
save
K

# 12. A stopped shell: the shell controls cannot be applied and keep their value.
kquitapp6 plasmashell >/dev/null 2>&1
sleep 3
kcm <<'K'
wait 1000
waitshell
get shellRunning
set glass 1
save
get glass
K
check "stopped shell: page" "$(lastget shellRunning) $(lastget glass)" "false 0"
check "stopped shell: Glass not written" "$(ck plasmafusionrc Effects Glass)" Full
plasmashell >>"$OUT/plasmashell-12.log" 2>&1 &
wait_for_name org.kde.plasmashell
sleep 12

# 13. The power service's critical tier (simulated as plasma-fusion-powerfx leaves it).
kwriteconfig6 --file plasmafusionrc --group Power --key Tier critical
kwriteconfig6 --file plasmafusionrc --group Power --key UserDockMagnify true
kwriteconfig6 --file plasmafusionrc --group Power --key UserGlass Full
evaljs - >/dev/null <<'JS'
var ps = panels();
for (var i = 0; i < ps.length; ++i) { var d = ps[i].widgets("org.plasmafusion.dock"); for (var j = 0; j < d.length; ++j) { d[j].currentConfigGroup = ["General"]; d[j].writeConfig("magnify", false); } }
JS
qdbus org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect blur
sleep 1
kcm <<'K'
waitshell
get powerCritical
get magnify
set glass 1
set magnify false
save
K
dump_state c13-critical
check "critical: Glass" "$(ck plasmafusionrc Effects Glass)" Reduced
check "critical: UserGlass" "$(ck plasmafusionrc Power UserGlass)" Reduced
check "critical: blur stays unloaded" "$(blur_loaded)" false
check "critical: dock glass left to the service" "$(wkey org.plasmafusion.dock glass)" full
check "critical: panels follow Reduced" "$(popacity top)" opaque
check "critical: UserDockMagnify" "$(ck plasmafusionrc Power UserDockMagnify)" false
check "critical: page showed the tier and the remembered magnification" "$(lastget powerCritical) $(lastget magnify)" "true true"
kwriteconfig6 --file plasmafusionrc --group Power --key Tier full
kwriteconfig6 --file plasmafusionrc --group Power --key UserGlass --delete
kwriteconfig6 --file plasmafusionrc --group Power --key UserDockMagnify --delete
qdbus org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect blur

# 14. Defaults: everything back to the Plasma Fusion defaults.
kcm <<'K'
waitshell
set glass 2
set snapTrigger 1
set dndBehavior 1
set tabletMode 1
set iconSize 3
set keyboardPolicy 2
set everyScreen false
set solidTopBar false
save
defaults
get representsDefaults
get needsSave
save
get representsDefaults
K
sleep 2
dump_state c14-defaults
shot c14-defaults
check "defaults: Glass" "$(ck plasmafusionrc Effects Glass) $(blur_loaded)" "Full true"
check "defaults: snap" "$(ck plasmafusionrc Decoration SnapLayoutsOnHover)" false
check "defaults: drag" "$(ck kdeglobals KDE DndBehavior)" ""
check "defaults: tablet" "$(ck kwinrc Input TabletMode)" ""
check "defaults: icon size" "$(fkey iconSize)" 2
check "defaults: icons" "$(fkey filterMode)" 0
check "defaults: keyboard" "$(wkey org.plasmafusion.quicksettings keyboardPolicy)" tablet
check "defaults: every screen" "$(ck plasmafusionrc TopBar EveryScreen)" true
check "defaults: top bar" "$(popacity top) $(popacity dock)" "adaptive translucent"
check "defaults: dock" "$(wkey org.plasmafusion.dock magnify) $(wkey org.plasmafusion.dock magnifiedSize)" "true 62"
check "defaults: motion" "$(ck kdeglobals KDE AnimationDurationFactor)" ""
check "defaults: page reports defaults (after Defaults, after Apply)" "$(gets representsDefaults | awk '{print $(NF-1), $NF}')" "true true"
# Informational: an icon-size change re-lays the grid (Folder View converts the positions).
positions >"$OUT/positions-05-end.txt"
shot c15-end
