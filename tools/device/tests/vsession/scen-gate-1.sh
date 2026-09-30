# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Login check, integrated phase 1 (tools/vsession scenario; test tooling only). Seed HOME:
# pf-stage/ (tools/build.sh output) and pf-tools/ (the repository's tools/). Starts from a Breeze
# Dark desktop with a font of the user's own, installs Plasma Fusion with fusion-config.sh, then:
#   (a) matching versions: the check changes nothing;
#   (c) Breeze chosen: the next check switches the Fusion-only parts off; Plasma Fusion Dark again
#       and the next check turns them back on;
#   (d) "My previous desktop" is listed and gives back the Breeze Dark look;
#   and ends on the compiled decoration for phase 2 (faked update).
exec 2>&1
set -x
T=$HOME/pf-tools/device
GATE=$HOME/.local/share/plasma-fusion/gate/plasma-fusion-gate.sh
. "$HOME/pf-tools/device/tests/vsession/gate-common.sh"

# Seed look: Breeze Dark and a user font.
plasma-apply-lookandfeel -a org.kde.breezedark.desktop >"$OUT/lnf-0.log" 2>&1
kwriteconfig6 --file kdeglobals --group General --key font --notify "Noto Sans,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
sleep 3
dump 0-breeze-dark-seed
cfgsum >"$OUT/cfg-0.txt"
# Kept in HOME for phase 3, which compares it with the state after fusion-restore.sh.
mkdir -p "$HOME/pf-test" && cp "$OUT/cfg-0.txt" "$HOME/pf-test/cfg-0.txt"
shot 00-seed

bash "$T/fusion-config.sh" --install "$HOME/pf-stage" --dry-run >"$OUT/fc-0-dry.log" 2>&1
echo "dry run rc=$? state dir: $(ls "$HOME/.local/state/plasma-fusion" 2>&1)" >>"$OUT/checks.txt"
bash "$T/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc-1.log" 2>&1
echo "fusion-config rc=$?" >>"$OUT/checks.txt"
restart_shell
dump 1-fusion
cfgsum >"$OUT/cfg-1.txt"
shot 01-fusion
ls -la "$HOME/.config/plasma-workspace/env" "$HOME/.config/systemd/user" "$HOME/.config/systemd/user/xdg-desktop-autostart.target.wants" \
  "$HOME/.local/share/plasma-fusion/gate" "$HOME/.local/state/plasma-fusion/gate" >"$OUT/installed.txt" 2>&1
cat "$HOME/.config/plasma-workspace/env/plasma-fusion-gate.sh" "$HOME/.config/systemd/user/plasma-fusion-gate-notify.service" \
  "$HOME/.local/state/plasma-fusion/gate/tested" >>"$OUT/installed.txt" 2>&1
cp -r "$HOME/.local/share/plasma/look-and-feel/org.plasmafusion.previous.desktop" "$OUT/previous-package" 2>/dev/null

bash "$T/fusion-config.sh" >"$OUT/fc-2-rerun.log" 2>&1
echo "second run: $(grep -E '^Done' "$OUT/fc-2-rerun.log")" >>"$OUT/checks.txt"
cfgsum >"$OUT/cfg-2.txt"

# (a) matching versions: nothing changes.
bash "$GATE" check >"$OUT/gate-a-check.log" 2>&1
simulated_login a
cfgsum >"$OUT/cfg-a.txt"
cmp -s "$OUT/cfg-2.txt" "$OUT/cfg-a.txt" && echo "(a) PASS config unchanged by a matching login" >>"$OUT/checks.txt" ||
  { echo "(a) FAIL config changed by a matching login" >>"$OUT/checks.txt"; diff "$OUT/cfg-2.txt" "$OUT/cfg-a.txt" >>"$OUT/checks.txt"; }

# (c) Breeze chosen, then a login.
plasma-apply-lookandfeel -a org.kde.breeze.desktop >"$OUT/lnf-c1.log" 2>&1
sleep 4
dump c1-breeze-applied
simulated_login c1
dump c2-after-login-under-breeze
bash "$GATE" status >"$OUT/gate-c-status.txt" 2>&1
expect "(c) snap off" "$(kreadconfig6 --file kwinrc --group Plugins --key plasmafusion-snapEnabled)" ""
expect "(c) attach off" "$(kreadconfig6 --file kwinrc --group Plugins --key plasmafusion-attachEnabled)" ""
expect "(c) outline off" "$(kreadconfig6 --file kwinrc --group Outline --key QmlPath)" ""
expect "(c) switcher KWin's" "$(kreadconfig6 --file kwinrc --group TabBox --key LayoutName)" "thumbnail_grid"
expect "(c) lock-screen drop-in aside" "$(ls "$HOME/.config/systemd/user/plasma-kwin_wayland.service.d" 2>/dev/null)" ""
qdbus-qt6 org.kde.KWin /KWin reconfigure
sleep 2
expect "(c) KWin unloaded snap" "$(qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-snap)" "false"
plasma-apply-lookandfeel -a org.plasmafusion.dark.desktop >"$OUT/lnf-c3.log" 2>&1
sleep 4
simulated_login c3
dump c3-fusion-again
cfgsum >"$OUT/cfg-c3.txt"
# kdeglobals, kcminputrc and kdedefaults/ are the Global Theme applies' business (Breeze's apply
# reverts the user's cursor, which the Fusion themes do not carry): compared without them.
diff <(grep -v -e '^kdeglobals|' -e '^kcminputrc|' -e '^kdedefaults/' "$OUT/cfg-a.txt") <(grep -v -e '^kdeglobals|' -e '^kcminputrc|' -e '^kdedefaults/' "$OUT/cfg-c3.txt") >"$OUT/cfg-c-diff.txt" &&
  echo "(c) PASS every value the check touched is back (kwinrc, drop-in; kdeglobals, kcminputrc, kdedefaults left out)" >>"$OUT/checks.txt" ||
  echo "(c) FAIL values differ, see cfg-c-diff.txt" >>"$OUT/checks.txt"
