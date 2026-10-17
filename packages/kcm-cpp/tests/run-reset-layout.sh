#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# ctest driver (tests/CMakeLists.txt, test kcmctl-reset): the settings module's "Reset Fusion
# layout" against a stand-in plasmashell (packages/powerfx/tests/mock-session.py with
# fake-shell.js; its loadLookAndFeelDefaultLayout puts a prepared layout in place) on a private
# D-Bus session without service activation (session-bus.conf), in a scratch HOME, without display
# variables. No kglobalaccel answers there, so every key the module tries to give is reported as
# not set, which shows which keys it tries: quick settings gets Meta+A when it had none, and the
# pen menu gets a key only when the old one had it (Meta+Shift+W is fusion-config.sh --pen's).
# With "Dock on every screen" on, the reset runs ensure-topbars.js (a stand-in) for the other docks
# and reports it when the script is missing or fails. A top bar that hid (the settings page's "Hide
# the top bar automatically") hides again after the reset, which rebuilds it showing.
# Needs node and python3 with GObject introspection (mock-session.py).
#
#   run-reset-layout.sh KCMCTL PLUGIN_DIR WORKDIR
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
kcmctl=$1 plugins=$2 work=$3
powerfx=$here/../../powerfx
for t in node python3 dbus-run-session; do
  command -v "$t" >/dev/null || { echo "FAIL: run-reset-layout.sh needs $t"; exit 1; }
done

rm -rf "$work"
mkdir -p "$work/home" "$work/config" "$work/data" "$work/cache" "$work/state" "$work/runtime" "$work/bin"
chmod 700 "$work/runtime"
work=$(cd "$work" && pwd)
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export HOME=$work/home XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work/cache
export XDG_STATE_HOME=$work/state XDG_RUNTIME_DIR=$work/runtime
export QT_PLUGIN_PATH=$plugins QT_QPA_PLATFORM=offscreen
for tool in systemctl plasma-apply-lookandfeel plasma-apply-colorscheme; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/programs.log"\n' "$tool" "$work" >"$work/bin/$tool"
  chmod +x "$work/bin/$tool"
done
export PATH=$work/bin:$PATH

# layout PEN_KEY FIRST_ID: a top bar with quick settings and the pen menu, a dock.
layout() {
  local q=$(($2 + 3)) p=$(($2 + 4))
  cat <<JSON
{"knownWidgetTypes": ["org.plasmafusion.appname", "org.plasmafusion.quicksettings", "org.plasmafusion.pen", "org.plasmafusion.dock"],
 "desktops": [{"id": $(($2 + 1)), "widgets": []}],
 "panels": [{"id": $(($2 + 2)), "location": "top", "widgets": [
               {"id": $q, "type": "org.plasmafusion.quicksettings", "config": {}},
               {"id": $p, "type": "org.plasmafusion.pen", "config": {}, "shortcut": "$1"}]},
            {"id": $(($2 + 5)), "location": "bottom", "opacity": "translucent", "widgets": [
               {"id": $(($2 + 6)), "type": "org.plasmafusion.dock", "config": {}}]}]}
JSON
}

# bar HIDING FIRST_ID: a top bar (the app name and quick settings) with this hiding.
bar() {
  cat <<JSON
{"knownWidgetTypes": ["org.plasmafusion.appname", "org.plasmafusion.quicksettings"],
 "desktops": [{"id": $(($2 + 1)), "widgets": []}],
 "panels": [{"id": $(($2 + 2)), "location": "top", "hiding": "$1", "widgets": [
               {"id": $(($2 + 3)), "type": "org.plasmafusion.appname", "config": {}},
               {"id": $(($2 + 4)), "type": "org.plasmafusion.quicksettings", "config": {}}]}]}
JSON
}

cat >"$work/inner.sh" <<'EOF2'
set -u
work=$1 kcmctl=$2 powerfx=$3
N=0 FAIL=0
check() { local d=$1; shift; N=$((N + 1)); if "$@"; then echo "ok $N $d"; else FAIL=$((FAIL + 1)); echo "not ok $N $d"; fi; }
reset() { # NAME: a reset with layout.json and layout.json.reset prepared; the module's error text in $work/NAME.err
  # The last session's output goes first: the stand-in's redirection happens in the background
  # child, so the wait below could see the old "ready" and start the module before the stand-in
  # shell is there (its actions then do nothing).
  rm -f "$work/mock-session.out"
  python3 "$powerfx/tests/mock-session.py" --address "$DBUS_SESSION_BUS_ADDRESS" --layout "$work/layout.json" \
    --log "$work/calls.log" --node "$(command -v node)" >"$work/mock-session.out" 2>&1 &
  local mock=$!
  # Up to 30 s (a loaded machine, sanitizer builds).
  for _ in $(seq 300); do grep -q ready "$work/mock-session.out" 2>/dev/null && break; sleep 0.1; done
  check "the stand-in shell started ($1)" grep -q ready "$work/mock-session.out"
  grep -q ready "$work/mock-session.out" || sed 's/^/  mock: /' "$work/mock-session.out"
  printf '%s\n' waitshell "call resetLayout" waitidle "get errorText" "get infoText" | "$kcmctl" >"$work/$1.log" 2>&1
  kill "$mock" 2>/dev/null; wait "$mock" 2>/dev/null
  sed -n 's/^kcmctl: errorText=//p' "$work/$1.log" >"$work/$1.err"
}
kwriteconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage org.plasmafusion.dark.desktop 2>/dev/null || true

