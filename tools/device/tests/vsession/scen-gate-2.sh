# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Login check, integrated phase 2 (tools/vsession scenario, same HOME as phase 1; test tooling).
# Before this session started, login-sim.sh ran a login with faked KWin and kscreenlocker versions.
# (b) KWin must start with the Aurorae Plasma Fusion theme, the lock-screen drop-in must be aside,
# and the queued notification must show once the desktop is up (what the notify unit runs).
exec 2>&1
set -x
GATE=$HOME/.local/share/plasma-fusion/gate/plasma-fusion-gate.sh
. "$HOME/pf-tools/device/tests/vsession/gate-common.sh"
dump 5-after-faked-update-login
expect "(b) KWin started with Aurorae" "$(kwin_deco)" "decoration Plugin: org.kde.kwin.aurorae.v2 Theme: __aurorae__svg__PlasmaFusionDark "
expect "(b) lock-screen drop-in aside" "$(ls "$HOME/.config/systemd/user/plasma-kwin_wayland.service.d" 2>/dev/null)" ""
expect "(b) Fusion-only parts stay on (snap loaded)" "$(qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-snap)" "true"
expect "(b) notification queued" "$(head -n1 "$HOME/.local/state/plasma-fusion/gate/notify" 2>/dev/null)" "Safe mode after a Plasma change"
cp "$HOME/.local/state/plasma-fusion/gate/notify" "$OUT/notify-queued.txt" 2>/dev/null
bash "$GATE" status >"$OUT/gate-b-status.txt" 2>&1
shot 05a-safe-mode-desktop
# ExecStart of plasma-fusion-gate-notify.service:
bash "$GATE" notify &
notifier=$!
sleep 4
shot 05b-notification
wait "$notifier"
expect "(b) notification shown and dequeued" "$(ls "$HOME/.local/state/plasma-fusion/gate/notify" 2>/dev/null)" ""
grep ' notify: ' "$HOME/.local/state/plasma-fusion/gate.log" >>"$OUT/checks.txt"
# A second login with the same (faked) versions queues nothing new and changes nothing.
cfgsum >"$OUT/cfg-b1.txt"
PF_GATE_FAKE_VERSIONS="kwin=6.8.0 kscreenlocker=6.8.0" simulated_login b2
cfgsum >"$OUT/cfg-b2.txt"
cmp -s "$OUT/cfg-b1.txt" "$OUT/cfg-b2.txt" && echo "PASS (b) second mismatching login changes nothing" >>"$OUT/checks.txt" ||
  echo "FAIL (b) second mismatching login changed the config" >>"$OUT/checks.txt"
expect "(b) no second notification" "$(ls "$HOME/.local/state/plasma-fusion/gate/notify" 2>/dev/null)" ""
cp "$HOME/.local/state/plasma-fusion/gate.log" "$OUT/gate.log" 2>/dev/null
