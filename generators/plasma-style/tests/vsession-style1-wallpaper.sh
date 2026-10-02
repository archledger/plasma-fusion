# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# STYLE-1 wallpaper scenario for tools/vsession (sourced inside a private session; test use only).
# Seed: make-style1-seed.sh from a stage built with every wallpaper size (PF_WALLPAPER_SIZES=all).
# Plasma Fusion Dark with the Global Theme layout, then Light: the desktop at rest, to check that the
# picture made for the screen's aspect ratio is used (ridge under the dock, the whole sun).
exec 2>&1
set -x
T=$HOME/pf-tools
export QT_FORCE_STDERR_LOGGING=1
dismiss_launcher() { kcalc >/dev/null 2>&1 & local kc=$!; sleep 4; kill $kc 2>/dev/null; sleep 2; }
bash "$T/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc-install.log" 2>&1
sleep 4; dismiss_launcher
pfinput 'move 300 300' 'sleep 0.5'; shot dark-rest
bash "$T/fusion-config.sh" --light --keep-layout >"$OUT/fc-light.log" 2>&1
sleep 6
pfinput 'move 300 300' 'sleep 0.5'; shot light-rest
# which picture the wallpaper plugin chose (its cache names the file) and the screen size
find "$HOME/.cache" -iname '*plasmafusion*' -o -iname '*wallpaper*' 2>/dev/null | head -20 >"$OUT/wallpaper-cache.txt"
kscreen-doctor -o >"$OUT/outputs.txt" 2>&1
true
