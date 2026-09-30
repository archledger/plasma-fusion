# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Login check, integrated phase 3 (same HOME; test tooling). Before this session, login-sim.sh ran
# a login with the real (tested) versions: (b) everything must be back; (a) another login changes
# nothing; then fusion-restore.sh removes the check and gives back the Breeze Dark seed.
exec 2>&1
set -x
. "$HOME/pf-tools/device/tests/vsession/gate-common.sh"
dump 6-after-matching-login
expect "(b) KWin started with the compiled decoration again" "$(kwin_deco)" "decoration Plugin: org.plasmafusion.decoration Theme:  "
expect "(b) lock-screen drop-in back" "$(ls "$HOME/.config/systemd/user/plasma-kwin_wayland.service.d" 2>/dev/null)" "plasma-fusion-lockscreen.conf"
expect "(b) no records left" "$(ls "$HOME/.local/state/plasma-fusion/gate/off" 2>/dev/null)" ""
shot 06-restored
cfgsum >"$OUT/cfg-6.txt"
simulated_login a2
cfgsum >"$OUT/cfg-6a.txt"
cmp -s "$OUT/cfg-6.txt" "$OUT/cfg-6a.txt" && echo "(a) PASS matching login changes nothing (after a restore)" >>"$OUT/checks.txt" ||
  echo "(a) FAIL matching login changed the config" >>"$OUT/checks.txt"
cp "$HOME/.local/state/plasma-fusion/gate.log" "$OUT/gate.log" 2>/dev/null
bash "$HOME/pf-tools/device/fusion-restore.sh" --dry-run >"$OUT/restore-dry.log" 2>&1
bash "$HOME/pf-tools/device/fusion-restore.sh" >"$OUT/restore.log" 2>&1
echo "fusion-restore rc=$?" >>"$OUT/checks.txt"
sleep 8
dump 7-after-fusion-restore
expect "restore: Breeze Dark again" "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)" "org.kde.breezedark.desktop"
expect "restore: user font again" "$(kreadconfig6 --file kdeglobals --group General --key font)" "Noto Sans,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
expect "restore: env stub removed" "$(ls "$HOME/.config/plasma-workspace/env" 2>/dev/null)" ""
expect "restore: notify unit removed" "$(ls "$HOME/.config/systemd/user" 2>/dev/null | tr '\n' ' ')" ""
expect "restore: engine removed" "$(ls "$HOME/.local/share/plasma-fusion/gate" 2>/dev/null)" ""
expect "restore: records removed, log kept" "$(ls "$HOME/.local/state/plasma-fusion/gate" 2>/dev/null)/$(ls "$HOME/.local/state/plasma-fusion/gate.log" 2>/dev/null | wc -l)" "/1"
expect "restore: My previous desktop stays installed" "$([ -f "$HOME/.local/share/plasma/look-and-feel/org.plasmafusion.previous.desktop/metadata.json" ] && echo yes)" "yes"
cfgsum >"$OUT/cfg-7.txt"
if [ -f "$HOME/pf-test/cfg-0.txt" ]; then
  diff "$HOME/pf-test/cfg-0.txt" "$OUT/cfg-7.txt" >"$OUT/cfg-0-7-diff.txt" &&
    echo "PASS restore: every value of the seed is back (cfg-0 = cfg-7)" >>"$OUT/checks.txt" ||
    echo "FAIL restore: values differ from the seed, see cfg-0-7-diff.txt" >>"$OUT/checks.txt"
fi
shot 07-after-restore
