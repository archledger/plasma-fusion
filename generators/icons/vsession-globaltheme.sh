# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Icons in context: applies the Plasma Fusion Dark Global Theme inside a private session, with
# ~/.config/kdedefaults in XDG_CONFIG_DIRS as startplasma sets it, then shows the desktop, the
# launcher and Dolphin. Seed HOME: STAGE=$SEED bash tools/build.sh (all parts), plus the colour
# scheme and fonts in ~/.local/share/{color-schemes,fonts}.
#   tools/vsession/remote.sh ic-5 generators/icons/vsession-globaltheme.sh $SEED 1440x900 200
exec 2>>"$OUT/scenario-trace.log"
set -x
mine() { for p in $(pgrep -x "$1"); do grep -qz "^XDG_RUNTIME_DIR=$PFV/run\$" /proc/$p/environ 2>/dev/null && echo "$p"; done; }
xdg-user-dirs-update >/dev/null 2>&1
plasma-apply-colorscheme PlasmaFusionDark > "$OUT/apply-colors.log" 2>&1
plasma-apply-lookandfeel -a org.plasmafusion.dark.desktop --resetLayout > "$OUT/apply-lnf.log" 2>&1
sleep 4
# startplasma puts ~/.config/kdedefaults (where Global Themes write) in XDG_CONFIG_DIRS; do the same here
export XDG_CONFIG_DIRS="$HOME/.config/kdedefaults:/etc/xdg"
kquitapp6 plasmashell >/dev/null 2>&1
sleep 2
plasmashell >"$OUT/plasmashell-2.log" 2>&1 &
wait_for_name org.kde.plasmashell
sleep 10
kreadconfig6 --file kdeglobals --group Icons --key Theme > "$OUT/icon-theme.txt"
shot 01-fusion-desktop
qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu >/dev/null 2>&1
sleep 3
shot 02-fusion-launcher
qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.activateLauncherMenu >/dev/null 2>&1
sleep 1
dolphin --new-window "$HOME" >"$OUT/dolphin.log" 2>&1 &
sleep 7
shot 03-fusion-dolphin
kill $(mine dolphin) 2>/dev/null
sleep 1
