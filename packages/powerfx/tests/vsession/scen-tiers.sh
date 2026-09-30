# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plasma-fusion-powerfx in a private Plasma session (tools/vsession), sourced by vsession.sh. The
# seed HOME holds the built HOME tree at ~/pf-stage, the tools tree at ~/pf-tools and
# packages/powerfx/tests at ~/pf-powerfx. Checks (EFFECTS.md 8.4, X6):
#   1. fusion-config.sh --install puts the service and its unit in place;
#   2. --apply saver, critical, full against the real KWin and plasmashell: the loaded effects,
#      kwinrc, the widgets' keys, a screenshot per tier; the files after full against before;
#   3. the running service on a private "system" bus with mock-power.py: battery events, the time
#      from event to blur unloaded, a plasmashell restart, a layout reset plus reload, a user's
#      change while overridden, CPU and memory while idle, SIGTERM.
# Results: out/results.txt (ok / not ok lines), state-*.txt, snap-*/, diff-*.txt, journal.log.
# shellcheck shell=bash
exec 2>&1
PFX=$HOME/.local/libexec/plasma-fusion/plasma-fusion-powerfx
T=$HOME/pf-powerfx
N=0
res() { N=$((N + 1)); echo "$1 $N $2" >>"$OUT/results.txt"; }
check() { local d=$1; shift; if "$@"; then res ok "$d"; else res "not ok" "$d"; fi; }
wait_for() { local end=$((SECONDS + $1)); shift; until "$@"; do [ "$SECONDS" -ge "$end" ] && return 1; sleep 0.1; done; }
# The script's journal lines go to out/journal.log, not to the machine's journal.
mkdir -p "$PFV/bin"
printf '#!/bin/sh\nshift 2; [ "$1" = -- ] && shift; echo "$(date +%%T.%%3N) $*" >>%s\n' "$OUT/journal.log" >"$PFV/bin/logger"
chmod +x "$PFV/bin/logger"
export PATH=$PFV/bin:$PATH
: >"$OUT/journal.log"
jl() { wc -l <"$OUT/journal.log"; }
wait_log() { wait_for "${3:-8}" bash -c "tail -n +$(($1 + 1)) '$OUT/journal.log' | grep -q -- \"\$0\"" "$2"; }
blur() { qdbus org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded blur 2>/dev/null; }
rc() { kreadconfig6 --file "$1" --group "$2" --key "$3" --default -; }
widgets() { # one line per Fusion widget: type id powerTier magnify glass (- when unset)
  evaljs - <<'JS'
var cs = desktops().concat(panels()), out = [];
for (var i = 0; i < cs.length; i++) { var ws = cs[i].widgets();
  for (var j = 0; j < ws.length; j++) { var w = ws[j];
    if (String(w.type).indexOf("org.plasmafusion.") !== 0 && String(w.type).indexOf("org.kde.plasma.systemmonitor") !== 0) continue;
    w.currentConfigGroup = ["General"];
    out.push(w.type + " " + w.id + " powerTier=" + w.readConfig("powerTier", "-") + " magnify=" + w.readConfig("magnify", "-") + " glass=" + w.readConfig("glass", "-"));
  } }
print(out.join("\n"));
JS
}
wkey() { widgets | awk -v t="$1" -v k="$2" '$1 == t { for (i = 3; i <= NF; i++) if (index($i, k "=") == 1) { print substr($i, length(k) + 2); exit } }'; }
dump() {
  { echo "== $1 $(date +%T.%3N)"; echo "blur loaded: $(blur)"; echo "kwinrc blurEnabled=$(rc kwinrc Plugins blurEnabled)"
    sed -n '/^\[Power\]/,/^\[/p' "$HOME/.config/plasmafusionrc" 2>/dev/null; widgets; } >"$OUT/state-$1.txt"
}
snap() {
  mkdir -p "$OUT/snap-$1"
  for f in kwinrc kdeglobals plasmafusionrc plasma-org.kde.plasma.desktop-appletsrc; do
    [ -f "$HOME/.config/$f" ] && cp "$HOME/.config/$f" "$OUT/snap-$1/"
  done
}

# ---- 1. install ----
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fusion-config.log" 2>&1
echo "fusion-config rc=$?" >>"$OUT/fusion-config.log"
check "installed: the service in ~/.local/libexec/plasma-fusion" test -x "$PFX"
check "installed: the unit in ~/.config/systemd/user (from the .config templates)" \
  cmp -s "$HOME/pf-stage/.config/systemd/user/plasma-fusion-powerfx.service" "$HOME/.config/systemd/user/plasma-fusion-powerfx.service"
