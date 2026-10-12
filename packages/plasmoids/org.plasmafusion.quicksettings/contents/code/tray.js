.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Hidden tray items while they matter (quick settings, P1). The layout hides vaults, printers,
    display configuration and the input-method item in the system tray next to this widget
    (disabledStatusNotifiers and hiddenItems, so passive ones do not bring the tray's expander
    arrow back); the tray has no key for "hidden while passive". While one of them is active this
    widget puts it into the tray's shownItems, which the 6.7 tray applies before both other lists
    (systemtraymodel.cpp calculateEffectiveStatus), so the stock item shows in the bar with its own
    pop-up, and takes it out again when it is passive. An id the user moved out of
    disabledStatusNotifiers (any choice in the tray's settings does) is the user's and is left
    alone. Tests: tests/tray.test.js (not installed).
*/

var VAULT = "org.kde.plasma.vault";
var PRINTERS = "org.kde.plasma.printmanager";
var DISPLAY = "org.kde.kscreen";
var INPUT_METHOD = "org.kde.plasma.manage-inputmethod";
var MANAGED = [VAULT, PRINTERS, DISPLAY, INPUT_METHOD];

// The managed ids to show now, from the stock items' own state ([{id, active}]: active is the
// applet's status, Active or needing attention), the number of screens and the posture:
// - a vault while one is open, printers while jobs are queued (their own Active status);
// - display configuration in presentation mode (its own Active status) and also while a second
//   screen is connected, when its layout choices (extend, mirror, switch) matter; the 6.7 item
//   is otherwise passive;
// - the input-method switch while it is active, except in tablet posture, where the sheet's
//   tablet row has its own keyboard button (TABLET 4.3) and the item would only repeat it.
function wanted(items, screens, tablet) {
    const out = [];
    for (const item of items || []) {
        const id = String(item.id || "");
        if (MANAGED.indexOf(id) === -1 || out.indexOf(id) !== -1) {
            continue;
        }
        if ((id === VAULT || id === PRINTERS) && item.active) {
            out.push(id);
        } else if (id === DISPLAY && (item.active || screens > 1)) {
            out.push(id);
        } else if (id === INPUT_METHOD && item.active && !tablet) {
            out.push(id);
        }
    }
    return out;
}

// The tray's next shownItems: each managed id the layout hid (in `disabled`) is in it exactly when
// it is wanted; every other entry stays as it is, in its order.
function shownItems(shown, disabled, want) {
    const current = (shown || []).map(String);
    const off = (disabled || []).map(String);
    const ours = MANAGED.filter(id => off.indexOf(id) !== -1);
    const next = current.filter(id => ours.indexOf(id) === -1 || want.indexOf(id) !== -1);
    for (const id of ours) {
        if (want.indexOf(id) !== -1 && next.indexOf(id) === -1) {
            next.push(id);
        }
    }
    return next;
}

// Whether two lists hold the same entries in the same order.
function same(a, b) {
    return a.length === b.length && a.every((v, i) => v === b[i]);
}
