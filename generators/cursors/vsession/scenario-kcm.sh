# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
# vsession scenario: the cursor settings page (kcm_cursortheme) lists both themes, draws their
# previews from the Xcursor files and offers the board's sizes.
T=$HOME/pfv-cursor-test
kcmshell6 kcm_cursortheme >"$OUT/kcm.log" 2>&1 &
KPID=$!
sleep 7
shot kcm
echo '{"cells":[{"name":"kcm","x":720,"y":300}]}' >"$OUT/kcm-cells.json"
python3 "$T/eipointer.py" "$OUT/kcm-cells.json" "$OUT" pointer >"$OUT/ei-kcm.log" 2>&1
kill $KPID 2>/dev/null
