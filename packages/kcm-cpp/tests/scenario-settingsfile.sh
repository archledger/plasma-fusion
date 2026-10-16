# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Test tooling (not installed). "Export my settings…" and "Import settings…" through tests/kcmctl,
# against the real plasmashell, kglobalaccel and the layout part's export-layout.js,
# import-layout.js and ensure-topbars.js, with two screens:
#   1. after the setup, the page and the panels are changed (Reduced glass, the keyboard on touch,
#      56 px magnified icons, a dock on every screen, the pen menu removed, KWin's Breeze window
#      decoration) and exported: the file has the bars of both screens and the main dock, not the
#      copy, and Breeze;
#   2. the page and the layout go back (the settings changed again, the Plasma Fusion decoration,
#      "Reset Fusion layout");
#   3. the import brings back the settings, Breeze, the same panels (the copy made again by "Dock
#      on every screen") and Meta+A on the new quick settings, without an error, and the key the
#      removed app name had (the file gives it none) is no longer kglobalaccel's; after a
#      plasmashell restart the panels are still on their screens.
# Run with PFV_OUTPUTS=2 (make-seed.sh ... dark, PF_KCMCTL set; the stage holds this change's
# look-and-feel part):
#   PFV_OUTPUTS=2 tools/vsession/remote.sh sf-1 packages/kcm-cpp/tests/scenario-settingsfile.sh SEED 1440x900 420
exec 2>&1
set -euo pipefail
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
export OUT
info() { echo "INFO $*" >>"$OUT/checks.txt"; }
trap 'echo "FAIL the scenario stopped at line $LINENO: $BASH_COMMAND" >>"$OUT/checks.txt"' ERR
# The panels: "sSCREEN:LOCATION:widget,widget,..." each, by screen and location; a dock copy is
# "dock(copy)".
layout() {
  evaljs - <<'JS'
var ps = panels(), out = [];
for (var i = 0; i < ps.length; ++i) {
    var names = ps[i].widgets().slice().sort(function (a, b) { return a.index - b.index; }).map(function (w) {
        var name = String(w.type).replace(/^org\.(plasmafusion|kde\.plasma)\./, "");
        w.currentConfigGroup = ["PlasmaFusion"];
        var copy = String(w.readConfig("everyScreenCopy", "")) === "true";
        w.currentConfigGroup = [];
        return name + (copy ? "(copy)" : "");
    });
    out.push("s" + ps[i].screen + ":" + ps[i].location + ":" + names.join(","));
}
print(out.sort().join(" "));
JS
}
file() { python3 -c 'import json, sys; f = json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$OUT/settings.json" "$1"; }

fusion_setup
info "screens: $(evaljs - <<<'print(screenCount);')"

# 1. Changed, then exported.
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.breeze
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme Breeze
qdbus org.kde.KWin /KWin reconfigure
evaljs - <<'JS' >/dev/null
var ps = panels();
for (var i = 0; i < ps.length; ++i) {
    ps[i].widgets("org.plasmafusion.pen").forEach(function (w) { w.remove(); });
}
JS
kcm <<'K'
waitshell
set glass 1
set keyboardPolicy 1
set magnifiedSize 56
set everyDock true
save
wait 2000
get errorText
K
sleep 3
changed=$(layout)
info "changed layout: $changed"
check "changed: no error" "$(lastget errorText)" ""
check "changed: Meta+A on quick settings" "$(wshortcut org.plasmafusion.quicksettings)" "Meta+A"
shot s00-changed
kcm <<K
waitshell
call exportSettings $OUT/settings.json
get errorText
get infoText
K
check "export: no error" "$(lastget errorText)" ""
check "export: the page says where" "$(lastget infoText)" "Your settings are saved in $OUT/settings.json."
check "export: the settings" "$(file '[f["settings"][k] for k in ("glass", "keyboardPolicy", "magnifiedSize", "everyDock")]')" "[1, 1, 56, True]"
check "export: both bars and the main dock, not the copy" \
  "$(file 'sorted((p["screen"], p["location"]) for p in f["layout"]["panels"]), f["layout"]["left"]')" \
  "([(0, 'bottom'), (0, 'top'), (1, 'top')], ['copy'])"
check "export: Breeze, not Plasma Fusion's decoration" "$(file 'f["settings"]["fusionDecoration"], f["settings"]["decoration"]["library"]')" "(False, 'org.kde.breeze')"
check "export: quick settings' key" "$(file '[w["shortcut"] for p in f["layout"]["panels"] for w in p["widgets"] if w["type"] == "org.plasmafusion.quicksettings"][0]')" "Meta+A"

# 2. Back to the defaults: the settings, and the layout rebuilt.
kcm <<'K'
waitshell
set glass 0
set keyboardPolicy 0
set magnifiedSize 62
set everyDock false
call useFusionDecoration
save
wait 2000
call resetLayout
waitidle
get errorText
K
sleep 3
info "reset layout: $(layout)"
check "reset: the layout differs" "$([ "$(layout)" != "$changed" ] && echo differs)" "differs"
check "reset: the Plasma Fusion decoration" "$(ck kwinrc org.kde.kdecoration2 library)" "org.plasmafusion.decoration"
# A key on the app name of this layout, which the file gives none (kglobalaccel keeps it in
# kglobalshortcutsrc as "activate widget ID").
oldapp=$(evaljs - <<'JS'
var ps = panels(), id = -1;
for (var i = 0; i < ps.length && id < 0; ++i) {
    var ws = ps[i].widgets("org.plasmafusion.appname");
    if (ws.length > 0) {
        ws[0].globalShortcut = "Meta+Ctrl+F9";
        id = ws[0].id;
    }
}
print(id);
JS
)
sleep 3
check "reset: the app name holds Meta+Ctrl+F9" "$(grep -c "^activate widget $oldapp=Meta+Ctrl+F9" "$HOME/.config/kglobalshortcutsrc")" 1
shot s01-reset

# 3. Imported.
kcm <<K
waitshell
call importSettings $OUT/settings.json
waitidle
get errorText
get infoText
get glass
get keyboardPolicy
get magnifiedSize
get everyDock
get fusionDecoration
K
sleep 4
check "import: no error" "$(lastget errorText)" ""
check "import: the result" "$(lastget infoText)" "The settings of settings.json are in place. Shortcuts: Meta+A quick settings."
check "import: the page's settings" "$(lastget glass) $(lastget keyboardPolicy) $(lastget magnifiedSize) $(lastget everyDock)" "1 1 56 true"
check "import: Breeze again" "$(ck kwinrc org.kde.kdecoration2 library) $(ck kwinrc org.kde.kdecoration2 theme) $(lastget fusionDecoration)" "org.kde.breeze Breeze false"
check "import: applied (plasmafusionrc)" "$(ck plasmafusionrc Effects Glass) $(ck plasmafusionrc Dock EveryScreen)" "Reduced true"
check "import: the widgets' keys (keyboard, magnified size)" "$(wkey org.plasmafusion.quicksettings keyboardPolicy) $(wkey org.plasmafusion.dock magnifiedSize)" "touch 56"
check "import: the same panels, the copy made again" "$(layout)" "$changed"
check "import: Meta+A on the new quick settings" "$(wshortcut org.plasmafusion.quicksettings)" "Meta+A"
check "import: the removed app name's key is released" "$(grep -c "^activate widget $oldapp=" "$HOME/.config/kglobalshortcutsrc")" 0
shot s02-imported

# The panels stay on their screens when plasmashell starts again (no screen of the exporting
# session is written back).
kquitapp6 plasmashell >/dev/null 2>&1; sleep 3
plasmashell >>"$OUT/plasmashell3.log" 2>&1 &
wait_for_name org.kde.plasmashell; sleep 12
check "restart: the same panels" "$(layout)" "$changed"
check "restart: Meta+A on quick settings" "$(wshortcut org.plasmafusion.quicksettings)" "Meta+A"
shot s03-restarted
info "done"
trap - ERR
set +e
[ "$(grep -c '^FAIL' "$OUT/checks.txt" || true)" = 0 ]