kquitapp6 plasmashell >/dev/null 2>&1; sleep 2
plasmashell >>"$OUT/plasmashell2.log" 2>&1 &
wait_for_name org.kde.plasmashell
qdbus org.kde.KWin /KWin reconfigure
sleep 15
check "the Fusion layout has a dock and a system card" [ -n "$(wkey org.plasmafusion.dock powerTier)" ] && [ -n "$(wkey org.plasmafusion.systemcard powerTier)" ]
dump 0-installed
check "blur loaded at the start" [ "$(blur)" = true ]
shot 00-full-before

# ---- 2. --apply, each tier ----
snap before
bash "$PFX" --apply saver >"$OUT/apply-saver.log" 2>&1; echo "rc=$?" >>"$OUT/apply-saver.log"
sleep 2; dump 1-saver
check "saver: dock and card powerTier 1" [ "$(wkey org.plasmafusion.dock powerTier)/$(wkey org.plasmafusion.systemcard powerTier)" = 1/1 ]
check "saver: blur loaded, magnification not turned off" bash -c "[ '$(blur)' = true ] && [ '$(wkey org.plasmafusion.dock magnify)' != false ]"
bash "$PFX" --apply critical >"$OUT/apply-critical.log" 2>&1; echo "rc=$?" >>"$OUT/apply-critical.log"
sleep 3; dump 2-critical
check "critical: exit 0" grep -qx 'rc=0' "$OUT/apply-critical.log"
check "critical: blur unloaded, kwinrc blurEnabled=false" [ "$(blur)/$(rc kwinrc Plugins blurEnabled)" = false/false ]
check "critical: dock magnify false, powerTier 2, glass solid" \
  [ "$(wkey org.plasmafusion.dock magnify)/$(wkey org.plasmafusion.dock powerTier)/$(wkey org.plasmafusion.dock glass)" = false/2/solid ]
check "critical: system card powerTier 2, glass solid" [ "$(wkey org.plasmafusion.systemcard powerTier)/$(wkey org.plasmafusion.systemcard glass)" = 2/solid ]
shot 02-critical
bash "$PFX" --apply full >"$OUT/apply-full.log" 2>&1; echo "rc=$?" >>"$OUT/apply-full.log"
sleep 3; dump 3-full
snap after
check "full: blur loaded again" [ "$(blur)" = true ]
check "full: dock magnify true, powerTier 0, glass full" \
  [ "$(wkey org.plasmafusion.dock magnify)/$(wkey org.plasmafusion.dock powerTier)/$(wkey org.plasmafusion.dock glass)" = true/0/full ]
check "full: kwinrc byte for byte as before" cmp -s "$OUT/snap-before/kwinrc" "$HOME/.config/kwinrc"
check "full: kdeglobals byte for byte as before" cmp -s "$OUT/snap-before/kdeglobals" "$HOME/.config/kdeglobals"
diff "$OUT/snap-before/plasmafusionrc" "$HOME/.config/plasmafusionrc" >"$OUT/diff-plasmafusionrc.txt"
diff "$OUT/snap-before/plasma-org.kde.plasma.desktop-appletsrc" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" >"$OUT/diff-appletsrc.txt"
check "full: plasmafusionrc differs only in [Power]" \
  bash -c "! grep -E '^[<>]' '$OUT/diff-plasmafusionrc.txt' | grep -vE '^[<>] ?(\[Power\]|Tier=.*|ShellTier=.*|ShellLighter=.*)?\$'"
# (new [General] groups appear with their header and a blank line)
check "full: appletsrc differs only by added keys at their defaults (powerTier=0, magnify=true, glass=full)" \
  bash -c "! grep -E '^[<>]' '$OUT/diff-appletsrc.txt' | grep -vE '^> ?(powerTier=0|magnify=true|glass=full|\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]\[Configuration\]\[General\])?\$'"
shot 03-full-after

