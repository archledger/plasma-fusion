#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# ctest driver (tests/CMakeLists.txt, test kcmctl-settingsfile): the settings module's "Export my
# settings…" and "Import settings…" against a stand-in plasmashell (packages/powerfx/tests/
# mock-session.py with fake-shell.js) on a private D-Bus session without service activation
# (session-bus.conf), in scratch HOMEs, without display variables. The Global Theme's
# export-layout.js and import-layout.js are stand-ins here (packages/look-and-feel/tests/
# layout.test.js tests the real ones): the export one prints a fixed layout (a value in it holds
# U+2028, which the import must escape: QJSEngine refuses it in a string literal, and so does the
# stand-in shell), the import one prints the layout it was given, in its two steps (PHASE remove,
# then add). Export writes the applied settings (not a change still pending)
# and that layout; import into a fresh HOME applies the settings, hands the file's layout to
# import-layout.js, tries the shortcut the file gives (no kglobalaccel answers here, so the key is
# reported as not set) and tells what was left out. A file that is not a settings file of this
# version changes nothing. Needs node and python3 with GObject introspection (mock-session.py).
#
#   run-settings-file.sh KCMCTL PLUGIN_DIR WORKDIR
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
kcmctl=$1 plugins=$2 work=$3
powerfx=$here/../../powerfx
for t in node python3 dbus-run-session; do
  command -v "$t" >/dev/null || { echo "FAIL: run-settings-file.sh needs $t"; exit 1; }
done

rm -rf "$work"
mkdir -p "$work/home" "$work/data" "$work/cache" "$work/state" "$work/runtime" "$work/bin"
chmod 700 "$work/runtime"
work=$(cd "$work" && pwd)
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export HOME=$work/home XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work/cache
export XDG_STATE_HOME=$work/state XDG_RUNTIME_DIR=$work/runtime XDG_DATA_DIRS=$work/nodata
export QT_PLUGIN_PATH=$plugins QT_QPA_PLATFORM=offscreen
for tool in systemctl plasma-apply-lookandfeel plasma-apply-colorscheme; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/programs.log"\n' "$tool" "$work" >"$work/bin/$tool"
  chmod +x "$work/bin/$tool"
done
export PATH=$work/bin:$PATH

# The stand-in shell's layout: a top bar with quick settings (no key), a dock.
cat >"$work/layout.json" <<'JSON'
{"knownWidgetTypes": ["org.plasmafusion.appname", "org.plasmafusion.quicksettings", "org.plasmafusion.dock"],
 "desktops": [{"id": 1, "widgets": []}],
 "panels": [{"id": 2, "location": "top", "widgets": [
               {"id": 3, "type": "org.plasmafusion.appname", "config": {}},
               {"id": 4, "type": "org.plasmafusion.quicksettings", "config": {}}]},
            {"id": 5, "location": "bottom", "opacity": "translucent", "widgets": [
               {"id": 6, "type": "org.plasmafusion.dock", "config": {}}]}]}
JSON
lf=$XDG_DATA_HOME/plasma/look-and-feel/org.plasmafusion.dark.desktop/contents/layouts
mkdir -p "$lf"
cat >"$lf/export-layout.js" <<'JS'
print(JSON.stringify({ version: 1, screens: 1, left: ["screen", "copy"], panels: [
    { screen: 0, location: "top", height: 34, floating: false, lengthMode: "fill", alignment: "center", hiding: "none",
      opacity: "adaptive", floatingApplets: true, config: [{ group: ["PlasmaFusion"], keys: { statusItems: "true" } }],
      widgets: [{ type: "org.plasmafusion.quicksettings", shortcut: "Meta+Q",
                  config: [{ group: ["General"], keys: { keyboardPolicy: "touch", note: "a\u2028b" } }] },
                { type: "org.plasmafusion.quicksettings", shortcut: "Meta+W", config: [] },
                { type: "org.example.gone", shortcut: "", config: [] }] }] }));
JS
cat >"$lf/import-layout.js" <<'JS'
if (PHASE === "remove") {
    print(JSON.stringify({ removed: 2 }));
} else {
    var keys = [], n = 0;
    LAYOUT.panels.forEach(function (p) {
        p.widgets.forEach(function (w) {
            n++;
            if (w.shortcut) {
                keys.push({ id: 100 + n, type: w.type, key: w.shortcut });
            }
        });
    });
    print(JSON.stringify({ panels: LAYOUT.panels.length, widgets: 1, screens: 1, notInstalled: ["org.example.gone"], leftOut: 1,
                           keys: keys, importGot: LAYOUT, phase: PHASE }));
}
JS

