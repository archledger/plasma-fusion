# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Live chips in a private session (real plasmashell and KWin, emulated keys and pointer). The HOME
# holds the stage in ~/pf-stage (with the live chips and quick settings packages of this change)
# and tools/ in ~/pf-tools, and the chips' test tool in ~/pf-chips. The Fusion setup runs (it puts
# the chips before the tray and hides the tray items they replace), then:
#   1. nothing in use but this run's own SSH login (the harness reaches the host over SSH): the
#      SSH chip; in a test container (cvsession.sh) there is no logind and so no login: the widget
#      says it has no logind, and no SSH chip;
#   2. a timed Keep awake (quick settings' debugAction keepawake:SECONDS): its chip with the time
#      left; a click opens quick settings;
#   3. a screen recording (Spectacle's item, fake_status_items.py recording): the time runs, the
#      chip's button finishes it (Activate);
#   4. screen sharing and remote control (the portal's items, fake ones): the capsule's glyphs
#      (and SSH's where there is the login),
#      the panel on hover (a tooltip) and on a click, its rows; Stop sharing and End end them (the
#      menu's End);
#   5. a microphone (a private PipeWire with a virtual source, parecord as "Zoom"): the chip, the
#      status items' ids as the watcher lists them (plasma-pa's microphone item), the panel's Mute
#      mutes the app's stream.
# The test tool and quick settings' stand-in PowerDevil (Keep awake needs one) are in ~/pf-chips.
# The checks read the widget's debug output: the seed's ~/.config/pfv-env has
# QT_LOGGING_RULES=org.plasmafusion.livechips.debug=true.
# Run: tools/vsession/remote.sh chips-1 packages/plasmoids/org.plasmafusion.livechips/tests/vsession/scenario-livechips.sh SEED 1440x900 360
export OUT
set -uo pipefail
set -x
CHK=$OUT/checks.txt
PLOG=$OUT/plasmashell.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
FAKE=$HOME/pf-chips/fake_status_items.py

# The widget's last log line of a kind ("livechips: chips ...").
last() { grep -a "livechips: $1" "$PLOG" | tail -1 | sed "s/.*livechips: $1 //"; }
# The log's length now: a later wait_log looks only at what comes after it (taken before the
# action, so a line logged at once is not missed).
mark() { MARK=$(wc -l <"$PLOG"); }
MARK=0
wait_log() { # PATTERN SECONDS: until the widget logged a line matching PATTERN after the last mark
  local i
  for ((i = 0; i < $2 * 4; i++)); do
    tail -n +"$((MARK + 1))" "$PLOG" | grep -aqE "livechips: $1" && return 0
    sleep 0.25
  done
  return 1
}
# The centre of a chip from the widget's last "chips at" line: NAME -> "X Y".
chip() {
  last "chips at" | tr ';' '\n' | awk -v n="$1" '$1 == n { split($2, p, ","); split($3, s, "x"); printf "%d %d\n", p[1] + s[1] / 2, p[2] + s[2] / 2 }'
}
# The centre of a panel button: ACTION -> "X Y".
button() {
  last "panel" | tr ';' '\n' | grep -F "\"$1\" at" | head -1 | sed 's/.* at //; s/,/ /'
}
widget_js() { # PLUGIN BODY: run BODY for every widget of PLUGIN (w), General group
  evaljs - <<EOF
panels().forEach(function (p) { p.widgets("$1").forEach(function (w) { w.currentConfigGroup = ["General"]; $2 }); });
EOF
}

# ---- PowerDevil's endpoints (quick settings' test stand-in: Keep awake is available with them)
python3 "$HOME/pf-chips/mock_power.py" >"$OUT/mock-power.log" 2>&1 &
sleep 1

# ---- a private PipeWire (no session manager: no real devices) and its Pulse server
pipewire >"$OUT/pipewire.log" 2>&1 &
sleep 1.5
pipewire-pulse >"$OUT/pipewire-pulse.log" 2>&1 &
sleep 1.5
pactl load-module module-null-sink media.class=Audio/Source/Virtual sink_name=fakemic >>"$OUT/pactl.log" 2>&1
info "private pipewire: $(pactl info 2>/dev/null | grep -a 'Server Name' | tr -s ' ')"

