#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# End-to-end test of plasma-fusion-powerfx without a desktop: two private buses (never the user's
# or the system's), mock-power.py as UPower and the power-profiles daemon on the "system" one,
# mock-session.py as KWin's effects and plasmashell's scripting (fake-shell.js, needs node) on the
# "session" one, and a throw-away HOME. Checks the tier table, --apply of every tier and the way
# back (files byte for byte), the options, a user's change while overridden, a missing
# plasmashell, and the running service: events, coalescing, a plasmashell restart, reload, UPower
# going away, a dying monitor, SIGTERM, memory and CPU.
#
#   offline.sh WORKDIR     (WORKDIR is created and removed at the end unless KEEP=1)
#
# Prints one "ok N ..." or "not ok N ..." line per check; exit status 1 when one failed.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$HERE/../plasma-fusion-powerfx
W=${1:?work directory}
[ -e "$W" ] && { echo "$W exists; give a new directory" >&2; exit 2; }
for t in dbus-daemon busctl gdbus kwriteconfig6 node python3; do
  command -v "$t" >/dev/null || { echo "offline.sh needs $t" >&2; exit 2; }
done
mkdir -p "$W/home/.config" "$W/run" "$W/bin" && chmod 700 "$W/run"
W=$(cd "$W" && pwd)
N=0 FAIL=0
ok() { N=$((N + 1)); echo "ok $N $1"; }
nok() { N=$((N + 1)); FAIL=$((FAIL + 1)); echo "not ok $N $1"; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else nok "$d"; fi; }

# The journal of the script under test goes to a file (logger stub first in PATH).
printf '#!/bin/sh\nshift 2; [ "$1" = -- ] && shift; echo "$*" >>%q\n' "$W/journal.log" >"$W/bin/logger"
chmod +x "$W/bin/logger"
: >"$W/journal.log"

bus_conf() {
  cat >"$W/$1.conf" <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path=$W/$1.sock</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF
}
bus_conf system; bus_conf session
SYS=unix:path=$W/system.sock SES=unix:path=$W/session.sock
E=(env -i HOME="$W/home" XDG_CONFIG_HOME="$W/home/.config" XDG_RUNTIME_DIR="$W/run" LANG=C.UTF-8
  PATH="$W/bin:/usr/bin:/bin" DBUS_SESSION_BUS_ADDRESS="$SES" DBUS_SYSTEM_BUS_ADDRESS="$SYS" QT_QPA_PLATFORM=offscreen)
PIDS=()
cleanup() {
  kill "${PIDS[@]}" 2>/dev/null
  [ -n "${SVC:-}" ] && kill "$SVC" 2>/dev/null
  sleep 0.3
  [ "${KEEP:-0}" = 1 ] || rm -rf "$W"
}
trap cleanup EXIT
"${E[@]}" dbus-daemon --nofork --config-file="$W/system.conf" >/dev/null 2>&1 & SYSBUS=$!; PIDS+=("$SYSBUS")
"${E[@]}" dbus-daemon --nofork --config-file="$W/session.conf" >/dev/null 2>&1 & PIDS+=($!)
for _ in $(seq 50); do [ -S "$W/system.sock" ] && [ -S "$W/session.sock" ] && break; sleep 0.1; done

cat >"$W/layout.json" <<'EOF'
{"desktops": [[{"id": 30, "type": "org.plasmafusion.systemcard", "config": {"General": {"updateInterval": "3000"}}},
               {"id": 32, "type": "org.kde.plasma.systemmonitor.cpu", "config": {"Appearance": {"updateRateLimit": "2000"}}}]],
 "panels": [[{"id": 5, "type": "org.plasmafusion.quicksettings", "config": {}}],
            [{"id": 12, "type": "org.plasmafusion.dock", "config": {"General": {"magnifiedSize": "62"}}},
             {"id": 14, "type": "org.plasmafusion.launcher", "config": {}}]]}
