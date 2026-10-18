/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Full screen off in tablet posture (board TabletSnap.dc.html): a window always has a place, so
    one taken out of full screen takes a half instead of floating where a finger cannot move it.
    Tested by packages/kwin/tests/tablet-snap.test.js (node).
*/

.pragma library

// Which half a quick tile is, from its geometry relative to the work area (the split divider's
// test, SplitDivider.qml).
function isLeft(g) {
    return !!g && g.x < 0.01 && g.width < 0.99 && g.height > 0.99;
}
function isRight(g) {
    return !!g && g.x > 0.01 && g.x + g.width > 0.99 && g.height > 0.99;
}

// The tiles the other windows hold that are shown with w: on its screen, on the current desktop
// and activity (an empty activity list is every activity, as in the snap script), not minimized.
// Plain objects with KWin's window fields (tests pass their own).
function occupiedTiles(w, windows, desktop, activity) {
    const tiles = [];
    for (const o of windows) {
        if (!o || o === w || o.deleted || !o.normalWindow || o.minimized || !o.tile || o.output !== w.output) {
            continue;
        }
        if (!(o.onAllDesktops || Array.from(o.desktops || []).indexOf(desktop) >= 0)) {
            continue;
        }
        const activities = Array.from(o.activities || []).map(String);
        if (activities.length > 0 && activities.indexOf(String(activity)) < 0) {
            continue;
        }
        tiles.push(o.tile.relativeGeometry);
    }
    return tiles;
}

// Where the window goes: {side: "left" | "right", fraction, reset}, or null when it does not fit
// (it floats, as before). The free half, the right one when both are free or both taken. fraction
// is the share of the work area the side has now: what the other window leaves (the split divider
// may have moved it to 1/3 or 2/3), the right tile's share when both are taken, and a half when
// nothing is tiled, where reset asks for the split to go back to the middle (KWin keeps a split
// moved earlier). minWidth: the window's minimum width; areaWidth: the work area's (8 px for the
// split's gaps).
function placeFor(tiles, minWidth, areaWidth) {
    const lefts = tiles.filter(isLeft);
    const rights = tiles.filter(isRight);
    let place;
    if (lefts.length > 0 && rights.length === 0) {
        place = { side: "right", fraction: 1 - Math.max(...lefts.map(g => g.x + g.width)), reset: false };
    } else if (rights.length > 0 && lefts.length === 0) {
        place = { side: "left", fraction: Math.min(...rights.map(g => g.x)), reset: false };
    } else if (lefts.length === 0) {
        place = { side: "right", fraction: 0.5, reset: true };
    } else {
        place = { side: "right", fraction: Math.min(...rights.map(g => g.width)), reset: false };
    }
    return minWidth > place.fraction * areaWidth - 8 ? null : place;
}