# ---- the setup, then the shell again (plasma-pa connects to the Pulse server above)
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1
info "fusion-config rc=$?"
grep -a -x -A3 'Live chips' "$OUT/fc.log" >>"$CHK" || true
pfv_restart_shell 12
evaljs - >"$OUT/bar.txt" 2>>"$OUT/errors.log" <<'EOF'
panels().forEach(function (p) { if (p.location === "top") print(p.widgets().map(function (w) { return w.type; }).join(" ")); });
EOF
order=$(head -1 "$OUT/bar.txt")
info "top bar: $order"
case " $order " in
  *" org.plasmafusion.livechips org.kde.plasma.systemtray "*) pass "setup: the chips sit right before the tray" ;;
  *) fail "setup: the chips are not right before the tray ($order)" ;;
esac

# ---- 1. this run's own SSH login. On the test host (remote.sh) the harness's SSH login is one,
# which logind lists. A test container (cvsession.sh; podman writes /run/.containerenv into every
# container) has no system bus, so no logind and no login.
if [ -f /run/.containerenv ]; then ssh_login=0; else ssh_login=1; fi
sleep 3
info "logins: $(last 'remote logins')"
if [ "$ssh_login" = 1 ]; then
  case "$(last 'state')" in
    *'"capsule":["ssh"]'*'"tint":"ssh"'*) pass "1: the SSH login shows the SSH chip, tinted ($(last 'state'))" ;;
    *) fail "1: no SSH chip ($(last 'state'))" ;;
  esac
else
  case "$(last 'no systemd-logind')|$(last 'state')" in
    '|'* | *'"ssh"'*) fail "1: a test container: logind '$(last 'no systemd-logind')', state $(last 'state')" ;;
    *) pass "1: a test container has no logind (the widget says so) and no SSH chip ($(last 'no systemd-logind'))" ;;
  esac
fi
shot 10-ssh

# ---- 2. a timed Keep awake
mark
widget_js org.plasmafusion.quicksettings 'w.writeConfig("debugAction", "keepawake:1500");'
if wait_log 'state .*"keepAwake":2[45]' 10; then pass "2: a timed Keep awake shows its time left ($(last 'state'))"; else fail "2: no Keep awake chip ($(last 'state'))"; fi
sleep 1
shot 20-keepawake
read -r kx ky <<<"$(chip keepawake)"
info "Keep awake chip at $kx $ky"
if [ -n "${kx:-}" ]; then
  pfinput "click $kx $ky"
  if grep -aq 'quicksettings: openRequest keepawake' "$PLOG"; then pass "2: a click opens quick settings' Keep awake page"; else fail "2: the click opened nothing"; fi
  sleep 1.5
  shot 21-keepawake-page
  pfinput 'key escape'
  sleep 1
fi

# ---- 3. a screen recording
mark
python3 "$FAKE" recording 41 --timeout 120 >"$OUT/fake-recording.log" 2>&1 &
if wait_log 'state .*"recording":"0:4[2-9]"' 10; then pass "3: Spectacle's item shows the recording's time ($(last 'state'))"; else fail "3: no recording chip ($(last 'state'))"; fi
# The chips' places are logged when a chip comes or goes, not each second the time runs on.
wait_log 'chips at .*stop ' 5
mark
sleep 3.5
since=$(tail -n +"$((MARK + 1))" "$PLOG")
places=$(grep -ac 'livechips: chips at' <<<"$since")
states=$(grep -ac 'livechips: state .*"recording":"' <<<"$since")
if [ "$places" -eq 0 ] && [ "$states" -ge 3 ]; then pass "3: the time runs on ($states state lines in 3.5 s), no chip places logged again"
else fail "3: in 3.5 s of recording, $places chip places and $states state lines"; fi
shot 30-recording
read -r sx sy <<<"$(chip stop)"
info "stop button at $sx $sy"
[ -n "${sx:-}" ] && pfinput "click $sx $sy"
sleep 1.5
if grep -q 'activated recording' "$OUT/fake-recording.log"; then pass "3: the chip's button finishes the recording (Activate)"; else fail "3: the button did not reach Spectacle's item"; fi

