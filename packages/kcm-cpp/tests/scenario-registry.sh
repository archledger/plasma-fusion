# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Test tooling (not installed). The settings registry's rows through the module itself
# (tests/kcmctl: the plugin loaded as System Settings loads it, properties set and Apply called),
# with the written keys read back after each step (checks.txt). Run in a virtual session seeded by
# tests/make-seed.sh (PF_KCMCTL set), like scenario-controls.sh:
#   tools/vsession/remote.sh km-registry packages/kcm-cpp/tests/scenario-registry.sh seed 1440x900 360
exec 2>&1
set -x
source "$HOME/pf-kcm-tests/session-common.sh"
export OUT

# Registry row 15 (High contrast): the switch must write the gsettings key the XDG settings
# portal's contrast is served from. xdg-desktop-portal-kde 6.7.5 does not serve the contrast key
# at all (its appearance keys are color-scheme, accent-color and reduced-motion); the gtk impl
# answers org.freedesktop.appearance contrast from gsettings org.gnome.desktop.a11y.interface
# high-contrast. With the key left at false, apps never see Plasma's high contrast.
kcm <<'EOF'
set highContrast true
call save
waitidle
EOF
check "high contrast writes gsettings on" \
  "$(gsettings get org.gnome.desktop.a11y.interface high-contrast 2>/dev/null | tr -d "'")" "true"

kcm <<'EOF'
set highContrast false
call save
waitidle
EOF
check "high contrast writes gsettings off" \
  "$(gsettings get org.gnome.desktop.a11y.interface high-contrast 2>/dev/null | tr -d "'")" "false"
