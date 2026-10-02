# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# STYLE-1 accent-colour scenario for tools/vsession (sourced inside a private session; test use only).
# Seed: make-style1-seed.sh. Does an AccentColor change recolour Plasma-style accents without a
# shell restart? The PC3 test pop-up (switch, check box, slider, tabs, list highlight) with the
# Fusion style: before, 8 s after `plasma-apply-colorscheme --accent-color`, after a shell restart;
# then the same with Breeze as the control.
exec 2>&1
set -x
T=$HOME/pf-tools
export QT_FORCE_STDERR_LOGGING=1
N=0
restart_shell() { # $1 label
  N=$((N + 1))
  kquitapp6 plasmashell >/dev/null 2>&1
  for _ in $(seq 1 40); do qdbus-qt6 | grep -q org.kde.plasmashell || break; sleep 0.5; done
  plasmashell >"$OUT/plasmashell-$N-$1.log" 2>&1 &
  wait_for_name org.kde.plasmashell
  sleep 9
}
inv() { qdbus-qt6 org.kde.kglobalaccel /component/plasmashell org.kde.kglobalaccel.Component.invokeShortcut "activate widget $1"; }
dismiss_launcher() { kcalc >/dev/null 2>&1 & local kc=$!; sleep 4; kill $kc 2>/dev/null; sleep 2; }
popup() { inv "$PTID"; sleep 2.5; shot "$1"; inv "$PTID"; sleep 1; }
colors() { for k in "Colors:Selection BackgroundNormal" "Colors:Button DecorationFocus"; do
  echo "$1 $k=$(kreadconfig6 --file kdeglobals --group "${k% *}" --key "${k#* }")"; done >>"$OUT/colors.txt"; }

kpackagetool6 -t Plasma/Applet -i "$HOME/pkg/org.plasmafusion.pstest" >/dev/null 2>&1
bash "$T/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc-install.log" 2>&1
PTID=$(evaljs - <<'JS' | tr -dc '0-9'
var ps = panels(); var top = null;
for (var i = 0; i < ps.length; i++) if (ps[i].location == "top") top = ps[i];
var pt = top.addWidget("org.plasmafusion.pstest"); pt.globalShortcut = "Ctrl+Alt+Shift+F4"; print(pt.id);
JS
)
restart_shell start; dismiss_launcher
colors 01-blue; popup d-01-fusion-blue
plasma-apply-colorscheme --accent-color '#1f9e8f' >>"$OUT/accent.log" 2>&1
sleep 8; colors 02-teal; popup d-02-fusion-teal-live
restart_shell teal; popup d-03-fusion-teal-restart
plasma-apply-desktoptheme default >>"$OUT/accent.log" 2>&1
sleep 5; popup d-04-breeze-teal
plasma-apply-colorscheme --accent-color '#e8743b' >>"$OUT/accent.log" 2>&1
sleep 8; colors 05-orange; popup d-05-breeze-orange-live
restart_shell orange; popup d-06-breeze-orange-restart
plasma-apply-desktoptheme plasma-fusion-dark >>"$OUT/accent.log" 2>&1
sleep 5; popup d-07-fusion-orange-live
true
