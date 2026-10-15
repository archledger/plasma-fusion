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
    let added = false;
    for (let i = 0; i < rest.length; ++i) {
        if (rest[i].indexOf(anchor) >= 0) {
            out.push(rest[i].concat([win]));
            added = true;
        } else {
            out.push(rest[i].slice());
        }
    }
    if (!added) {
        out.push([anchor, win]);
    }
    return out;
}

// The groups together with the zone each member was placed in: {groups, zones}, zones keyed by
// key(win). Zones are kept only for windows that are in a group; a window left alone (the last
// partner of a group of two) is forgotten, so a stale zone can never stand for a later one.
function prune(groups, zones, key) {
    const kept = {};
    for (let i = 0; i < groups.length; ++i) {
        for (let j = 0; j < groups[i].length; ++j) {
            const k = key(groups[i][j]);
            if (zones[k] !== undefined) {
                kept[k] = zones[k];
            }
        }
    }
    return kept;
}

// win joins anchor's group with the zone it was placed in. win leaves its old group first (its
// former partners' bookkeeping with it); an anchor that is in no group yet starts one with the
// zone it holds now, one already in a group keeps the zone it was placed in.
function joined(state, anchor, win, anchorZone, winZone, key) {
    const rest = leave(state.groups, win);
    const zones = prune(rest, state.zones, key);
    if (groupOf(rest, anchor) < 0) {
        zones[key(anchor)] = anchorZone;
    }
    zones[key(win)] = winZone;
    return { groups: join(rest, anchor, win), zones: zones };
}

// win leaves its group (and the zones of windows left alone are forgotten).
function left(state, win, key) {
    const groups = leave(state.groups, win);
    return { groups: groups, zones: prune(groups, state.zones, key) };
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

// ---- validating at use: the decisions read the windows as they are now, so a change no handler
// saw (an app or a script moving a window, a switch in the settle between two offers) still
// counts. The values are plain snapshots taken by main.qml.

function sameRect(a, b) {
    return !!a && !!b && a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height;
}

// Whether two windows share an activity; an empty list means all activities.
function sharedActivity(a, b) {
    if (!a || !b || a.length === 0 || b.length === 0) {
        return true;
    }
    for (let i = 0; i < a.length; ++i) {
        if (b.indexOf(a[i]) >= 0) {
            return true;
        }
    }
    return false;
}

// Whether a window still holds the zone it was placed in. zone: {tile, rect, place}; now: {tile,
// frame, place, maximized, fullScreen, settled}. A plain-geometry zone is asked only once the
// window has settled (a Wayland client answers its resize late; an interactive move is asked when
// it ends).
function holds(zone, now) {
    if (!zone || now.maximized || now.fullScreen || now.place !== zone.place) {
        return false;
    }
    if (zone.tile) {
        return now.tile === zone.tile;
    }
    return !now.tile && (!now.settled || inZone(now.frame, zone.rect));
}

// Whether a fill sequence still stands: its first window holds its chosen zone, and the workspace
// is the one it started on - the same desktop and activity, the same work area and layout family
// (a rotation turns columns into rows). rec: {zone, desktop, activity, area, family}; now: the
// first window's snapshot (holds) plus {desktop, activity, area, family}.
function fillValid(rec, now) {
    if (now.desktop !== rec.desktop || now.activity !== rec.activity || now.family !== rec.family || !sameRect(now.area, rec.area)) {
        return false;
    }
    return holds(rec.zone, now);
}