cat >"$work/inner.sh" <<'EOF2'
set -u
work=$1 kcmctl=$2 powerfx=$3
N=0 FAIL=0
check() { local d=$1; shift; N=$((N + 1)); if "$@"; then echo "ok $N $d"; else FAIL=$((FAIL + 1)); echo "not ok $N $d"; fi; }
# session NAME COMMAND...: the module runs the commands against the stand-in shell; its output in
# $work/NAME.log, the shell's calls in $work/calls.log.
session() {
  local name=$1; shift
  : >"$work/calls.log"
  # The last session's output goes first: the stand-in's redirection happens in the background
  # child, so the wait below could see the old "ready" and start the module before the stand-in
  # shell is there (its actions then do nothing).
  rm -f "$work/mock-session.out"
  python3 "$powerfx/tests/mock-session.py" --address "$DBUS_SESSION_BUS_ADDRESS" --layout "$work/layout.json" \
    --log "$work/calls.log" --node "$(command -v node)" >"$work/mock-session.out" 2>&1 &
  local mock=$!
  # Up to 30 s (a loaded machine, sanitizer builds).
  for _ in $(seq 300); do grep -q ready "$work/mock-session.out" 2>/dev/null && break; sleep 0.1; done
  check "the stand-in shell started ($name)" grep -q ready "$work/mock-session.out"
  grep -q ready "$work/mock-session.out" || sed 's/^/  mock: /' "$work/mock-session.out"
  printf '%s\n' waitshell "$@" waitidle "get errorText" "get infoText" | "$kcmctl" >"$work/$name.log" 2>&1
  kill "$mock" 2>/dev/null; wait "$mock" 2>/dev/null
}
text() { sed -n "s/^kcmctl: $2=//p" "$work/$1.log"; }
json() { python3 -c 'import json, sys; print(eval(sys.argv[2], {"f": json.load(open(sys.argv[1]))}))' "$@"; }
# The layout import-layout.js was given equals the file's (FILE).
import_got() {
  python3 - "$work/calls.log" "$1" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    if '"importGot"' in line:
        sys.exit(0 if json.loads(line.split(" -> ", 1)[1])["importGot"] == json.load(open(sys.argv[2]))["layout"] else 1)
sys.exit(1)
PY
}

# ---- Export: the applied settings, not a change still pending, and the layout the script printed.
export XDG_CONFIG_HOME=$work/config-a
mkdir -p "$XDG_CONFIG_HOME"
# Another decoration than Plasma Fusion's (an Aurorae theme of this HOME), with its button order.
printf '[org.kde.kdecoration2]\nButtonsOnLeft=XIA\nButtonsOnRight=_\nlibrary=org.kde.kwin.aurorae.v2\ntheme=__aurorae__svg__TestTheme\n' >"$XDG_CONFIG_HOME/kwinrc"
mkdir -p "$XDG_DATA_HOME/aurorae/themes/TestTheme"
session export "set glass 1" "set hotCorner false" "set reduceMotion true" "set iconsMode 0" save "set magnifiedSize 70" \
  "call exportSettings $work/export.json"
check "export: the file is written" test -s "$work/export.json"
check "  as a Plasma Fusion settings file of version 1" test "$(json "$work/export.json" 'f["format"], f["version"]')" = "('plasma-fusion-settings', 1)"
check "  with the applied settings" test "$(json "$work/export.json" '[f["settings"][k] for k in ("glass", "hotCorner", "reduceMotion", "iconsMode")]')" = "[1, False, True, 0]"
check "  and not the change still pending (magnifiedSize)" test "$(json "$work/export.json" 'f["settings"]["magnifiedSize"]')" = 62
check "  and the accent and decoration" test "$(json "$work/export.json" '"accentMode" in f["settings"] and "fusionDecoration" in f["settings"]')" = True
check "  the decoration in use, not Plasma Fusion's: its keys" \
  test "$(json "$work/export.json" 'f["settings"]["fusionDecoration"], f["settings"]["decoration"]')" = \
  "(False, {'ButtonsOnLeft': 'XIA', 'ButtonsOnRight': '_', 'library': 'org.kde.kwin.aurorae.v2', 'theme': '__aurorae__svg__TestTheme'})"
check "  and the layout export-layout.js printed (its last line)" \
  test "$(json "$work/export.json" 'f["layout"]["panels"][0]["widgets"][0]["shortcut"], f["layout"]["left"]')" = "('Meta+Q', ['screen', 'copy'])"
check "  and the page says where, and that a panel of a screen not connected is not in it" \
  bash -c "grep -q 'saved in $work/export.json. A panel of a screen that is not connected is not in the file.' '$work/export.log'"
check "  without an error" test -z "$(text export errorText)"

