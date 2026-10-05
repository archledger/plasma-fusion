#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Portal propagation audit (settings registry:
# artifacts/plasma-fusion/2026-10-05-settings-plan/PLAN.md task 1). Run inside a Plasma session.
# Writes each appearance option the way the Fusion KCM does, reads the XDG settings portal back,
# and restores what it changed.
#   tools/tests/settings/portal-audit.sh
# Exit 1 when any mapping fails.
set -uo pipefail

kread() { kreadconfig6 --file "$1" --group "$2" --key "$3" 2>/dev/null || true; }

# --- snapshot what the cases change (empty = the key is absent and is deleted on restore)
ORIG_LNF=$(kread kdeglobals KDE LookAndFeelPackage)
ORIG_LIGHT=$(kread kdeglobals KDE DefaultLightLookAndFeel)
ORIG_DARK=$(kread kdeglobals KDE DefaultDarkLookAndFeel)
ORIG_AUTO=$(kread kdeglobals KDE AutomaticLookAndFeel)
ORIG_SCHEME=$(kread kdeglobals General ColorScheme)
ORIG_ACCENT=$(kread kdeglobals General AccentColor)
ORIG_LASTACCENT=$(kread kdeglobals General LastUsedCustomAccentColor)
ORIG_ACCENTWP=$(kread kdeglobals General accentColorFromWallpaper)
ORIG_MOTION=$(kread kdeglobals KDE AnimationDurationFactor)

restore_key() { # restore_key FILE GROUP KEY VALUE
  if [ -n "$4" ]; then
    kwriteconfig6 --file "$1" --group "$2" --key "$3" "$4"
  else
    kwriteconfig6 --file "$1" --group "$2" --key "$3" --delete
  fi
}

restore() {
  [ -n "$ORIG_LNF" ] && plasma-apply-lookandfeel --apply "$ORIG_LNF" >/dev/null 2>&1
  restore_key kdeglobals KDE DefaultLightLookAndFeel "$ORIG_LIGHT"
  restore_key kdeglobals KDE DefaultDarkLookAndFeel "$ORIG_DARK"
  restore_key kdeglobals KDE AutomaticLookAndFeel "$ORIG_AUTO"
  [ -n "$ORIG_SCHEME" ] && plasma-apply-colorscheme "$ORIG_SCHEME" >/dev/null 2>&1
  restore_key kdeglobals General AccentColor "$ORIG_ACCENT"
  restore_key kdeglobals General LastUsedCustomAccentColor "$ORIG_LASTACCENT"
  restore_key kdeglobals General accentColorFromWallpaper "$ORIG_ACCENTWP"
  restore_key kdeglobals KDE AnimationDurationFactor "$ORIG_MOTION"
}
trap restore EXIT

read_one() { busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
    org.freedesktop.portal.Settings ReadOne ss org.freedesktop.appearance "$1" \
    | sed 's/^v //; s/^(ddd) //; s/^u //; s/^b //; s/^s //'; }

fail=0
check() { # check NAME KEY WANT
  local got
  got=$(read_one "$2")
  if [ "$got" != "$3" ]; then
    echo "FAIL $1: $2 = '$got', want '$3'"
    fail=1
  else
    echo "ok   $1: $2 = $got"
  fi
}

# 1. Style: the Global Theme applies the colour scheme, the portal reports its brightness.
plasma-apply-lookandfeel --apply org.plasmafusion.dark.desktop >/dev/null 2>&1
sleep 2
check "style dark" color-scheme 1
plasma-apply-lookandfeel --apply org.plasmafusion.light.desktop >/dev/null 2>&1
sleep 2
check "style light" color-scheme 2

# 2. Accent: the KCM writes kdeglobals [General] AccentColor and LastUsedCustomAccentColor and
#    re-applies the scheme with the accent (plasma-apply-colorscheme --accent-color). The portal
#    reports the palette highlight, which is Colors:Selection BackgroundNormal
#    (xdg-desktop-portal-kde src/settings.cpp readAccentColor: palette().highlight()). The
#    AccentColor key is what feeds the palette; --accent-color alone does not.
kwriteconfig6 --file kdeglobals --group General --key AccentColor '#3cc4b0'
kwriteconfig6 --file kdeglobals --group General --key LastUsedCustomAccentColor '#3cc4b0'
plasma-apply-colorscheme --accent-color '#3cc4b0' >/dev/null 2>&1
sel_focus=""
sel_bg=""
got=""
# Poll up to 10 s: the palette reaches the portal through KGlobalSettings's notify, which can lag
# behind the config write (observed: up to 3 s and more while another change settles).
for _ in $(seq 1 10); do
  sel_bg=$(kread kdeglobals "Colors:Selection" BackgroundNormal)
  sel_focus=$(kread kdeglobals "Colors:Selection" DecorationFocus)
  got=$(read_one accent-color)
  want=$(python3 -c 'import sys; print("%.6f %.6f %.6f" % tuple(int(v) / 255 for v in sys.argv[1].split(",")))' "$sel_bg")
  if [ "$sel_focus" = "60,196,176" ] && python3 -c 'import sys
a = sys.argv[1].split()
b = sys.argv[2].split()
sys.exit(0 if len(a) == 3 and len(b) == 3 and all(abs(float(x) - float(y)) < 0.01 for x, y in zip(a, b)) else 1)' "$got" "$want"
  then
    break
  fi
  sleep 1
done
if [ "$sel_focus" = "60,196,176" ] && python3 -c 'import sys
a = sys.argv[1].split()
b = sys.argv[2].split()
sys.exit(0 if len(a) == 3 and len(b) == 3 and all(abs(float(x) - float(y)) < 0.01 for x, y in zip(a, b)) else 1)' "$got" "$want"
then
  echo "ok   accent: accent-color = $got (scheme highlight $sel_bg)"
else
  echo "FAIL accent: accent-color = '$got', want '$want' (Selection BackgroundNormal '$sel_bg', DecorationFocus '$sel_focus', want 60,196,176)"
  fail=1
fi

# 15. High contrast on/off (the KCM's switch applies the scheme).
plasma-apply-colorscheme PlasmaFusionHighContrast >/dev/null 2>&1
sleep 2
check "high contrast on" contrast 1
plasma-apply-colorscheme PlasmaFusionDark >/dev/null 2>&1
sleep 2
check "high contrast off" contrast 0

# 5. Reduce motion (the KCM's switch writes AnimationDurationFactor).
kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 0
sleep 2
check "reduce motion on" reduced-motion 1
kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 1
sleep 2
check "reduce motion off" reduced-motion 0

exit $fail