# ---- 4. screen sharing and remote control
mark
python3 "$FAKE" screen Firefox window --timeout 120 >"$OUT/fake-screen.log" 2>&1 &
python3 "$FAKE" remote RustDesk input --timeout 120 >"$OUT/fake-remote.log" 2>&1 &
if [ "$ssh_login" = 1 ]; then capsule='"capsule":\["remote","screen","ssh"\]' kinds="remote control, screen sharing and SSH"
else capsule='"capsule":\["remote","screen"\]' kinds="remote control and screen sharing"; fi
if wait_log "state .*$capsule" 10; then pass "4: the capsule: $kinds, neutral ($(last 'state'))"; else fail "4: capsule $(last 'state')"; fi
sleep 1
shot 40-capsule
read -r cx cy <<<"$(chip capsule)"
info "capsule at $cx $cy"
# Hover: the panel as the capsule's tooltip (the board's "click or hover").
mark
pfinput "move $cx $cy"
if wait_log 'hover panel ' 6; then pass "4: hovering the capsule shows the panel as its tooltip ($(last 'hover panel' | cut -c1-120))"; else fail "4: no panel on hover"; fi
shot 40b-hover
mark
pfinput "click $cx $cy"
wait_log 'panel ' 5 || true
sleep 1
shot 41-panel
info "panel: $(last 'panel')"
case "$ssh_login|$(last 'panel')" in
  1'|'*'screen "Firefox" "Stop sharing"'*'remote "RustDesk" "End"'*'ssh '*) pass "4: the panel names the apps with their actions, and the login" ;;
  0'|'*'ssh '*) fail "4: a login row in a test container: $(last 'panel')" ;;
  0'|'*'screen "Firefox" "Stop sharing"'*'remote "RustDesk" "End"'*) pass "4: the panel names the apps with their actions (no login in a test container)" ;;
  *) fail "4: panel rows: $(last 'panel')" ;;
esac
read -r bx by <<<"$(button 'Stop sharing')"
mark
[ -n "${bx:-}" ] && pfinput "click $bx $by"
sleep 2
if grep -q 'ended screen' "$OUT/fake-screen.log"; then pass "4: Stop sharing ends the session (the item's menu End)"; else fail "4: Stop sharing did not reach the item"; fi
wait_log 'panel ' 4 || true
read -r bx by <<<"$(button 'End')"
[ -n "${bx:-}" ] && pfinput "click $bx $by"
sleep 2
if grep -q 'ended remote' "$OUT/fake-remote.log"; then pass "4: End ends remote control"; else fail "4: End did not reach the item"; fi
pfinput 'key escape'
sleep 1

# ---- 5. a microphone
mark
parecord --raw --device=fakemic --client-name=Zoom --property=application.name=Zoom /dev/null >"$OUT/parecord.log" 2>&1 &
rec=$!
if wait_log 'state .*"capsule":\[[^]]*"microphone"' 10; then pass "5: an app recording shows the microphone ($(last 'state'))"; else fail "5: no microphone chip ($(last 'state'))"; fi
sleep 1
shot 50-microphone
# The status items as the watcher lists them (plasma-pa's microphone item is up now): their ids are
# what the tray hides.
python3 - >>"$CHK" <<'PY'
import dbus
bus = dbus.SessionBus()
w = bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
for entry in w.Get("org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems", dbus_interface="org.freedesktop.DBus.Properties"):
    service, path = entry.split("/", 1)
    try:
        p = bus.get_object(service, "/" + path).GetAll("org.kde.StatusNotifierItem", dbus_interface="org.freedesktop.DBus.Properties")
        print("INFO status item id %r title %r" % (str(p.get("Id")), str(p.get("Title"))))
    except dbus.DBusException as e:
        print("INFO status item %s: %s" % (entry, e.get_dbus_name()))
PY
read -r cx cy <<<"$(chip capsule)"
mark
pfinput "click $cx $cy"
wait_log 'panel ' 5 || true
sleep 1
shot 51-microphone-panel
read -r bx by <<<"$(button 'Mute')"
info "Mute at ${bx:-?} ${by:-?}"
[ -n "${bx:-}" ] && pfinput "click $bx $by"
sleep 1.5
if pactl list source-outputs 2>/dev/null | grep -aq 'Mute: yes'; then pass "5: Mute mutes Zoom's stream"; else fail "5: the stream is not muted ($(pactl list source-outputs 2>/dev/null | grep -a 'Mute:' | tr '\n' ' '))"; fi
shot 52-muted
mark
kill "$rec" 2>/dev/null
if wait_log 'state \{"capsule":\[[^]]*\]' 10 && ! last 'state' | grep -q microphone; then pass "5: the chip goes with the recording ($(last 'state'))"; else fail "5: still $(last 'state')"; fi
pfinput 'key escape'
info "done"