# ---- Import into a fresh HOME ("Top bar on every screen" is on by default: the screens the file
# had no bars for get theirs from ensure-topbars.js, a stand-in here).
export XDG_CONFIG_HOME=$work/config-b
mkdir -p "$XDG_CONFIG_HOME"
printf '[org.kde.kdecoration2]\nButtonsOnLeft=M\nButtonsOnRight=IAX\nlibrary=org.plasmafusion.decoration\ntheme=\n' >"$XDG_CONFIG_HOME/kwinrc"
echo 'print("top bars: stand-in ran");' >"$work/data/plasma/look-and-feel/org.plasmafusion.dark.desktop/contents/layouts/ensure-topbars.js"
session import "call importSettings file://$work/export.json" "get glass" "get hotCorner" "get iconsMode"
check "import: the settings are on the page" bash -c "grep -q '^kcmctl: glass=1' '$work/import.log' && grep -q '^kcmctl: hotCorner=false' '$work/import.log' && grep -q '^kcmctl: iconsMode=0' '$work/import.log'"
check "  and applied (plasmafusionrc, kwinrc, kdeglobals)" bash -c "
  grep -q '^Glass=Reduced' '$XDG_CONFIG_HOME/plasmafusionrc' && grep -q '^AppIcons=designs' '$XDG_CONFIG_HOME/plasmafusionrc' &&
  grep -q '^BorderActivate=9' '$XDG_CONFIG_HOME/kwinrc' && grep -q '^AnimationDurationFactor=0' '$XDG_CONFIG_HOME/kdeglobals'"
