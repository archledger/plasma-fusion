#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# ctest driver (tests/CMakeLists.txt, test kcmctl-power): the settings module and the power service
# (packages/powerfx/plasma-fusion-powerfx) together, while the service holds a tier. A stand-in
# plasmashell and KWin (packages/powerfx/tests/mock-session.py, which runs the shell's scripts with
# fake-shell.js against a layout file) answer on a private D-Bus session without service activation
# (session-bus.conf), in a scratch HOME, without display variables; systemctl is a stand-in that
# logs its arguments. Checks:
#   - at critical, a Glass level and dock magnification chosen on the page leave the held widgets
#     and blur alone, and are what the service gives back when the battery recovers (the widgets'
#     glass, the dock's magnification, blur on again);
#   - system meters turned on in saver ask the service to apply its tier to them (and not at full).
# Needs node and python3 with GObject introspection (mock-session.py).
#
#   run-power-tier.sh KCMCTL PLUGIN_DIR WORKDIR
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
kcmctl=$1 plugins=$2 work=$3
powerfx=$here/../../powerfx
for t in node python3 kwriteconfig6 kreadconfig6 busctl dbus-run-session; do
  command -v "$t" >/dev/null || { echo "FAIL: run-power-tier.sh needs $t"; exit 1; }
done

rm -rf "$work"
mkdir -p "$work/home" "$work/config" "$work/data" "$work/cache" "$work/state" "$work/runtime" "$work/bin"
chmod 700 "$work/runtime"
work=$(cd "$work" && pwd)
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export HOME=$work/home XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work/cache
export XDG_STATE_HOME=$work/state XDG_RUNTIME_DIR=$work/runtime
export QT_PLUGIN_PATH=$plugins QT_QPA_PLATFORM=offscreen
# The programs the module and the service start: logged, never the real ones.
for tool in systemctl logger plasma-apply-lookandfeel plasma-apply-colorscheme; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/programs.log"\n' "$tool" "$work" >"$work/bin/$tool"
  chmod +x "$work/bin/$tool"
done
export PATH=$work/bin:$PATH

# Top bar (app name, quick settings), dock (dock, launcher), a desktop with the system card.
cat >"$work/layout.json" <<'EOF'
{"knownWidgetTypes": ["org.plasmafusion.appname", "org.plasmafusion.quicksettings", "org.plasmafusion.dock",
                      "org.plasmafusion.launcher", "org.plasmafusion.systemcard", "org.plasmafusion.meters"],
 "desktops": [{"id": 1, "type": "org.plasmafusion.desktop", "widgets": [
    {"id": 30, "type": "org.plasmafusion.systemcard", "config": {}}]}],
 "panels": [{"id": 2, "location": "top", "opacity": "adaptive", "widgets": [
               {"id": 3, "type": "org.plasmafusion.appname", "config": {}},
               {"id": 5, "type": "org.plasmafusion.quicksettings", "config": {}}]},
            {"id": 10, "location": "bottom", "opacity": "translucent", "widgets": [
               {"id": 12, "type": "org.plasmafusion.dock", "config": {"General": {"magnify": "true"}}},
               {"id": 14, "type": "org.plasmafusion.launcher", "config": {}}]}]}
EOF

cat >"$work/inner.sh" <<'EOF'
set -u
work=$1 kcmctl=$2 powerfx=$3
python3 "$powerfx/tests/mock-session.py" --address "$DBUS_SESSION_BUS_ADDRESS" --layout "$work/layout.json" \
  --log "$work/calls.log" --node "$(command -v node)" >"$work/mock-session.out" 2>&1 &
