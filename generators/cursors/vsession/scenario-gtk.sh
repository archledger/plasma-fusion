# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
# vsession scenario (sourced by tools/vsession/vsession.sh): the Xcursor half of the themes,
# loaded by a GTK 3 app (GTK 3 does not use cursor-shape-v1). The theme name reaches GTK the way
# Plasma's GTK settings sync delivers it: GSettings org.gnome.desktop.interface and settings.ini.
T=$HOME/pfv-cursor-test
gsettings set org.gnome.desktop.interface cursor-theme PlasmaFusion-cursors >"$OUT/gsettings.txt" 2>&1
gsettings set org.gnome.desktop.interface cursor-size 24 >>"$OUT/gsettings.txt" 2>&1
gsettings get org.gnome.desktop.interface cursor-theme >>"$OUT/gsettings.txt" 2>&1
python3 "$T/gtkcursors.py" "$OUT/gtk-cells.json" >"$OUT/gtkapp.log" 2>&1 &
GPID=$!
for _ in $(seq 1 50); do [ -s "$OUT/gtk-cells.json" ] && break; sleep 0.2; done
python3 "$T/eipointer.py" "$OUT/gtk-cells.json" "$OUT" gtk >"$OUT/ei-gtk.log" 2>&1
kill $GPID 2>/dev/null
