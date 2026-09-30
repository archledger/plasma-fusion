# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Virtual-session scenario (test tooling): the Window Decorations settings page with the plugin on
# QT_PLUGIN_PATH. Its previews create the decoration and its buttons through the plugin factory
# (a PreviewBridge instead of KWin); this checks that they render and nothing crashes.
#   tools/vsession/remote.sh cx-N packages/decoration-cpp/tests/vsession/scenario-kcm.sh SEED 1440x900 240
. "$HOME/pf-deco/params.sh"
kwinjs() {
  local f=$PFV/helper-$RANDOM.js
  cat >"$f"
  local id
  id=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$f" "pfcx-helper-$RANDOM")
  qdbus org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null 2>&1
  sleep 0.5
}
opts=(--install "$HOME/pf-stage")
[ "$VARIANT" = light ] && opts+=(--light)
bash "$HOME/pf-tools/device/fusion-config.sh" "${opts[@]}" >"$OUT/fusion-config.log" 2>&1
kquitapp6 plasmashell >/dev/null 2>&1
sleep 2
plasmashell >>"$OUT/plasmashell2.log" 2>&1 &
wait_for_name org.kde.plasmashell
sleep 8
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.plasmafusion.decoration
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme ""
qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1
sleep 1
systemsettings kcm_kwindecoration >"$OUT/systemsettings.log" 2>&1 &
sleep 10
kwinjs <<'JS'
const s = workspace.windowList().find(w => (w.resourceClass || "").indexOf("systemsettings") >= 0);
if (s) { s.frameGeometry = {x: 120, y: 60, width: 1200, height: 740}; workspace.activeWindow = s; }
JS
pfinput 'move 1400 800' 'sleep 1.5'
shot k01-kcm-themes
for xy in ${KCM_CLICKS:-}; do
  pfinput "click ${xy%,*} ${xy#*,}" 'sleep 1.5'
  shot "k02-kcm-click-${xy/,/-}"
done
pgrep -u "$(id -u)" -f "^systemsettings" >/dev/null && echo "systemsettings still running" || echo "systemsettings NOT running"
