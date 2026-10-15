// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
.pragma library

// Pure logic of the dynamic workspaces: plain objects in, plain objects out, no KWin types, so the
// node suite (packages/kwin/tests/workspaces.test.js) drives every rule. main.qml reads KWin into
// these shapes and carries out what they decide.

// KWin's ceiling (VirtualDesktopManager::maximum(), the same in 6.7 and 6.8).
const MAXIMUM = 25;

// How long a pass holds back after an event (milliseconds). KWin's slide effect ends its switch
// animation at once when a desktop is added or removed (both call finishedSwitching), and its spring
// settles in about 0.7 s: nothing changes until a second after the last switch. A window that just
// closed may be handing over to the next one of its app (a dialog, a splash screen): its desktop
// stays a second, as in GNOME (LAST_WINDOW_GRACE_TIME). After the script starts, windows a session
// restore brings back look for their desktop by id: nothing is removed for ten seconds.
const SETTLE_MILLIS = 1000;
const GRACE_MILLIS = 1000;
const START_MILLIS = 10000;

// Whether a window is of the kind that can hold a desktop, which does not change while it is open:
// a managed window of the user's, not a panel, notification, OSD, applet popup or tooltip (KWin's
// special windows) and not a popup menu. main.qml watches these windows only.
function candidate(view) {
    return !!view && view.managed === true && view.special !== true && view.popup !== true;
}

// Whether a window holds its desktops now: a candidate that is not closing, not on every desktop
// (KWin's own internal windows are) and not kept out of the pager. Minimized windows count: they
// are still on their desktop.
function counts(view) {
    return candidate(view) && view.deleted !== true && view.allDesktops !== true && view.skipPager !== true;
}

// desktopIds (in KWin's order) -> one boolean each: does a counted window list that desktop. Windows
// of every activity count - KWin's desktops are shared by the activities, and removing one would
// move another activity's windows.
function occupancy(desktopIds, windows) {
    const held = {};
    for (let i = 0; i < windows.length; ++i) {
        const w = windows[i];
        if (!counts(w)) {
            continue;
        }
        const ds = w.desktops || [];
        for (let j = 0; j < ds.length; ++j) {
            held[ds[j]] = true;
        }
    }
    return desktopIds.map(id => held[id] === true);
}

// KeepFirst as a count: a whole number from 0 to 24 (anything unreadable is 0).
function keepCount(value) {
    const n = Math.floor(Number(value));
    if (!Number.isFinite(n) || n < 0) {
        return 0;
    }
    return Math.min(n, MAXIMUM - 1);
}

// What the desktops should become. desktopIds in KWin's order, occupied one boolean each,
// currentIds the desktop shown on each screen (all of them are kept: with per-screen desktops each
// screen has its own), keepFirst how many desktops at the start always stay.
//   append: a desktop is needed at the end (the last one holds windows);
//   remove: the ids of the empty desktops to remove, last first.
// Kept besides those: the empty desktop right after the last occupied one (the one to move windows
// to) and the first keepFirst desktops.
function plan(desktopIds, occupied, currentIds, keepFirst) {
    const n = desktopIds.length;
    const keep = keepCount(keepFirst);
    let lastOccupied = -1;
    for (let i = 0; i < n; ++i) {
        if (occupied[i]) {
            lastOccupied = i;
        }
    }
    const trailing = lastOccupied + 1;
    const current = {};
    for (let i = 0; i < currentIds.length; ++i) {
        current[currentIds[i]] = true;
    }
    const remove = [];
    for (let i = n - 1; i >= 0; --i) {
        const id = desktopIds[i];
        if (occupied[i] || i < keep || i === trailing || current[id]) {
            continue;
        }
        remove.push(id);
    }
    // At least one desktop always stays: the empty one after the last occupied desktop exists unless
    // the last desktop is occupied, and an occupied desktop is never removed. The ceiling counts the
    // desktops that are left: removals in the same pass make room for the one at the end.
    const append = n > 0 && occupied[n - 1] === true && n - remove.length < MAXIMUM;
    return { append: append, remove: remove };
}

// Whether KWin takes one more desktop now (main.qml asks right before it adds one: the removals that
// made room may still be waiting for their moment).
function canAdd(count) {
    return count < MAXIMUM;
}

// What a pass may do now. times: {now, started, lastSwitch, lastClose} in milliseconds (an event
// that never happened is -Infinity). Returns which parts of the plan may run and, when a needed part
// must wait, in how many milliseconds to look again (-1: nothing to wait for).
function decide(wanted, times) {
    const addAt = times.lastSwitch + SETTLE_MILLIS;
    const removeAt = Math.max(addAt, times.lastClose + GRACE_MILLIS, times.started + START_MILLIS);
    const append = wanted.append && times.now >= addAt;
    const remove = wanted.remove.length > 0 && times.now >= removeAt ? wanted.remove.slice() : [];
    let retryIn = -1;
    if (wanted.append && !append) {
        retryIn = addAt - times.now;
    }
    if (wanted.remove.length > 0 && remove.length === 0) {
        const wait = removeAt - times.now;
        retryIn = retryIn < 0 ? wait : Math.min(retryIn, wait);
    }
    return { append: append, remove: remove, retryIn: retryIn < 0 ? -1 : Math.ceil(retryIn) };
}

// The script's own numbered names: numbered[i] is the name of number i + 1 ("Workspace 3"),
// translated by main.qml. Returns the number a name stands for, or 0 when it is another name.
function numberOf(name, numbered) {
    const i = numbered.indexOf(String(name));
    return i < 0 ? 0 : i + 1;
}

// The name a desktop the script adds at position (0-based) gets.
function nameFor(position, numbered) {
    return position >= 0 && position < numbered.length ? numbered[position] : "";
}

// Renames that keep the script's numbered names in step with their positions after removals:
// desktops [{id, name}] in KWin's order -> [{id, name}] to set. Any other name is never touched.
function renames(desktops, numbered) {
    const out = [];
    for (let i = 0; i < desktops.length; ++i) {
        const number = numberOf(desktops[i].name, numbered);
        if (number > 0 && number !== i + 1) {
            const name = nameFor(i, numbered);
            if (name !== "") {
                out.push({ id: desktops[i].id, name: name });
            }
        }
    }
    return out;
}
