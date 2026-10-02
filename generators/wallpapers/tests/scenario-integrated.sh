# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Foundation parts inside the whole Plasma Fusion desktop (test only). Seed: make-seed.sh --all.
# Every part is built into the seed and applied with tools/device/fusion-config.sh inside the
# private session (dark, then --light); Konsole and KWrite get the Plasma Fusion profile/theme.
T=$HOME/pf-tools
export XDG_CONFIG_DIRS=$HOME/.config/kdedefaults:/etc/xdg QT_FORCE_STDERR_LOGGING=1
exec 2>&1
set -x
kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile "Plasma Fusion.profile"
kwriteconfig6 --file kwriterc --group "KTextEditor Renderer" --key "Auto Color Theme Selection" false
for v in dark light; do
  if [ $v = dark ]; then bash "$T/fusion-config.sh" > "$OUT/config-$v.log" 2>&1; KT="Plasma Fusion Dark"
  else bash "$T/fusion-config.sh" --light > "$OUT/config-$v.log" 2>&1; KT="Plasma Fusion Light"; fi
  python3 "$T/merge-kdedefaults.py" kwinrc kcminputrc >> "$OUT/merge.log" 2>&1
  qdbus org.kde.KWin /KWin reconfigure
  source "$T/dismiss-launcher.sh"
  sleep 4
  shot int-$v-01-desktop
  systemsettings kcm_colors > "$OUT/int-ss-$v.log" 2>&1 & P=$!; sleep 8; shot int-$v-02-colors; kill $P; sleep 1
  dolphin --new-window $HOME/Pictures/Wallpapers > "$OUT/int-dolphin-$v.log" 2>&1 & P=$!; sleep 6; shot int-$v-03-dolphin; kill $P; sleep 1
  konsole -e bash $HOME/test/demo.sh > "$OUT/int-konsole-$v.log" 2>&1 & P=$!; sleep 5; shot int-$v-04-konsole; kill $P; sleep 1
  kwriteconfig6 --file kwriterc --group "KTextEditor Renderer" --key "Color Theme" "$KT"
  kwrite $HOME/test/sample.qml > "$OUT/int-kwrite-$v.log" 2>&1 & P=$!; sleep 5; shot int-$v-05-kwrite; kill $P; sleep 1
done
cp ~/.config/kdeglobals "$OUT/int-kdeglobals.txt"
cp "$HOME/.local/state/plasma-fusion/plasmashell.log" "$OUT/plasmashell-restarted.log" 2>/dev/null