mock=$!
for _ in $(seq 50); do grep -q ready "$work/mock-session.out" 2>/dev/null && break; sleep 0.1; done
grep -q ready "$work/mock-session.out" || { echo "FAIL: mock-session did not start"; cat "$work/mock-session.out"; exit 1; }
N=0 FAIL=0
check() { local d=$1; shift; N=$((N + 1)); if "$@"; then echo "ok $N $d"; else FAIL=$((FAIL + 1)); echo "not ok $N $d"; fi; }
cfg() { python3 -c 'import json,sys
l = json.load(open(sys.argv[1]))
for c in l["desktops"] + l["panels"]:
    for w in (c if isinstance(c, list) else c["widgets"]):
        if w["id"] == int(sys.argv[2]):
            print(w["config"].get(sys.argv[3], {}).get(sys.argv[4], "-"))' "$work/layout.json" "$@"; }
rc() { kreadconfig6 --file "$1" --group "$2" --key "$3" --default -; }
module() { printf '%s\n' "$@" | "$kcmctl" >>"$work/kcmctl.log" 2>&1; }
pfx() { bash "$powerfx/plasma-fusion-powerfx" "$@" 2>>"$work/powerfx.log"; }

# ---- critical: the page's Glass level and magnification, given back at recovery ----
kwriteconfig6 --file plasmafusionrc --group Effects --key Glass Full
pfx --apply critical
check "the service holds the widgets at critical" [ "$(cfg 5 General glass)/$(cfg 12 General magnify)/$(rc kwinrc Plugins blurEnabled)" = solid/false/false ]
module waitshell "get powerCritical" "set glass 1" "set magnify false" save "get glass" "get magnify"
check "the module saw the critical tier" grep -q '^kcmctl: powerCritical=true$' "$work/kcmctl.log"
check "Glass Reduced is the page's level" [ "$(rc plasmafusionrc Effects Glass)" = Reduced ]
check "the module stores it for the service ([Power] PageGlass)" [ "$(rc plasmafusionrc Power PageGlass)" = Reduced ]
check "and the magnification ([Power] PageDockMagnify)" [ "$(rc plasmafusionrc Power PageDockMagnify)/$(rc plasmafusionrc Power UserDockMagnify)" = false/false ]
check "the held widgets stay solid, blur off" [ "$(cfg 5 General glass)$(cfg 14 General glass)$(cfg 30 General glass)/$(rc kwinrc Plugins blurEnabled)" = solidsolidsolid/false ]
check "the panels follow at once (Reduced: opaque top bar)" grep -q "containment 2 opacity=opaque" "$work/calls.log.writes"
pfx --apply full
check "recovered: quick settings, launcher, card and dock get Reduced" \
  [ "$(cfg 5 General glass)$(cfg 14 General glass)$(cfg 30 General glass)$(cfg 12 General glass)" = reducedreducedreducedreduced ]
check "recovered: magnification stays off as chosen" [ "$(cfg 12 General magnify)" = false ]
check "recovered: blur on again" [ "$(rc kwinrc Plugins blurEnabled)" = - ]
check "recovered: the page's choices are forgotten" [ "$(rc plasmafusionrc Power PageGlass)/$(rc plasmafusionrc Power PageDockMagnify)" = -/- ]
module waitshell "get glass" "get magnify"
check "the page reads Reduced and magnification off again" \
  [ "$(tail -n 4 "$work/kcmctl.log" | grep -E '^kcmctl: (glass|magnify)=' | tr '\n' ' ')" = "kcmctl: glass=1 kcmctl: magnify=false " ]

# ---- saver: system meters turned on get the tier ----
pfx --apply saver
: >"$work/programs.log"
# The meters are placed from the event loop after Apply (every 300 ms, up to 3 s).
module waitshell "set systemMeters true" save "wait 1500" "get systemMeters"
check "meters added to the top bar, before quick settings" [ "$(python3 -c 'import json,sys
print(",".join(w["type"].rsplit(".", 1)[1] for w in json.load(open(sys.argv[1]))["panels"][0]["widgets"]))' "$work/layout.json")" = appname,meters,quicksettings ]
check "in saver the module asks the service to apply its tier again" \
  grep -qx 'systemctl --user try-reload-or-restart plasma-fusion-powerfx.service' "$work/programs.log"
pfx --apply saver
meters=$(python3 -c 'import json,sys
print([w["id"] for w in json.load(open(sys.argv[1]))["panels"][0]["widgets"] if w["type"] == "org.plasmafusion.meters"][0])' "$work/layout.json")
check "and the service's run gives the new meters powerTier 1" [ "$(cfg "$meters" General powerTier)" = 1 ]
pfx --apply full
: >"$work/programs.log"
module waitshell "set systemMeters false" save "set systemMeters true" save
check "at full tier the module leaves the service alone" bash -c "! grep -q systemctl '$work/programs.log'"

kill "$mock" 2>/dev/null
echo "$((N - FAIL)) of $N passed"
[ "$FAIL" = 0 ]
EOF

status=0
dbus-run-session --config-file="$here/session-bus.conf" -- bash "$work/inner.sh" "$work" "$kcmctl" "$powerfx" || status=$?
if [ "$status" != 0 ]; then
  echo "--- kcmctl"; cat "$work/kcmctl.log" 2>/dev/null
  echo "--- powerfx"; cat "$work/powerfx.log" 2>/dev/null
  echo "--- shell calls"; cat "$work/calls.log" 2>/dev/null
  echo "FAIL: kcmctl-power"
  exit 1
fi
echo "PASS: kcmctl-power"
