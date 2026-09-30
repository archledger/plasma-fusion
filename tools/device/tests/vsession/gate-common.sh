# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Helpers for the login-check scenarios (sourced inside a tools/vsession session; test tooling).
# shellcheck shell=bash disable=SC2154

# Values the check and "My previous desktop" care about, as the session reads them.
dump() {
  local k
  {
    echo "== $1"
    for k in "kdeglobals KDE LookAndFeelPackage" "kdeglobals KDE widgetStyle" "kdeglobals General ColorScheme" \
      "kdeglobals Icons Theme" "kdeglobals General font" "kdeglobals General menuFont" "kdeglobals WM activeFont" \
      "kcminputrc Mouse cursorTheme" "plasmarc Theme name" "ksplashrc KSplash Theme" \
      "kwinrc org.kde.kdecoration2 library" "kwinrc org.kde.kdecoration2 theme" \
      "kwinrc org.kde.kdecoration2 ButtonsOnLeft" "kwinrc org.kde.kdecoration2 ButtonsOnRight" \
      "kwinrc TabBox LayoutName" "kwinrc TabBox DesktopMode" "kwinrc TabBoxAlternative LayoutName" \
      "kwinrc Plugins plasmafusion-snapEnabled" "kwinrc Plugins plasmafusion-attachEnabled" "kwinrc Outline QmlPath"; do
      set -- $k
      echo "$1 [$2] $3 = $(kreadconfig6 --file "$1" --group "$2" --key "$3")"
    done
    echo "lock-screen drop-in: $(ls "$HOME/.config/systemd/user/plasma-kwin_wayland.service.d" 2>/dev/null)"
    echo "gate stub: $(ls "$HOME/.config/plasma-workspace/env" 2>/dev/null)"
    echo "gate records: $(grep -vc '^#' "$HOME/.local/state/plasma-fusion/gate/off" 2>/dev/null || echo 0)"
    echo "queued notification: $(head -n1 "$HOME/.local/state/plasma-fusion/gate/notify" 2>/dev/null)"
    echo "KWin: $(kwin_deco) snap=$(qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-snap 2>/dev/null) attach=$(qdbus-qt6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-attach 2>/dev/null)"
  } >>"$OUT/state.txt"
}

kwin_deco() {
  echo "decoration $(qdbus-qt6 org.kde.KWin /KWin supportInformation 2>/dev/null | sed -n '/^Decoration/,/^$/p' | grep -E '^(Plugin|Theme):' | tr '\n' ' ')"
}

# Every file|group|key=value of the files the check, fusion-config.sh and Global Themes write,
# sorted (the order-independent content KConfig reads).
cfgsum() {
  (cd "$HOME/.config" && for f in kwinrc kdeglobals kcminputrc plasmarc ksplashrc plasmafusionrc kdedefaults/* \
    systemd/user/plasma-kwin_wayland.service.d/* plasma-workspace/env/*; do
    [ -f "$f" ] || continue
    awk -v F="$f" '{ t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t) }
      t == "" || t ~ /^#/ { next } t ~ /^\[/ { g = t; next } { sub(/[ \t]*=[ \t]*/, "=", t); print F "|" g "|" t }' "$f"
  done) | LC_ALL=C sort
}

expect() { # LABEL ACTUAL EXPECTED
  if [ "$2" = "$3" ]; then
    echo "PASS $1 ('$2')" >>"$OUT/checks.txt"
  else
    echo "FAIL $1: got '$2', expected '$3'" >>"$OUT/checks.txt"
  fi
}

restart_shell() {
  kquitapp6 plasmashell >/dev/null 2>&1
  sleep 2
  plasmashell >>"$OUT/plasmashell.log" 2>&1 &
  wait_for_name org.kde.plasmashell
  sleep 8
}

# What a login runs: the installed env stub, sourced by startplasma's plasma-sourceenv.sh.
simulated_login() { # LABEL
  /bin/sh /usr/libexec/plasma-sourceenv.sh "$HOME/.config/plasma-workspace/env/plasma-fusion-gate.sh" >/dev/null
  echo "simulated login $1: rc=$?; $(grep ' login: ' "$HOME/.local/state/plasma-fusion/gate.log" 2>/dev/null | tail -n1)" >>"$OUT/checks.txt"
  grep -F "$(date +%Y-%m-%dT%H:%M)" "$HOME/.local/state/plasma-fusion/gate.log" 2>/dev/null | tail -n 12 >"$OUT/gate-login-$1.log"
}