cp "$work/layout-nopen.json" "$work/layout.json"; cp "$work/layout-new.json" "$work/layout.json.reset"
reset nopen
check "the layout was rebuilt" grep -q 'loadLookAndFeelDefaultLayout' "$work/calls.log"
check "quick settings without a key is given Meta+A" grep -q 'Meta+A for quick settings' "$work/nopen.err"
check "the pen menu without a key is given none (Meta+Shift+W is --pen's)" bash -c "! grep -q 'pen menu' '$work/nopen.err'"

cp "$work/layout-pen.json" "$work/layout.json"; cp "$work/layout-new.json" "$work/layout.json.reset"
: >"$work/calls.log"
reset pen
check "a pen menu that had Meta+Shift+W gets it again" grep -q 'Meta+Shift+W for pen menu' "$work/pen.err"

# A top bar that hid: the layout rebuilds it showing, the module makes it hide again; one that
# showed is left showing.
# (the stand-in shell's writes are in calls.log.writes)
cp "$work/bar-hidden.json" "$work/layout.json"; cp "$work/bar-new.json" "$work/layout.json.reset"
: >"$work/calls.log.writes"
reset hidden
check "a top bar that hid: the rebuilt bar hides again" grep -q 'containment 52 hiding=autohide' "$work/calls.log.writes"
cp "$work/bar-shown.json" "$work/layout.json"; cp "$work/bar-new.json" "$work/layout.json.reset"
: >"$work/calls.log.writes"
reset shown
check "  one that showed: no hiding set" bash -c "! grep -q 'hiding=' '$work/calls.log.writes'"

# "Dock on every screen" saved on: the reset runs ensure-topbars.js (a stand-in) to bring the other
# docks back, and says so when it cannot: no script (no data dirs but the scratch one), or a
# script that fails.
printf '[Dock]\nEveryScreen=true\n' >"$XDG_CONFIG_HOME/plasmafusionrc"
export XDG_DATA_DIRS=$work/nodata
lf=$XDG_DATA_HOME/plasma/look-and-feel/org.plasmafusion.dark.desktop/contents/layouts
cp "$work/layout-nopen.json" "$work/layout.json"; cp "$work/layout-new.json" "$work/layout.json.reset"
reset docks-missing
check "every dock, no ensure-topbars.js: the reset says the other docks could not come back" \
  grep -q 'docks of the other screens could not be added back' "$work/docks-missing.err"
mkdir -p "$lf"
echo 'throw new Error("stand-in failure");' >"$lf/ensure-topbars.js"
cp "$work/layout-nopen.json" "$work/layout.json"; cp "$work/layout-new.json" "$work/layout.json.reset"
reset docks-fail
check "every dock, a failing ensure-topbars.js: the reset says the docks could not be added" \
  grep -q 'The docks could not be added' "$work/docks-fail.err"
echo 'print("docks: stand-in ran");' >"$lf/ensure-topbars.js"
cp "$work/layout-nopen.json" "$work/layout.json"; cp "$work/layout-new.json" "$work/layout.json.reset"
: >"$work/calls.log"
reset docks
check "every dock: the reset runs ensure-topbars.js" grep -q 'docks: stand-in ran' "$work/calls.log"
check "  and reports nothing about the docks" bash -c "! grep -qi 'docks' '$work/docks.err'"

echo "$((N - FAIL)) of $N passed"
[ "$FAIL" = 0 ]
EOF2
layout "" 0 >"$work/layout-nopen.json"
layout "Meta+Shift+W" 0 >"$work/layout-pen.json"
layout "" 50 >"$work/layout-new.json"
bar autohide 0 >"$work/bar-hidden.json"
bar none 0 >"$work/bar-shown.json"
bar none 50 >"$work/bar-new.json"

status=0
dbus-run-session --config-file="$here/session-bus.conf" -- bash "$work/inner.sh" "$work" "$kcmctl" "$powerfx" || status=$?
if [ "$status" != 0 ]; then
  for f in "$work"/nopen.log "$work"/pen.log "$work"/hidden.log "$work"/shown.log "$work"/docks-missing.log "$work"/docks-fail.log "$work"/docks.log; do echo "--- $f"; cat "$f" 2>/dev/null; done
  echo "--- shell calls"; cat "$work/calls.log" 2>/dev/null
  echo "FAIL: kcmctl-reset"
  exit 1
fi
echo "PASS: kcmctl-reset"