EOF
cp "$W/layout.json" "$W/layout.orig.json"
start_power() {
  "${E[@]}" python3 "$HERE/mock-power.py" --address "$SYS" "$@" >"$W/mock-power.out" 2>&1 & MOCKP=$!; PIDS+=("$MOCKP")
  for _ in $(seq 50); do grep -q ready "$W/mock-power.out" 2>/dev/null && return 0; sleep 0.1; done
  echo "mock-power did not start" >&2; cat "$W/mock-power.out" >&2; exit 2
}
start_power
"${E[@]}" python3 "$HERE/mock-session.py" --address "$SES" --layout "$W/layout.json" --log "$W/calls.log" --node "$(command -v node)" >"$W/mock-session.out" 2>&1 & PIDS+=($!)
for _ in $(seq 50); do grep -q ready "$W/mock-session.out" 2>/dev/null && break; sleep 0.1; done

pfx() { "${E[@]}" bash "$SCRIPT" "$@"; }
kwc() { "${E[@]}" kwriteconfig6 "$@"; }
sysset() { "${E[@]}" busctl --system set-property "$@"; }
battery() { sysset org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery b "$1"; }
percent() { sysset org.freedesktop.UPower /org/freedesktop/UPower/devices/DisplayDevice org.freedesktop.UPower.Device Percentage d "$1"; }
warning() { sysset org.freedesktop.UPower /org/freedesktop/UPower/devices/DisplayDevice org.freedesktop.UPower.Device WarningLevel u "$1"; }
profile() { sysset net.hadess.PowerProfiles /net/hadess/PowerProfiles net.hadess.PowerProfiles ActiveProfile s "$1"; }
status_of() { pfx --status | sed -n "s/^$1=//p"; }
cfg() { python3 -c 'import json,sys
l = json.load(open(sys.argv[1]))
for w in [w for c in l["desktops"] + l["panels"] for w in c]:
    if w["id"] == int(sys.argv[2]):
        print(w["config"].get(sys.argv[3], {}).get(sys.argv[4], "-"))' "$W/layout.json" "$@"; }
rc_get() { "${E[@]}" kreadconfig6 --file "$1" --group "$2" --key "$3" --default -; }
shell() { "${E[@]}" busctl --user call org.plasmafusion.MockSession /MockSession org.plasmafusion.MockSession "$1"; }
wait_for() { # SECONDS COMMAND...: until COMMAND succeeds (every 50 ms)
  local end=$((SECONDS + $1)); shift
  until "$@"; do [ "$SECONDS" -ge "$end" ] && return 1; sleep 0.05; done
}
st_is() { [ "$(rc_get plasmafusionrc Power "$1")" = "$2" ]; }

# Realistic starting files, written by KConfig itself (so its own order).
kwc --file kwinrc --group Plugins --key sheetEnabled true
kwc --file kwinrc --group Plugins --key plasmafusion-snapEnabled true
kwc --file kwinrc --group Effect-blur --key BlurStrength 13
kwc --file kdeglobals --group KDE --key LookAndFeelPackage org.plasmafusion.dark.desktop
kwc --file plasmafusionrc --group Effects --key Glass Full
cp "$W/home/.config/kwinrc" "$W/kwinrc.orig"; cp "$W/home/.config/kdeglobals" "$W/kdeglobals.orig"

# ---- tier table ----
t() { # ON_BATTERY PERCENT WARNING PROFILE EXPECTED
  battery "$1"; percent "$2"; warning "$3"; profile "$4"
  local got; got=$(status_of tier)
  check "tier: battery=$1 $2 % warning $3 $4 -> $5 (got $got)" [ "$got" = "$5" ]
}
t false 84 1 balanced full
t true 84 1 balanced full
t true 21 1 balanced full
t true 20.4 3 balanced saver
t true 20 3 balanced saver
t true 10.6 3 balanced saver
t true 10 3 balanced critical
t true 50 4 balanced critical
t true 50 5 performance critical
t true 50 3 balanced full
t false 5 4 balanced full
t false 84 1 power-saver saver
t true 84 1 power-saver saver
t true 9 1 power-saver critical
battery false; percent 84; warning 1; profile balanced
check "--help prints the usage" bash -c "$(printf '%q ' "${E[@]}") bash $(printf %q "$SCRIPT") --help | grep -q -- '--apply TIER'"
pfx --apply nonsense >/dev/null 2>&1; check "--apply with a bad tier exits 2" [ $? = 2 ]

# ---- --apply critical and back ----
pfx --apply critical 2>>"$W/stderr.log"; rc=$?
check "--apply critical exits 0" [ "$rc" = 0 ]
check "critical: kwinrc blurEnabled=false" [ "$(rc_get kwinrc Plugins blurEnabled)" = false ]
check "critical: KWin unloadEffect blur called" grep -qx 'kwin unloadEffect blur' "$W/calls.log"
check "critical: dock magnify false, powerTier 2" [ "$(cfg 12 General magnify)/$(cfg 12 General powerTier)" = false/2 ]
check "critical: glass solid on card, quick settings, dock, launcher" \
  [ "$(cfg 30 General glass)$(cfg 5 General glass)$(cfg 12 General glass)$(cfg 14 General glass)" = solidsolidsolidsolid ]
check "critical: card powerTier 2, monitor 8000" [ "$(cfg 30 General powerTier)/$(cfg 32 Appearance updateRateLimit)" = 2/8000 ]
check "critical: state Tier, ShellTier, ForcedBlur, UserBlurEnabled" \
  [ "$(rc_get plasmafusionrc Power Tier)$(rc_get plasmafusionrc Power ShellTier)$(rc_get plasmafusionrc Power ForcedBlur)$(rc_get plasmafusionrc Power UserBlurEnabled)" = criticalcriticaltrueabsent ]
check "critical: UserDockMagnify=true, UserGlass=Full" [ "$(rc_get plasmafusionrc Power UserDockMagnify)/$(rc_get plasmafusionrc Power UserGlass)" = true/Full ]
check "critical: one journal line" [ "$(grep -c '^tier critical' "$W/journal.log")" = 1 ]
check "the plan was stored before the write (plan, then apply)" bash -c "grep -o 'evaluateScript [a-z]*' $(printf %q "$W/calls.log") | tr '\n' ' ' | grep -q 'plan evaluateScript apply'"
pfx --apply critical 2>>"$W/stderr.log"
check "critical again: no second journal line, no write" [ "$(grep -c '^tier critical' "$W/journal.log")" = 1 ]
pfx --apply full 2>>"$W/stderr.log"; rc=$?
check "--apply full exits 0" [ "$rc" = 0 ]
check "full: kwinrc byte for byte as before" cmp -s "$W/kwinrc.orig" "$W/home/.config/kwinrc"
check "full: kdeglobals byte for byte as before" cmp -s "$W/kdeglobals.orig" "$W/home/.config/kdeglobals"
check "full: KWin loadEffect blur called" grep -qx 'kwin loadEffect blur' "$W/calls.log"
check "full: widget values back (powerTier 0 kept as the only trace)" python3 -c '
import json, sys
a, b = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
def flat(l): return {(w["id"], g, k): v for c in l["desktops"] + l["panels"] for w in c for g, kv in w["config"].items() for k, v in kv.items()}
fa, fb = flat(a), flat(b)
extra = {k: v for k, v in fb.items() if k not in fa}
assert all(fa[k] == fb.get(k) for k in fa), "changed"
assert all((k[2], v) in (("powerTier", "0"), ("magnify", "true"), ("glass", "full")) for k, v in extra.items()), extra
' "$W/layout.orig.json" "$W/layout.json"
check "full: only Tier, ShellTier, ShellLighter left in [Power]" bash -c "[ \"\$(sed -n '/^\[Power\]/,/^\[/p' $(printf %q "$W/home/.config/plasmafusionrc") | grep -c =)\" = 3 ]"

# ---- options ----
kwc --file plasmafusionrc --group Power --key LighterOnCritical false
pfx --apply critical 2>>"$W/stderr.log"
check "LighterOnCritical=false: blur and magnification untouched" [ "$(rc_get kwinrc Plugins blurEnabled)/$(cfg 12 General magnify)" = -/true ]
check "LighterOnCritical=false: intervals still x4" [ "$(cfg 30 General powerTier)/$(cfg 32 Appearance updateRateLimit)" = 2/8000 ]
kwc --file plasmafusionrc --group Power --key LighterOnCritical true
pfx --apply full 2>>"$W/stderr.log"
kwc --file plasmafusionrc --group Power --key ShorterAnimationsOnCritical true
pfx --apply critical 2>>"$W/stderr.log"
check "ShorterAnimationsOnCritical: factor 0.75" [ "$(rc_get kdeglobals KDE AnimationDurationFactor)" = 0.75 ]
pfx --apply full 2>>"$W/stderr.log"
check "ShorterAnimationsOnCritical: kdeglobals byte for byte as before" cmp -s "$W/kdeglobals.orig" "$W/home/.config/kdeglobals"
kwc --file kdeglobals --group KDE --key AnimationDurationFactor 0.5
cp "$W/home/.config/kdeglobals" "$W/kdeglobals.half"
pfx --apply critical 2>>"$W/stderr.log"
check "ShorterAnimationsOnCritical: 0.5 is never lengthened" [ "$(rc_get kdeglobals KDE AnimationDurationFactor)" = 0.5 ]
pfx --apply full 2>>"$W/stderr.log"
check "ShorterAnimationsOnCritical: 0.5 stays" cmp -s "$W/kdeglobals.half" "$W/home/.config/kdeglobals"
kwc --file kdeglobals --group KDE --key AnimationDurationFactor --delete
kwc --file plasmafusionrc --group Power --key ShorterAnimationsOnCritical --delete

# ---- the user's changes while overridden ----
pfx --apply critical 2>>"$W/stderr.log"
kwc --file kwinrc --group Plugins --key blurEnabled true
pfx --apply full 2>>"$W/stderr.log"
check "blur turned on by the user at critical stays on" [ "$(rc_get kwinrc Plugins blurEnabled)" = true ]
check "no state left after that" [ "$(rc_get plasmafusionrc Power ForcedBlur)/$(rc_get plasmafusionrc Power UserBlurEnabled)" = -/- ]
kwc --file kwinrc --group Plugins --key blurEnabled --delete
pfx --apply critical 2>>"$W/stderr.log"
kwc --file plasmafusionrc --group Effects --key Glass Solid
pfx --apply full 2>>"$W/stderr.log"
check "Glass=Solid chosen at critical: blur stays off" [ "$(rc_get kwinrc Plugins blurEnabled)" = false ]
kwc --file plasmafusionrc --group Effects --key Glass Full
kwc --file kwinrc --group Plugins --key blurEnabled --delete

# ---- plasmashell missing ----
shell ReleaseShell
pfx --apply critical 2>>"$W/stderr.log"; rc=$?
check "no plasmashell: --apply exits 3" [ "$rc" = 3 ]
check "no plasmashell: KWin part done, widgets not" [ "$(rc_get kwinrc Plugins blurEnabled)/$(rc_get plasmafusionrc Power ShellTier)/$(cfg 12 General magnify)" = false/full/true ]
check "no plasmashell: the journal says so" grep -q 'Plasma widgets when plasmashell is back' "$W/journal.log"
shell OwnShell
pfx --apply critical 2>>"$W/stderr.log"; rc=$?
check "plasmashell back: --apply critical sets the widgets" [ "$rc/$(cfg 12 General magnify)/$(rc_get plasmafusionrc Power ShellTier)" = 0/false/critical ]
shell ReleaseShell
pfx --apply full 2>>"$W/stderr.log"
check "log-out case: full without plasmashell keeps ShellTier critical" [ "$(rc_get plasmafusionrc Power Tier)/$(rc_get plasmafusionrc Power ShellTier)" = full/critical ]
shell OwnShell
pfx --apply full 2>>"$W/stderr.log"
check "next start: the widgets are given back" [ "$(cfg 12 General magnify)/$(rc_get plasmafusionrc Power ShellTier)" = true/full ]
check "and kwinrc is as before" cmp -s "$W/kwinrc.orig" "$W/home/.config/kwinrc"

# ---- the running service ----
# Each change ends with its journal line: wait for the next one.
jl() { wc -l <"$W/journal.log"; }
wait_log() { # N PATTERN: a journal line after line N matches PATTERN (5 s)
  wait_for 5 bash -c "tail -n +$(($1 + 1)) $(printf %q "$W/journal.log") | grep -q -- $(printf %q "$2")"
}
battery false; percent 84; warning 1; profile balanced
"${E[@]}" bash "$SCRIPT" 2>"$W/service.log" & SVC=$!
sleep 1.5
kids() { ps -o pid= --ppid "$1" | while read -r p; do echo "$p"; kids "$p"; done; }
check "service: bash plus three gdbus monitor processes" [ "$(for p in $(kids "$SVC"); do ps -o comm= -p "$p"; done | grep -c '^gdbus$')" = 3 ]
j=$(jl)
battery true
sleep 1.5
check "on battery at 84 %: still full, nothing logged" [ "$(rc_get plasmafusionrc Power Tier)/$(jl)" = "full/$j" ]
j=$(jl); t0=$EPOCHREALTIME; percent 15
wait_for 5 st_is Tier saver; t1=$EPOCHREALTIME
check "15 %: saver" wait_log "$j" '^tier saver (on battery, 15 %'
echo "# saver state written $(python3 -c "print(round(($t1 - $t0) * 1000))") ms after the event (0.5 s coalescing included)"
check "saver: widgets follow" [ "$(cfg 12 General powerTier)/$(cfg 30 General powerTier)" = 1/1 ]
j=$(jl); percent 8
check "8 %: critical" wait_log "$j" '^tier critical (on battery, 8 %'
check "8 %: blur off, magnification off" [ "$(rc_get kwinrc Plugins blurEnabled)/$(cfg 12 General magnify)/$(cfg 12 General powerTier)" = false/false/2 ]
n0=$(grep -c . "$W/calls.log"); j=$(jl)
battery false; sleep 0.1; battery true; sleep 0.1; percent 7.5
sleep 1.5
check "a burst of events that ends where it began: no work, no line" [ "$(grep -c . "$W/calls.log")/$(jl)" = "$n0/$j" ]
# plasmashell restarts after a layout reset: the dock is a new widget with its defaults
j=$(jl)
shell ReleaseShell; sleep 0.3
python3 -c 'import json,sys
l = json.load(open(sys.argv[1]))
for c in l["panels"]:
    for w in c:
        if w["id"] == 12: w["id"] = 42; w["config"] = {}
json.dump(l, open(sys.argv[1], "w"))' "$W/layout.json"
shell OwnShell
check "plasmashell restarted: the tier is set on it again" wait_log "$j" '^plasmashell is back: tier critical'
check "plasmashell restarted: the new dock has magnify false, powerTier 2" [ "$(cfg 42 General magnify)/$(cfg 42 General powerTier)" = false/2 ]
check "plasmashell restarted: the new dock's own value is remembered" bash -c "$(printf '%q ' "${E[@]}") kreadconfig6 --file plasmafusionrc --group Power --key UserWidgetValues | grep -q '42/magnify=true'"
# reload after an option change
j=$(jl)
kwc --file plasmafusionrc --group Power --key LighterOnCritical false
kill -HUP "$SVC"
check "reload with LighterOnCritical=false: logged at once" wait_log "$j" '^tier critical (on battery, 7 %.*blur back'
check "reload: blur, magnification and glass back, still critical" \
  [ "$(rc_get kwinrc Plugins blurEnabled)/$(cfg 42 General magnify)/$(cfg 14 General glass)/$(rc_get plasmafusionrc Power Tier)" = -/true/full/critical ]
j=$(jl)
kwc --file plasmafusionrc --group Power --key LighterOnCritical --delete
kill -HUP "$SVC"
check "reload with the default again: lighter again" wait_log "$j" '^tier critical.*blur off'
# on AC
j=$(jl); battery false
check "AC: full" wait_log "$j" '^tier full (on AC'
check "AC: everything back" [ "$(cfg 42 General magnify)/$(cfg 42 General powerTier)/$(cfg 32 Appearance updateRateLimit)/$(cfg 5 General glass)" = true/0/2000/full ]
check "AC: kwinrc as before" cmp -s "$W/kwinrc.orig" "$W/home/.config/kwinrc"
j=$(jl); profile power-saver
check "power-saver profile on AC: saver" wait_log "$j" '^tier saver (on AC'
j=$(jl); profile balanced
wait_log "$j" '^tier full'

# memory and CPU
rss=0 pss=0
for p in "$SVC" $(kids "$SVC"); do
  r=$(awk '/^VmRSS/{print $2}' "/proc/$p/status" 2>/dev/null); s=$(awk '/^Pss:/{print $2}' "/proc/$p/smaps_rollup" 2>/dev/null)
  rss=$((rss + ${r:-0})); pss=$((pss + ${s:-0}))
  echo "# $(ps -o comm= -p "$p") pid $p rss ${r:-?} kB pss ${s:-?} kB"
done
echo "# service total: rss $((rss / 1024)) MiB, pss $((pss / 1024)) MiB"
check "service memory: PSS under 16 MiB" [ "$pss" -lt 16384 ]
ticks() { local s=0 p; for p in "$SVC" $(kids "$SVC"); do s=$((s + $(awk '{print $14 + $15}' "/proc/$p/stat" 2>/dev/null || echo 0))); done; echo "$s"; }
c0=$(ticks); sleep 20; c1=$(ticks)
check "idle 20 s without events: 0 CPU ticks (got $((c1 - c0)))" [ $((c1 - c0)) = 0 ]
c0=$(ticks)
for i in $(seq 10); do
  "${E[@]}" busctl --system call org.freedesktop.UPower /org/freedesktop/UPower org.plasmafusion.Mock SetMany 'osa{sv}' \
    /org/freedesktop/UPower/devices/DisplayDevice org.freedesktop.UPower.Device 1 EnergyRate d "7.$i" >/dev/null
  sleep 2
done
c1=$(ticks)
check "10 UPower updates that change nothing in 20 s: at most 2 CPU ticks (got $((c1 - c0)))" [ $((c1 - c0)) -le 2 ]
# UPower goes away and comes back at 8 %
battery true; percent 30; wait_for 3 st_is Tier full
kill "$MOCKP"; wait "$MOCKP" 2>/dev/null
check "UPower gone: read as AC, full" wait_for 4 st_is Tier full
start_power --on-battery --percentage 8
check "UPower back at 8 % on battery: critical" wait_for 5 st_is Tier critical
# SIGTERM: clean exit, no process left, then the unit's ExecStopPost
kids_before=$(kids "$SVC" | wc -l)
t0=$EPOCHREALTIME; kill -TERM "$SVC"; wait_for 5 bash -c "! kill -0 $SVC 2>/dev/null"; t1=$EPOCHREALTIME; wait "$SVC"; rc=$?
check "SIGTERM: exit 0 (got $rc)" [ "$rc" = 0 ]
ms=$(python3 -c "print(round(($t1 - $t0) * 1000))")
check "SIGTERM: gone within 1 s (took $ms ms)" [ "$ms" -lt 1000 ]
# (the [g] keeps pgrep from finding the shell that runs it)
check "SIGTERM: its $kids_before monitor processes are gone" wait_for 3 bash -c "! pgrep -f '[g]dbus monitor --session --dest org.kde.plasmashell --object-path /org/plasmafusion' -u $(id -u) >/dev/null"
SVC=
pfx --apply full 2>>"$W/stderr.log"
check "ExecStopPost --apply full: kwinrc as before" cmp -s "$W/kwinrc.orig" "$W/home/.config/kwinrc"
# a dying monitor ends the service with status 1 (the unit restarts it)
"${E[@]}" bash "$SCRIPT" 2>>"$W/service.log" & SVC=$!
sleep 2
kill "$SYSBUS"
wait_for 5 bash -c "! kill -0 $SVC 2>/dev/null"; wait "$SVC"; rc=$?
check "system bus gone: service exits 1 (got $rc)" [ "$rc" = 1 ]
check "system bus gone: logged" grep -q 'monitor stopped' "$W/journal.log"
SVC=
check "no stray gdbus of this test" wait_for 3 bash -c "! pgrep -f '[g]dbus monitor --session --dest org.kde.plasmashell --object-path /org/plasmafusion' -u $(id -u) >/dev/null"
check "--apply printed nothing but its journal lines" bash -c "! grep -v '^plasma-fusion-powerfx: ' $(printf %q "$W/stderr.log")"

echo "# journal:"; sed 's/^/#   /' "$W/journal.log"
echo "# service stderr:"; sed 's/^/#   /' "$W/service.log"
echo "$((N - FAIL)) of $N passed"
[ "$FAIL" = 0 ]
