// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
.pragma library

// Pure logic of snap groups: plain values in, plain values out, no KWin types, so the node suite
// (packages/kwin/tests/snap-groups.test.js) drives every rule. main.qml owns the KWin objects.
//
// A group is an array of windows (compared by identity) that were snapped together through the
// picker; a window is in at most one group, and a group always has at least two members.

// Index of the group holding win, or -1.
function groupOf(groups, win) {
    for (let i = 0; i < groups.length; ++i) {
        if (groups[i].indexOf(win) >= 0) {
            return i;
        }
    }
    return -1;
}

// win leaves its group; a group left with one member ends. Returns the new list (the old one is
// left alone, so a QML property assignment sees the change).
function leave(groups, win) {
    const out = [];
    for (let i = 0; i < groups.length; ++i) {
        const members = groups[i].filter(w => w !== win);
        if (members.length >= 2) {
            out.push(members);
        }
    }
    return out;
}

// win joins anchor's group (a new group of the two when anchor has none). win leaves any other
// group first: a window placed into a new arrangement belongs to that one.
function join(groups, anchor, win) {
    if (anchor === win) {
        return groups;
    }
    const rest = leave(groups, win);
    const out = [];
    let joined = false;
    for (let i = 0; i < rest.length; ++i) {
        if (rest[i].indexOf(anchor) >= 0) {
            out.push(rest[i].concat([win]));
            joined = true;
        } else {
            out.push(rest[i].slice());
        }
    }
    if (!joined) {
        out.push([anchor, win]);
    }
    return out;
}

// The other members of win's group (empty when it has none).
function partners(groups, win) {
    const i = groupOf(groups, win);
    return i < 0 ? [] : groups[i].filter(w => w !== win);
}

// The order in which the picker offers a layout's other zones after the user chose one: the zones
// after the chosen one, wrapping around, without the ones that already hold a window.
// occupied: array of booleans, one per zone (missing entries count as free).
function fillOrder(count, chosen, occupied) {
    const out = [];
    for (let k = 1; k < count; ++k) {
        const zone = (chosen + k) % count;
        if (!(occupied && occupied[zone])) {
            out.push(zone);
        }
    }
    return out;
}

// Whether a window's rectangle still sits in a plain-geometry zone (the thirds, which are not KWin
// tiles): its top-left corner within tolerance and no larger than the zone. A window may be a
// little smaller than its zone (a terminal rounds its size to whole character cells).
function inZone(rect, zone, tolerance) {
    const t = tolerance === undefined ? 4 : tolerance;
    return Math.abs(rect.x - zone.x) <= t && Math.abs(rect.y - zone.y) <= t
        && rect.width <= zone.width + t && rect.height <= zone.height + t
        && rect.width >= zone.width / 2 && rect.height >= zone.height / 2;
}