check "  import-layout.js got the file's layout" import_got "$work/export.json"
check "  in two steps: the panels there are removed first, then the file's added" bash -c "
  r=\$(grep -n '\"removed\":2' '$work/calls.log' | head -1 | cut -d: -f1); a=\$(grep -n '\"phase\":\"add\"' '$work/calls.log' | head -1 | cut -d: -f1)
  [ -n \"\$r\" ] && [ -n \"\$a\" ] && [ \"\$r\" -lt \"\$a\" ]"
check "  the file's key for quick settings is the one tried" grep -q 'Meta+Q for quick settings' "$work/import.log"
check "  and the second quick settings' own key too" grep -q 'Meta+W for quick settings' "$work/import.log"
check "  the file's decoration is back, with its button order" bash -c "
  [ \"\$(kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key library)\" = org.kde.kwin.aurorae.v2 ] &&
  [ \"\$(kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme)\" = __aurorae__svg__TestTheme ] &&
  [ \"\$(kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft)\" = XIA ]"
check "  ensure-topbars.js gives the other screens their top bars" grep -q 'top bars: stand-in ran' "$work/calls.log"
check "  the page tells what is in place and what was left out" bash -c "
  grep -q 'The settings of export.json are in place. Widgets that are not installed here were left out: org.example.gone. A panel was left out' '$work/import.log'"

# ---- Files that are not settings files of this version change nothing.
cp "$work/export.json" "$work/good.json"
python3 - "$work" <<'PY'
import json, sys
work = sys.argv[1]
good = json.load(open(f"{work}/good.json"))
def write(name, f):
    with open(f"{work}/{name}.json", "w") as out:
        out.write(f if isinstance(f, str) else json.dumps(f))
write("garbage", "{not json")
write("format", dict(good, format="something-else"))
write("version", dict(good, version=2))
write("nopanels", dict(good, layout=dict(good["layout"], panels=[])))
bad = json.loads(json.dumps(good)); bad["layout"]["panels"][0]["location"] = "middle"; write("location", bad)
bad = json.loads(json.dumps(good)); bad["layout"]["panels"][0]["widgets"][0]["config"][0]["keys"]["keyboardPolicy"] = 3; write("keytype", bad)
bad = json.loads(json.dumps(good)); bad["settings"]["glass"] = 7; bad["settings"]["hotCorner"] = "yes"; write("values", bad)
def panel(name, change):
    bad = json.loads(json.dumps(good)); change(bad["layout"]["panels"][0]); write(name, bad)
panel("customlen", lambda p: p.update(lengthMode="custom"))
panel("floating", lambda p: p.update(floating="yes"))
panel("hiding", lambda p: p.update(hiding="sometimes"))
panel("height", lambda p: p.update(height="34"))
panel("applets", lambda p: p.pop("floatingApplets"))
bad = json.loads(json.dumps(good)); bad["settings"]["decoration"] = {"library": "org.example.decoration"}; write("otherdeco", bad)
bad = json.loads(json.dumps(good))
for p in bad["layout"]["panels"]:
    for w in p["widgets"]:
        w["shortcut"] = ""
write("nokeys", bad)
PY
export XDG_CONFIG_HOME=$work/config-c
mkdir -p "$XDG_CONFIG_HOME"
for bad in garbage format version nopanels location keytype customlen floating hiding height applets missing; do
  session "bad-$bad" "call importSettings $work/$bad.json" "get glass"
  check "a bad file ($bad) is refused" grep -q "^kcmctl: errorText=$bad.json cannot be imported: " "$work/bad-$bad.log"
  check "  and nothing is changed" bash -c "grep -q '^kcmctl: glass=0' '$work/bad-$bad.log' && ! grep -q importGot '$work/calls.log' && ! test -e '$XDG_CONFIG_HOME/plasmafusionrc'"
done
session values "get hotCorner" "call importSettings $work/values.json" "get glass" "get hotCorner"
check "values a setting does not take are left as they are" bash -c "grep -q '^kcmctl: glass=0' '$work/values.log' && test \$(grep -c '^kcmctl: hotCorner=true' '$work/values.log') = 2"
check "  and the page says so" grep -q '2 settings in the file have values this version does not take' "$work/values.log"
check "  the rest of the file is in place" bash -c "grep -q importGot '$work/calls.log' && grep -q '^AppIcons=designs' '$XDG_CONFIG_HOME/plasmafusionrc'"

# ---- A decoration that is not installed here is named; a file without keys gives none (no
# default either: the file is what the user had).
session otherdeco "call importSettings $work/otherdeco.json"
check "the file's decoration is not here: the page names it" \
  grep -q 'The window decoration of the file (org.example.decoration) is not installed on this computer.' "$work/otherdeco.log"
session nokeys "call importSettings $work/nokeys.json"
check "a file without keys: none is tried, not Plasma Fusion's Meta+A either" bash -c "
  ! grep -q 'Meta+' '$work/nokeys.log' && grep -q '^kcmctl: errorText=\$' '$work/nokeys.log'"

# ---- The page left right after an import, or System Settings closed during it: the file's panels
# still come (the steps run in one go, not from timers of the page, which would die with it).
session leave "call importSettings $work/good.json" unload "wait 2500"
check "the page left after an import: the file's panels are added" grep -q '"phase":"add"' "$work/calls.log"
session quit "quitafter 1" "call importSettings $work/good.json"
check "System Settings closed during an import: the file's panels are added" grep -q '"phase":"add"' "$work/calls.log"

# ---- The panels removed, the file's could not be added: the page says how to get panels back.
cat >"$work/data/plasma/look-and-feel/org.plasmafusion.dark.desktop/contents/layouts/import-layout.js" <<'JS'
if (PHASE === "remove") {
    print(JSON.stringify({ removed: 2 }));
} else {
    throw new Error("stand-in failure");
}
JS
session addfail "call importSettings $work/good.json"
# (The shell's reason, a stack here, takes lines of its own.)
check "the file's panels not added: the page says so, and what brings panels back" bash -c "
  grep -q '^kcmctl: errorText=The panels of the file could not be added: ' '$work/addfail.log' &&
  grep -q \"Reset Fusion layout brings Plasma Fusion's panels back.\" '$work/addfail.log'"

# ---- An export larger than an import takes (8 MiB) is not written.
cat >"$work/data/plasma/look-and-feel/org.plasmafusion.dark.desktop/contents/layouts/export-layout.js" <<'JS'
print(JSON.stringify({ version: 1, screens: 1, left: [], panels: [
    { screen: 0, location: "top", height: 34, floating: false, lengthMode: "fill", alignment: "center", hiding: "none",
      opacity: "adaptive", floatingApplets: false, config: [],
      widgets: [{ type: "org.plasmafusion.quicksettings", shortcut: "", config: [{ group: ["General"], keys: { big: "x".repeat(9 * 1024 * 1024) } }] }] }] }));
JS
session toolarge "call exportSettings $work/toolarge.json"
check "an export larger than an import takes is refused, and no file is written" bash -c "
  grep -q 'The settings were not exported: the file would be 9.0 MiB, more than the 8 MiB an import takes.' '$work/toolarge.log' &&
  ! test -e '$work/toolarge.json'"

# ---- Without the Global Theme's scripts there is nothing to export or import with.
rm "$work/data/plasma/look-and-feel/org.plasmafusion.dark.desktop/contents/layouts/export-layout.js"
session noscript "get settingsFileAvailable" "call exportSettings $work/none.json"
check "no export-layout.js: the action is not offered, and an export says why" bash -c "
  grep -q '^kcmctl: settingsFileAvailable=false' '$work/noscript.log' && grep -q 'export-layout.js is not installed' '$work/noscript.log' && ! test -e '$work/none.json'"

echo "$((N - FAIL)) of $N passed"
[ "$FAIL" = 0 ]
EOF2

status=0
dbus-run-session --config-file="$here/session-bus.conf" -- bash "$work/inner.sh" "$work" "$kcmctl" "$powerfx" || status=$?
if [ "$status" != 0 ]; then
  for f in "$work"/*.log; do echo "--- $f"; cat "$f"; done
  echo "FAIL: kcmctl-settingsfile"
  exit 1
fi
echo "PASS: kcmctl-settingsfile"