expect "(c) drop-in back" "$(ls "$HOME/.config/systemd/user/plasma-kwin_wayland.service.d" 2>/dev/null)" "plasma-fusion-lockscreen.conf"
qdbus-qt6 org.kde.KWin /KWin reconfigure
qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start
sleep 2
expect "(c) KWin loaded snap again" "$(qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-snap)" "true"

# (d0) "My previous desktop" made again while Plasma Fusion is live, as fusion-config.sh does on a
# device that was set up before the check existed: the session's XDG_CONFIG_DIRS starts with the live
# ~/.config/kdedefaults (Plasma Fusion's values), which must not leak into the package.
first=$(ls -d "$HOME/.local/state/plasma-fusion"/backup-*/ | head -n 1)
python3 "$T/previous-theme.py" --backup "${first%/}" --data "$OUT/regen" >"$OUT/previous-regen.log" 2>&1
diff "$HOME/.local/share/plasma/look-and-feel/org.plasmafusion.previous.desktop/contents/defaults" \
  "$OUT/regen/plasma/look-and-feel/org.plasmafusion.previous.desktop/contents/defaults" >"$OUT/previous-regen.diff" 2>&1 &&
  echo "(d0) PASS made again under Plasma Fusion: same package as before Plasma Fusion" >>"$OUT/checks.txt" ||
  echo "(d0) FAIL made again under Plasma Fusion: differs, see previous-regen.diff" >>"$OUT/checks.txt"
grep -c -e plasmafusion -e Manrope "$OUT/regen/plasma/look-and-feel/org.plasmafusion.previous.desktop/contents/defaults" |
  sed 's/^/(d0) Plasma Fusion values in the regenerated package: /' >>"$OUT/checks.txt"

# (d) My previous desktop.
plasma-apply-lookandfeel --list >"$OUT/lnf-list.txt" 2>&1
grep -q '^org.plasmafusion.previous.desktop' "$OUT/lnf-list.txt" && echo "(d) PASS listed by plasma-apply-lookandfeel --list" >>"$OUT/checks.txt" ||
  echo "(d) FAIL not listed" >>"$OUT/checks.txt"
plasma-apply-lookandfeel -a org.plasmafusion.previous.desktop >"$OUT/lnf-d.log" 2>&1
sleep 5
qdbus-qt6 org.kde.KWin /KWin reconfigure
sleep 2
dump d-previous
for k in "kdeglobals General ColorScheme" "kdeglobals Icons Theme" "kdeglobals KDE widgetStyle" "kdeglobals General font" \
  "kdeglobals General menuFont" "kdeglobals WM activeFont" "kcminputrc Mouse cursorTheme" "plasmarc Theme name" \
  "kwinrc org.kde.kdecoration2 library" "kwinrc org.kde.kdecoration2 theme" "ksplashrc KSplash Theme"; do
  set -- $k
  was=$(sed -n '/^== 0-breeze-dark-seed$/,/^== /p' "$OUT/state.txt" | grep -m1 -F "$1 [$2] $3 = " | sed 's/^[^=]*= //')
  now=$(kreadconfig6 --file "$1" --group "$2" --key "$3")
  if [ -n "$was" ]; then
    expect "(d) $1 [$2] $3 as before Fusion" "$now" "$was"
  else
    # Unset before (Plasma's built-in font); the package names the system or Plasma default.
    expect "(d) $1 [$2] $3 back to the default font" "${now%%,*}" "Noto Sans"
  fi
done
kwin_deco >>"$OUT/checks.txt"
shot 02-previous
simulated_login d
dump d2-after-login-under-previous
expect "(d) Fusion-only parts off under My previous desktop (snap)" "$(kreadconfig6 --file kwinrc --group Plugins --key plasmafusion-snapEnabled)" ""

# Back to Plasma Fusion Dark, then the compiled decoration for phase 2.
plasma-apply-lookandfeel -a org.plasmafusion.dark.desktop >"$OUT/lnf-e.log" 2>&1
sleep 4
simulated_login e
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.plasmafusion.decoration
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme ""
qdbus-qt6 org.kde.KWin /KWin reconfigure
sleep 3
dump 9-end-phase1
kwin_deco >>"$OUT/checks.txt"
shot 09-cpp-decoration
cp "$HOME/.local/state/plasma-fusion/gate.log" "$OUT/gate.log" 2>/dev/null
