# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
# Test tooling (not installed). Edge cases for the window decoration, sourced by
# tools/vsession/vsession.sh (seed from make-seed.sh): e1 a small dialog, e2 the dialog squeezed
# below the corner sizes (140x150), e3 BorderSizeAuto=true (Aurorae then uses Normal borders).
source "$HOME/pf-deco/params.sh"
next() { qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "PF DC Next Step"; sleep 1.5; }
dolphin --new-window "$HOME" >"$OUT/dolphin.log" 2>&1 &
sleep 5
kdialog --title "Save changes?" --yesno "Save changes to the document before closing?" >"$OUT/kdialog.log" 2>&1 &
sleep 4
PHASES='[[{"match":"dolphin","rect":[80,80,760,500]},{"match":"kdialog","activate":true}],[{"match":"kdialog","rect":[900,120,140,110],"activate":true}],[{"match":"kdialog","rect":[900,120,420,160],"activate":true}]]'
sed "s|@PHASES@|$PHASES|" "$HOME/pf-deco/steps.qml.in" >"$PFV/steps.qml"
id=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript "$PFV/steps.qml" pfdcedge)
qdbus org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run
sleep 2
python3 "$HOME/pf-deco/pointer.py" 700 860
shot e1-dialog
next; shot e2-tiny
next
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSizeAuto true
qdbus org.kde.KWin /KWin reconfigure
sleep 3
shot e3-border-auto
