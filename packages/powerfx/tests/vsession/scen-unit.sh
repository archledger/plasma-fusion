# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plasma-fusion-powerfx.service under a real systemd user manager, in a private Plasma session
# (tools/vsession), sourced by vsession.sh. Same seed as scen-tiers.sh. Needs sudo -n for one thing:
# a transient system unit o1pw-um-* (Delegate=yes) that runs a second `systemd --user` for this
# user with the session's private HOME, runtime directory and D-Bus bus, so the logged-in user's
# own manager is never used. Stand-ins in the private HOME: graphical-session.target without its
# basic.target requirement, an idle start target, and every unit the stock user targets would pull
# in masked (sockets, timers, pipewire...). The power state comes from mock-power.py on a private
# "system" bus. Checks: enable/disable through [Install], start with the session target, the tier
# applied, Nice, slice, memory, reload, Restart=on-failure with ExecStopPost in between, PartOf stop
# giving every value back, ConditionEnvironment.
# Results: out/results.txt, um-*.txt.
# shellcheck shell=bash
# shellcheck disable=SC2024  # sudo runs the command; its output belongs to this user's files
exec 2>&1
T=$HOME/pf-powerfx
UM=o1pw-um-${PFV##*/}
UD=$HOME/.config/systemd/user
N=0
res() { N=$((N + 1)); echo "$1 $N $2" >>"$OUT/results.txt"; }
check() { local d=$1; shift; if "$@"; then res ok "$d"; else res "not ok" "$d"; fi; }
wait_for() { local end=$((SECONDS + $1)); shift; until "$@"; do [ "$SECONDS" -ge "$end" ] && return 1; sleep 0.2; done; }
blur() { qdbus org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded blur 2>/dev/null; }
rc() { kreadconfig6 --file "$1" --group "$2" --key "$3" --default -; }
dock_magnify() {
  evaljs - <<'JS'
var ps = panels(), v = "none"; for (var i = 0; i < ps.length; i++) { var ws = ps[i].widgets("org.plasmafusion.dock");
  for (var j = 0; j < ws.length; j++) { ws[j].currentConfigGroup = ["General"]; v = String(ws[j].readConfig("magnify", "-")); } }
print(v);
JS
}
# Only ever the private manager: its socket lives in this session's runtime directory.
usys() {
  [ -S "$PFV/run/systemd/private" ] || { echo "no private manager" >&2; return 1; }
  XDG_RUNTIME_DIR=$PFV/run systemctl --user "$@"
}
prop() { usys show -p "$2" --value "$1"; }
stop_um() {
  sudo -n systemctl stop "$UM" 2>/dev/null
  sudo -n systemctl reset-failed "$UM" 2>/dev/null
  # the manager leaves mode-0 entries in its runtime directory; let the harness remove them
  chmod -R u+rwx "$PFV/run/systemd" 2>/dev/null
  return 0
}
# bail TEXT: record a failure, collect the manager's journal, stop everything this scenario started
bail() {
  res "not ok" "$1 (the remaining checks were skipped)"
  sudo -n journalctl -u "$UM" --since "$T0" --no-pager -o short-precise >"$OUT/um-journal.txt" 2>&1
  stop_um; kill "$MOCKP" "$SYSBUS" 2>/dev/null
}

bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fusion-config.log" 2>&1
echo "fusion-config rc=$?" >>"$OUT/fusion-config.log"
kquitapp6 plasmashell >/dev/null 2>&1; sleep 2
plasmashell >>"$OUT/plasmashell2.log" 2>&1 &
wait_for_name org.kde.plasmashell
qdbus org.kde.KWin /KWin reconfigure
sleep 12
check "the unit is in ~/.config/systemd/user" test -f "$UD/plasma-fusion-powerfx.service"

# stand-ins and masks, all in the private HOME
printf '[Unit]\nDescription=Plasma Fusion test: idle start of a private manager\nDefaultDependencies=no\n' >"$UD/o1pw-idle.target"
printf '[Unit]\nDescription=Plasma Fusion test: stand-in for the graphical session\nDefaultDependencies=no\n' >"$UD/graphical-session.target"
for u in drkonqi-coredump-launcher.socket systemd-ask-password.socket systemd-importd.socket systemd-machined.socket \
  drkonqi-coredump-cleanup.timer drkonqi-coredump-cleanup.service drkonqi-sentry-postman.timer drkonqi-sentry-postman.path \
  drkonqi-coredump-pickup.service systemd-tmpfiles-setup.service systemd-tmpfiles-clean.timer dbus.socket pipewire.socket \
  pipewire-pulse.socket grub-boot-success.timer kunifiedpush-distributor.service spice-vdagent.service uresourced.service \
  xdg-user-dirs.service gnome-initial-setup-copy-worker.service unity-gtk-module.service; do
  ln -sfn /dev/null "$UD/$u"
done

# mock power daemons on a private "system" bus
cat >"$PFV/sysbus.conf" <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:path=$PFV/run/o1pw-system.sock</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>
EOF
dbus-daemon --nofork --config-file="$PFV/sysbus.conf" >"$OUT/sysbus.log" 2>&1 &
SYSBUS=$!
wait_for 5 test -S "$PFV/run/o1pw-system.sock"
MOCK=unix:path=$PFV/run/o1pw-system.sock
python3 "$T/mock-power.py" --address "$MOCK" --on-battery --percentage 8 >"$OUT/mock-power.out" 2>&1 &
MOCKP=$!
wait_for 10 grep -q ready "$OUT/mock-power.out"
pct() { DBUS_SYSTEM_BUS_ADDRESS=$MOCK busctl --system set-property org.freedesktop.UPower /org/freedesktop/UPower/devices/DisplayDevice org.freedesktop.UPower.Device Percentage d "$1"; }

T0=$(date '+%Y-%m-%d %H:%M:%S')
echo "$T0" >"$OUT/um-start-time.txt"
# The SELinux context of the user's own manager (user@.service gets it from PAM); from a plain system
# unit the manager would run as init_t and could not read the private HOME.
sudo -n systemd-run --quiet --unit="$UM" --uid="$(id -u)" --gid="$(id -g)" \
  -p Delegate=yes -p TimeoutStopSec=20 -p SELinuxContext="$(id -Z)" \
  --setenv=HOME="$HOME" --setenv=XDG_RUNTIME_DIR="$PFV/run" \
  --setenv=DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" --setenv=DBUS_SYSTEM_BUS_ADDRESS="$MOCK" \
  --setenv=XDG_CONFIG_DIRS="$XDG_CONFIG_DIRS" --setenv=XDG_CURRENT_DESKTOP=KDE --setenv=LANG=en_US.UTF-8 \
  /usr/lib/systemd/systemd --user --unit=o1pw-idle.target >"$OUT/um-run.txt" 2>&1
echo "systemd-run rc=$?" >>"$OUT/um-run.txt"
if ! wait_for 15 test -S "$PFV/run/systemd/private"; then
  bail "the private user manager did not start (see um-journal.txt)"
  return 0 2>/dev/null || exit 0
fi
sleep 1
usys show -p Version -p Environment -p SystemState >"$OUT/um-manager.txt" 2>&1
check "private manager: plasma-fusion-powerfx.service is found and disabled" [ "$(usys is-enabled plasma-fusion-powerfx.service 2>&1)" = disabled ]
usys enable plasma-fusion-powerfx.service >"$OUT/um-enable.txt" 2>&1
check "enable: the [Install] link in graphical-session.target.wants" test -L "$UD/graphical-session.target.wants/plasma-fusion-powerfx.service"
usys start graphical-session.target
if ! wait_for 10 bash -c "[ \"\$(XDG_RUNTIME_DIR=$PFV/run systemctl --user show -p ActiveState --value plasma-fusion-powerfx.service)\" = active ]"; then
  usys status --no-pager plasma-fusion-powerfx.service >"$OUT/um-status-1.txt" 2>&1
  bail "session start: the service did not become active"
  return 0 2>/dev/null || exit 0
fi
res ok "session start: the service is active"
check "session start at 8 %: critical applied (blur unloaded, magnify false)" wait_for 10 bash -c "[ \"\$(qdbus org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded blur)\" = false ]"
sleep 2
check "session start at 8 %: dock magnify false, Tier critical" [ "$(dock_magnify)/$(rc plasmafusionrc Power Tier)" = false/critical ]
PID=$(prop plasma-fusion-powerfx.service MainPID)
{ usys status --no-pager plasma-fusion-powerfx.service; echo; usys show -p MainPID -p NRestarts -p MemoryCurrent -p MemoryMax -p MemoryPeak \
    -p Slice -p ControlGroup -p Nice -p KillMode -p ExecMainStartTimestamp plasma-fusion-powerfx.service;
  echo; ps -o pid,ni,rss,comm -p "$PID" --ppid "$PID"; cat "/proc/$PID/cgroup"; tr '\0' '\n' <"/proc/$PID/environ" | grep -E '^(PATH|DBUS_|XDG_RUNTIME|JOURNAL_STREAM)='; } >"$OUT/um-status-1.txt" 2>&1
check "the service runs at nice 10" [ "$(ps -o ni= -p "$PID" | tr -d ' ')" = 10 ]
check "the service is in background.slice" grep -q 'background.slice' "/proc/$PID/cgroup"
check "the unit's memory is under MemoryMax (32M)" [ "$(prop plasma-fusion-powerfx.service MemoryCurrent)" -lt 33554432 ]
usys reload plasma-fusion-powerfx.service
sleep 2
check "reload: same process, still active" [ "$(prop plasma-fusion-powerfx.service MainPID)/$(prop plasma-fusion-powerfx.service ActiveState)" = "$PID/active" ]
# a crash: Restart=on-failure after 5 s; ExecStopPost gives the values back meanwhile
[ "${PID:-0}" -gt 1 ] 2>/dev/null || { bail "no main PID ($PID)"; return 0 2>/dev/null || exit 0; }
kill -9 "$PID"
sleep 2
check "crash: ExecStopPost gave blur back while it restarts" [ "$(blur)" = true ]
check "crash: restarted by systemd (NRestarts 1, new process)" wait_for 12 bash -c "[ \"\$(XDG_RUNTIME_DIR=$PFV/run systemctl --user show -p NRestarts --value plasma-fusion-powerfx.service)\" = 1 ] && [ \"\$(XDG_RUNTIME_DIR=$PFV/run systemctl --user show -p ActiveState --value plasma-fusion-powerfx.service)\" = active ]"
check "crash: critical again after the restart" wait_for 10 bash -c "[ \"\$(qdbus org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded blur)\" = false ]"
pct 50
check "50 %: full, blur back" wait_for 5 bash -c "[ \"\$(qdbus org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded blur)\" = true ]"
pct 8
check "8 % again: critical" wait_for 5 bash -c "[ \"\$(qdbus org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded blur)\" = false ]"
sleep 2
t0=$EPOCHREALTIME
usys stop graphical-session.target
t1=$EPOCHREALTIME
echo "graphical-session.target stop took $(python3 -c "print(round(($t1 - $t0) * 1000))") ms" >>"$OUT/um-timing.txt"
check "session stop (PartOf): the service is inactive" [ "$(prop plasma-fusion-powerfx.service ActiveState)" = inactive ]
check "session stop: ExecStopPost gave everything back (blur, magnify, Tier full)" \
  [ "$(blur)/$(dock_magnify)/$(rc plasmafusionrc Power Tier)/$(rc kwinrc Plugins blurEnabled)" = true/true/full/- ]
usys show -p Result -p ExecMainStatus plasma-fusion-powerfx.service >"$OUT/um-status-2.txt" 2>&1
check "session stop: the unit did not fail" [ "$(prop plasma-fusion-powerfx.service Result)" = success ]
# another desktop: ConditionEnvironment keeps it off
usys set-environment XDG_CURRENT_DESKTOP=GNOME
usys start graphical-session.target
sleep 2
usys show -p ActiveState -p ConditionResult plasma-fusion-powerfx.service >"$OUT/um-status-3.txt" 2>&1
check "XDG_CURRENT_DESKTOP=GNOME: the service does not start (ConditionEnvironment)" \
  [ "$(prop plasma-fusion-powerfx.service ActiveState)/$(prop plasma-fusion-powerfx.service ConditionResult)" = inactive/no ]
usys stop graphical-session.target
usys set-environment XDG_CURRENT_DESKTOP=KDE
usys disable plasma-fusion-powerfx.service >"$OUT/um-disable.txt" 2>&1
check "disable: the link is gone" test ! -e "$UD/graphical-session.target.wants/plasma-fusion-powerfx.service"
stop_um
check "the private manager is gone" bash -c "! sudo -n systemctl is-active --quiet '$UM'"
sudo -n journalctl -u "$UM" --since "$T0" --no-pager -o short-precise >"$OUT/um-journal.txt" 2>&1
sudo -n journalctl -t plasma-fusion-powerfx --since "$T0" --no-pager -o short-precise >"$OUT/um-powerfx-journal.txt" 2>&1
kill "$MOCKP" "$SYSBUS" 2>/dev/null
echo "done" >>"$OUT/results.txt"
