.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    The quick settings tiles' order and the hidden ones (the sheet's edit mode, 0.5.0). The widget
    keeps two lists in its settings, shared by every quick settings widget (main.qml):
    tileOrder, every tile in the user's order (empty: the default order, which follows each
    release), and hiddenTiles, the tiles taken out of the grid. A tile with a condition (Disks &
    Devices while a device is connected, ...) keeps it: the grid shows a tile when it is not hidden
    and its condition holds, so a hidden one never appears and a shown one only when it applies.
    Tests: tests/tiles.test.js (not installed).
*/

// Every tile of this release, in the default order: the seven that are always there, then the
// ones shown when they apply. A new tile goes into this list where it belongs by default; for a
// user with an own order, merge() places it after the tile it follows here.
var DEFAULT_ORDER = ["wifi", "bluetooth", "nightlight", "dnd", "power", "darkstyle", "keepawake",
                     "devices", "hotspot", "chargelimit", "tabletmode"];

// A list from the settings as a plain array of strings (a KConfig StringList comes to QML as a
// sequence, and an empty one may come as an empty string).
function list(value) {
    if (value === undefined || value === null || value === "") {
        return [];
    }
    if (typeof value === "string") {
        return [value];
    }
    return Array.prototype.slice.call(value).map(String);
}

// Whether two lists hold the same entries in the same order.
function same(a, b) {
    const x = list(a);
    const y = list(b);
    return x.length === y.length && x.every((v, i) => v === y[i]);
}

// The ids of `value` that `known` has, each once, in their order.
function known(value, ids) {
    const all = ids || DEFAULT_ORDER;
    const out = [];
    for (const id of list(value)) {
        if (all.indexOf(id) !== -1 && out.indexOf(id) === -1) {
            out.push(id);
        }
    }
    return out;
}

// The full order from the stored one: the user's tiles in the user's order (ids this release does
// not know and repeats dropped), and every tile the stored order lacks (a tile new in this
// release, or no stored order at all) placed after the tile before it in the default order,
// wherever the user put that one; a tile first in the default order goes first.
function merge(stored, defaults) {
    const order = defaults || DEFAULT_ORDER;
    const out = known(stored, order);
    order.forEach((id, i) => {
        if (out.indexOf(id) !== -1) {
            return;
        }
        let at = 0;
        for (let j = i - 1; j >= 0; --j) {
            const before = out.indexOf(order[j]);
            if (before !== -1) {
                at = before + 1;
                break;
            }
        }
        out.splice(at, 0, id);
    });
    return out;
}

// Whether a tile's condition holds: `conditions` maps an id to false while that tile does not
// apply; an id it does not name always applies.
function applies(id, conditions) {
    return !conditions || conditions[id] !== false;
}

// The tiles in the grid, in order: not hidden, and their condition holds.
function shown(order, hidden, conditions) {
    const off = list(hidden);
    return list(order).filter(id => off.indexOf(id) === -1 && applies(id, conditions));
}

// The hidden tiles that could be shown now (the edit mode's tray), in order: a hidden tile whose
// condition does not hold waits until it does.
function addable(order, hidden, conditions) {
    const off = list(hidden);
    return list(order).filter(id => off.indexOf(id) !== -1 && applies(id, conditions));
}

// The full order after the shown tiles were rearranged to `next` (the same ids in a new order):
// the places the shown tiles had in the full order take them in the new order, and every other
// tile (hidden, or not applying now) keeps its place.
function arrange(order, before, next) {
    const out = list(order);
    const was = list(before);
    const now = list(next);
    let k = 0;
    for (let i = 0; i < out.length && k < now.length; ++i) {
        if (was.indexOf(out[i]) !== -1) {
            out[i] = now[k++];
        }
    }
    return out;
}

// `items` with `id` moved to `index` (clamped to the list).
function moveTo(items, id, index) {
    const out = list(items);
    const from = out.indexOf(id);
    if (from === -1) {
        return out;
    }
    out.splice(from, 1);
    out.splice(Math.max(0, Math.min(out.length, index)), 0, id);
    return out;
}

// `items` with `id` moved by `steps` places (negative: earlier), clamped to the list.
function moveBy(items, id, steps) {
    const from = list(items).indexOf(id);
    return from === -1 ? list(items) : moveTo(items, id, from + steps);
}

// The slot of a grid with `count` tiles in `columns` columns at a point (x, y) of the grid, cells
// of `cellWidth` x `cellHeight` with the gaps between them: where a dragged tile's centre puts it.
function slotAt(x, y, count, columns, cellWidth, cellHeight, columnGap, rowGap) {
    if (count <= 0) {
        return -1;
    }
    const column = Math.max(0, Math.min(columns - 1, Math.floor((x + columnGap / 2) / (cellWidth + columnGap))));
    const row = Math.max(0, Math.floor((y + rowGap / 2) / (cellHeight + rowGap)));
    return Math.min(count - 1, row * columns + column);
}

// The hidden list with `id` hidden (true) or shown again (false). A tile shown again goes back to
// its place in the order.
function setHidden(hidden, id, hide) {
    const out = list(hidden).filter(h => h !== id);
    if (hide) {
        out.push(id);
    }
    return out;
}

// Whether the tiles are as a new user has them (Reset to defaults has nothing to do).
function isDefault(order, hidden) {
    return known(hidden).length === 0 && same(merge(order), DEFAULT_ORDER);
}