# ---- 3. the running service, on a private "system" bus with the mock daemons ----
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
python3 "$T/mock-power.py" --address "$MOCK" --on-battery --percentage 50 >"$OUT/mock-power.out" 2>&1 &
MOCKP=$!
wait_for 10 grep -q ready "$OUT/mock-power.out"
pct() { DBUS_SYSTEM_BUS_ADDRESS=$MOCK busctl --system set-property org.freedesktop.UPower /org/freedesktop/UPower/devices/DisplayDevice org.freedesktop.UPower.Device Percentage d "$1"; }
onbat() { DBUS_SYSTEM_BUS_ADDRESS=$MOCK busctl --system set-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery b "$1"; }
DBUS_SYSTEM_BUS_ADDRESS=$MOCK bash "$PFX" 2>"$OUT/service.stderr" &
SVC=$!
sleep 3
kids() { ps -o pid= --ppid "$1" | while read -r p; do echo "$p"; kids "$p"; done; }
check "service: bash plus three gdbus monitors" [ "$(for p in $(kids "$SVC"); do ps -o comm= -p "$p"; done | grep -c '^gdbus$')" = 3 ]
check "service at 50 % on battery: full" [ "$(rc plasmafusionrc Power Tier)" = full ]
j=$(jl); pct 15
check "15 %: saver" wait_log "$j" 'tier saver (on battery, 15 %'
j=$(jl); t0=$EPOCHREALTIME; pct 8
wait_for 5 bash -c '[ "$(qdbus org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded blur)" = false ]'; t1=$EPOCHREALTIME
check "8 %: critical" wait_log "$j" 'tier critical (on battery, 8 %'
echo "blur unloaded $(python3 -c "print(round(($t1 - $t0) * 1000))") ms after the Percentage event" >>"$OUT/timing.txt"
check "8 %: dock magnify false" [ "$(wkey org.plasmafusion.dock magnify)" = false ]
dump 4-service-critical
# a plasmashell restart: the values stay (they are in the config), the service sees the new shell
pfv_restart_shell 10
check "after a plasmashell restart: dock still magnify false, powerTier 2" \
  [ "$(wkey org.plasmafusion.dock magnify)/$(wkey org.plasmafusion.dock powerTier)" = false/2 ]
# a layout reset while critical: new widgets, then a reload (what the settings module's Reset does)
plasma-apply-lookandfeel -a org.plasmafusion.dark.desktop --resetLayout >"$OUT/reset-layout.log" 2>&1
sleep 8
echo "after reset: $(widgets | tr '\n' ';')" >>"$OUT/timing.txt"
j=$(jl); kill -HUP "$SVC"
check "reload after a layout reset: logged" wait_log "$j" 'tier critical'
check "reload after a layout reset: the new dock is lighter too" [ "$(wkey org.plasmafusion.dock magnify)/$(wkey org.plasmafusion.dock powerTier)" = false/2 ]
# the user turns magnification on at 8 %: it stays after the battery recovers
evaljs - <<'JS' >/dev/null
var ps = panels(); for (var i = 0; i < ps.length; i++) { var ws = ps[i].widgets("org.plasmafusion.dock");
  for (var j = 0; j < ws.length; j++) { ws[j].currentConfigGroup = ["General"]; ws[j].writeConfig("magnify", true); } }
JS
# idle cost of the service: 30 s without events
ticks() { local s=0 p; for p in "$SVC" $(kids "$SVC"); do s=$((s + $(awk '{print $14 + $15}' "/proc/$p/stat" 2>/dev/null || echo 0))); done; echo "$s"; }
c0=$(ticks); sleep 30; c1=$(ticks)
check "service idle 30 s: 0 CPU ticks (got $((c1 - c0)))" [ $((c1 - c0)) = 0 ]
{ for p in "$SVC" $(kids "$SVC"); do
    echo "$(ps -o comm= -p "$p") pid $p rss $(awk '/^VmRSS/{print $2}' "/proc/$p/status") kB pss $(awk '/^Pss:/{print $2}' "/proc/$p/smaps_rollup") kB"
  done; } >"$OUT/service-memory.txt"
j=$(jl); onbat false
check "AC: full" wait_log "$j" 'tier full (on AC'
sleep 1; dump 5-service-full
check "AC: blur loaded, the user's magnify=true kept" [ "$(blur)/$(wkey org.plasmafusion.dock magnify)" = true/true ]
t0=$EPOCHREALTIME; kill -TERM "$SVC"; wait "$SVC"; rcode=$?; t1=$EPOCHREALTIME
check "SIGTERM: exit 0 in $(python3 -c "print(round(($t1 - $t0) * 1000))") ms" [ "$rcode" = 0 ]
check "no monitor left" bash -c "! pgrep -f '[g]dbus monitor --session --dest org.kde.plasmashell --object-path /org/plasmafusion' -u $(id -u) -a | grep -q ."
kill "$MOCKP" "$SYSBUS" 2>/dev/null
cp "$HOME/.config/plasmafusionrc" "$OUT/plasmafusionrc-end"
echo "done" >>"$OUT/results.txt"
