.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    The dock's test hook pick:TEXT (debugAction): of a menu's actions as they were added
    (DockMenu.actions, which the dock keeps after the menu is gone), the one to run as a click on
    it would: the one added with this text, if it is enabled.
*/

// The action ({text, run, enabled}; run is null for one that only closes the menu), or null.
function find(actions, text) {
    const action = (actions || []).find(a => a.text === text);
    return action && action.enabled ? action : null;
}
